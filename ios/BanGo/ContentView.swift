// 主畫面：照 Reeder 的結構，沒有下方分頁列，三層頁面左右並排：
//   側邊欄 ｜ 公告時間軸 ｜ 公告內頁 →（原文：App 裡的 Safari）
// 不用系統的導覽堆疊（NavigationStack 一層推一層），改成自己的並排頁面（PageStack.swift），跟 Reeder 一樣：
//   - 往右拉回上一層、往左拉到下一層，頁面都跟著手指走
//   - 每一頁有自己的工具列，換頁時工具列跟著頁面一起滑，不會在兩頁之間變形
//   - 移動中的頁面外圈有一圈亮邊和陰影
// 在側邊欄往左拉，回到上次看的分類；在內頁往左拉，換到時間軸上面那則（比較新的）公告。
// 設定從側邊欄左上角彈出。
// 打開 App 時直接停在「我的公告」的時間軸，按左上角的側邊欄按鈕回到側邊欄。

import SwiftUI

/// 記住目前在第幾層、每一層放什麼；任何畫面都可以叫它換頁
@Observable
final class Router {
    /// 每一頁在第幾層：側邊欄是最底層 0，時間軸 1，內頁 2
    enum Depth {
        static let sidebar = 0, timeline = 1, article = 2
    }

    /// 目前看到的是第幾層
    private(set) var depth = Depth.timeline  // 打開 App 時直接停在時間軸
    /// 時間軸顯示哪一種公告。回到側邊欄後還記得，往左拉就回到這個分類
    private(set) var filter: NoticeFilter = .mine
    /// 內頁顯示哪一則；沒有點進內頁時是 nil
    private(set) var article: Notice?

    var zoomed: ZoomedImage?          // 正在放大的圖片，任何頁面點圖片都設定這個
    var lastOpened: Notice.ID?        // 最後看的那則公告：時間軸上用灰色卡片標出來
    var rowMenu: RowMenu?             // 長按時間軸跳出選單的那一則
    var searching = false             // 時間軸正在搜尋（搜尋列蓋在工具列上）
    var searchQuery = ""
    var toast: String?                // 畫面下方短暫出現的提示，例如「已複製連結」
    var readingList: [Notice] = []    // 點進內頁時那個時間軸上的公告（由新到舊），內頁往左滑換到上面那則用

    /// 換頁動畫：不彈跳，跟 Reeder 一樣乾脆
    static let animation = Animation.spring(duration: 0.35, bounce: 0)

    /// 從側邊欄打開一種公告的時間軸
    func open(_ filter: NoticeFilter) {
        guard depth == Depth.sidebar else { return }  // 連點兩下不會出事
        self.filter = filter
        searching = false
        searchQuery = ""
        withAnimation(Self.animation) { depth = Depth.timeline }
    }

    /// 從時間軸打開一則公告
    func open(_ notice: Notice, in list: [Notice]) {
        guard depth == Depth.timeline else { return }
        readingList = list
        lastOpened = notice.id
        // 收鍵盤（從搜尋結果點進來時）：系統記得誰在打字，打開原文再關掉會把鍵盤叫回來
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        article = notice
        withAnimation(Self.animation) { depth = Depth.article }
    }

    /// 從內頁點分類／主題：直接回到那一類的時間軸
    func jump(to filter: NoticeFilter) {
        guard depth == Depth.article else { return }
        self.filter = filter
        searching = false
        searchQuery = ""
        withAnimation(Self.animation) { depth = Depth.timeline } completion: { [self] in
            if depth < Depth.article { article = nil }
        }
    }

    /// 設定裡換了學校：舊學校的分類、內頁都不適用了，回到「我的公告」
    func schoolChanged() {
        filter = .mine
        article = nil
        readingList = []
        lastOpened = nil
        searching = false
        searchQuery = ""
    }

    /// 回到上一層
    func back() {
        guard depth > Depth.sidebar else { return }
        if depth == Depth.timeline { searching = false; searchQuery = "" }  // 離開時間軸就收起搜尋
        withAnimation(Self.animation) { depth -= 1 } completion: { [self] in
            if depth < Depth.article { article = nil }  // 內頁已經滑走了，不用留著
        }
    }

    /// 拖曳放手後，直接設定停在哪一層（動畫由拖曳那邊負責）
    func settle(at newDepth: Int) {
        depth = newDepth
        if depth < Depth.timeline { searching = false; searchQuery = "" }
        if depth < Depth.article { article = nil }
    }

    /// 收起搜尋列，清空關鍵字
    func closeSearch() {
        withAnimation(.spring(duration: 0.3, bounce: 0)) { searching = false }
        searchQuery = ""
    }

    /// 顯示一下提示，1.5 秒後自己消失
    func showToast(_ text: String) {
        toast = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            if self?.toast == text { self?.toast = nil }
        }
    }

    /// 時間軸上在目前這則上面的那則（比較新）；已經是最上面一則、或不在內頁時是 nil
    var newer: Notice? {
        guard let article, let index = readingList.firstIndex(where: { $0.id == article.id }), index > 0
        else { return nil }
        return readingList[index - 1]
    }

    /// 這一層往左拉，有沒有下一頁可以拉進來：
    /// 側邊欄拉回時間軸；內頁拉進上面那則（比較新的）公告
    var hasForward: Bool { depth == Depth.sidebar || (depth == Depth.article && newer != nil) }

    /// 往左拉到下一頁放手後，直接換過去（動畫由拖曳那邊負責）
    func settleForward() {
        if depth == Depth.article, let next = newer {
            article = next          // 還是在內頁這一層，只是換成上面那則
            lastOpened = next.id    // 時間軸的灰色卡片跟著換到這則
        } else {
            settle(at: depth + 1)
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = NoticeStore()
    @State private var router = Router()

    var body: some View {
        ZStack {
            PageStack()
            // 點圖片放大：直接蓋在 App 最上面，不是打開新畫面
            ZoomLayer()
            // 長按時間軸的選單，也蓋在最上面
            RowMenuLayer()
            ToastLayer()
        }
        .tint(Color.brand)
        .font(.app(.body))  // 設定裡選的字體
        .task {
            AppFont.shared.applyAppearance()  // 導覽列標題也用同一種字體
        }
        .environment(store)
        .environment(router)
        .task { await store.refreshIfStale() }
        .preferredColorScheme(Demo.isOn ? .light : nil)
        .task {
            guard let title = Demo.openTitle,
                  let notice = store.semesterNotices.first(where: { $0.title.hasPrefix(title) }) else { return }
            router.open(notice, in: store.myNotices)
        }
        // 從背景回到 App 也更新（跟 Reeder 一樣）；10 分鐘內更新過就不重複下載
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshIfStale() } }
        }
    }
}

#Preview {
    ContentView()
}
