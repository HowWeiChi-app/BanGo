// 公告時間軸、單則公告、公告內頁，以及打開校網原文的 Safari。全部照 Reeder 排版：
//   - 左上角玻璃膠囊：側邊欄按鈕 ｜ 標題、副標、箭頭；捲下去之後點標題或箭頭會跳出「捲動到」選單
//     （上次讀到的地方／最上面），在最上面時點了沒反應。右上角膠囊：重新整理、搜尋
//   - 長按一則公告跳出選單：閱讀原文、複製連結、分享（RowMenu.swift）
//   - 每則公告：圓形來源頭像 + 來源名稱 + 分類，右上角是「3h」，下面是粗體標題、灰色摘要、圖片
//   - 最後看的那則用立體的玻璃卡片標出來；分隔線是暗線＋亮線的溝，回來時知道看到哪裡
//   - 內頁：來源、大標題、日期、圖片、內文，最後是「原文」連結；往左滑換到上面那則（比較新的）
// 玻璃效果都是系統的導覽列和工具列自己產生的，沒有自己畫。

import SafariServices
import SwiftUI

/// 公告時間軸，可以下拉更新。沒資料、載入中、載入失敗時顯示對應的提示。
struct NoticeTimeline: View {
    @Environment(NoticeStore.self) private var store
    @Environment(Router.self) private var router
    let filter: NoticeFilter

    private var query: String { router.searching ? router.searchQuery : "" }
    @State private var atTop = true  // 列表在最上面：標題的「捲動到」選單不用開
    @State private var scroller = ListScroller()  // 「捲動到」用系統的捲動（有動畫、滑動中也有效）

    /// 這個時間軸的公告；有在搜尋就只留標題或內文符合的
    private var shown: [Notice] {
        let notices = store.notices(filter)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return notices }
        return notices.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.content.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        let visible = shown  // 每次重畫只篩選一次
        let title = store.title(filter)
        ScrollViewReader { proxy in
            List {
                ForEach(visible) { notice in
                    Button {
                        // 已經點進內頁（或正在過去）就不會再開一次；visible 讓內頁往左滑時知道上面那則是哪一則
                        guard router.rowMenu == nil else { return }  // 剛長按打開選單，放開時不要換頁
                        router.open(notice, in: visible)
                    } label: {
                        NoticeRow(notice: notice)
                    }
                    .buttonStyle(CardPressStyle(highlighted: notice.id == router.lastOpened
                                                || notice.id == router.rowMenu?.notice.id))
                    // 長按：自己畫的玻璃選單（RowMenu.swift），不用系統的 contextMenu
                    .modifier(RowMenuTrigger(notice: notice))
                    // 每一則外面都留 14pt，卡片裡面再留 16pt，所以文字離螢幕邊 30pt（跟 Reeder 一樣）。
                    // 不管有沒有卡片，大小都一樣，點下去排版不會跳。
                    // 上 6、下 8：分隔線（2pt）畫在這一行的最下面，這樣卡片上下到分隔線都剛好空 6pt，分隔線在正中間
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 8, trailing: 14))
                    // 分隔線自己畫：系統的只有一條線，Reeder 是「暗線＋亮線」像刻出來的溝，離螢幕邊 32pt
                    .listRowBackground(Color.paper.overlay(alignment: .bottom) { Groove().padding(.horizontal, 32) }
                        .background(ScrollViewFinder(scroller: scroller)))  // 找到列表底下系統的捲動區
                    .listRowSeparator(.hidden)
                    .id(notice.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // 工具列底下是一整條不透明的模糊底，下緣一條線（Reeder 時間軸量出來是 hard，不是漸層的 soft）
            .scrollEdgeEffectStyle(.hard, for: .top)
            // Reeder 在最上面時，工具列後面是一整片紙張顏色，沒有底也沒有線；捲下去才出現
            .scrollEdgeEffectHidden(atTop && !router.searching, for: .top)
            // 硬邊的光影（亮線、暗線、陰影）系統畫不出來，自己疊上去
            .overlay(alignment: .top) {
                // 搜尋時搜尋列一直蓋在內容上面，所以就算在最上面也要有硬邊
                BarEdgeShade().opacity(atTop && !router.searching ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: atTop && !router.searching)
            }
            .paperBackground()
            .refreshable { await store.refresh() }
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top < 1 } action: { _, top in
                atTop = top
            }
            .overlay { placeholder(isEmpty: visible.isEmpty) }
            // 打開公告、或在內頁往左滑換到上面那則時，時間軸把那則捲到中間：回到列表就看得到剛剛讀到哪。
            // 用系統的捲動動畫（ListScroller），跟內頁滑進來同時進行（Reeder 也是一起捲）；
            // proxy.scrollTo 在 List 裡沒有動畫，點了靠下面的公告，時間軸會瞬移一下
            .onChange(of: router.lastOpened) { _, id in
                guard let id, router.depth > Router.Depth.timeline,
                      let row = visible.firstIndex(where: { $0.id == id }) else { return }
                if scroller.scrollView != nil {
                    scroller.scrollTo(row: row)
                } else {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .scrollDismissesKeyboard(.immediately)  // 往下捲就收鍵盤，方便看結果
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)  // 標題改放在左上角的膠囊裡
            .toolbar {
                // 搜尋時工具列的按鈕先收起來，搜尋列蓋在同一個位置（SearchBar，PageStack 疊上去的）。
                // 留一個看不見的項目：工具列整個空掉的話，系統就不畫硬邊和模糊，搜尋列底下內容會直接透出來
                if router.searching {
                    ToolbarItem(placement: .topBarLeading) {
                        Color.clear.frame(width: 1, height: 44).accessibilityHidden(true)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 11) {
                            // 回到側邊欄（Reeder 在這裡放的是側邊欄圖示，不是返回箭頭）
                            Button { router.back() } label: {
                                Image(systemName: "sidebar.left")
                            }
                            .accessibilityLabel(L("側邊欄", "Sidebar"))
                            // 分隔線跟時間軸的一樣：暗線＋亮線的刻痕，只是轉成直的
                            HStack(spacing: 0) {
                                Color.edgeDark.frame(width: 1)
                                Color.grooveLight.frame(width: 1)
                            }
                            .frame(height: 26)
                            // 標題和箭頭是同一顆按鈕：跳出「捲動到」選單（Reeder 的 Scroll To）
                            Menu {
                                Section(L("捲動到", "Scroll To")) {
                                    Button {
                                        if let row = visible.firstIndex(where: { $0.id == router.lastOpened }) { scroller.scrollTo(row: row) }
                                    } label: {
                                        Label(L("上次讀到的地方", "Where I Left Off"), systemImage: "arrow.turn.up.right")
                                        Text(L("回到剛剛看的那則", "Back to the last notice you read"))  // 選單裡的第二行灰字
                                    }
                                    .disabled(!visible.contains { $0.id == router.lastOpened })
                                    Button {
                                        scroller.scrollToTop()
                                    } label: {
                                        Label(L("最上面", "Top"), systemImage: "arrow.up.to.line")
                                        Text(L("回到最新的公告", "Back to the newest notice"))
                                    }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(title).font(.app(.headline)).foregroundStyle(Color.ink)
                                        Text(store.subtitle(filter)).font(.app(.footnote, .medium)).foregroundStyle(Color.inkSecondary)
                                    }
                                    .lineLimit(1)
                                    // 先限制最寬 190，再用 fixedSize 讓工具列照文字寬度排，不然會被擠到看不見
                                    .frame(maxWidth: 190, alignment: .leading)
                                    .fixedSize()
                                    // 在最上面時是淡灰色，捲下去才變深
                                    Image(systemName: "arrow.up.circle")
                                        .foregroundStyle(atTop ? AnyShapeStyle(Color.inkTertiary) : AnyShapeStyle(Color.ink))
                                }
                            }
                            .allowsHitTesting(!atTop)  // 已經在最上面：點了沒反應（跟 Reeder 一樣）
                            .accessibilityLabel(L("捲動到", "Scroll To"))
                        }
                        .padding(.horizontal, 2)
                    }
                    // 兩個按鈕放在同一個 ToolbarItemGroup，系統會把它們包在同一顆玻璃膠囊裡
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        RefreshButton()
                        Button {
                            withAnimation(.spring(duration: 0.3, bounce: 0)) { router.searching = true }
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel(L("搜尋", "Search"))
                    }
                }
            }
            .tint(Color.ink)  // 工具列圖示用深灰色，跟 Reeder 一樣
        }
    }

    @ViewBuilder private func placeholder(isEmpty: Bool) -> some View {
        if store.data == nil && store.isLoading {
            ProgressView(L("載入公告中…", "Loading notices…"))
        } else if store.data == nil, let error = store.errorMessage {
            ContentUnavailableView {
                Label(L("無法載入公告", "Can’t Load Notices"), systemImage: "wifi.slash")
            } description: {
                Text(error)
            } actions: {
                Button(L("重試", "Retry")) { Task { await store.refresh() } }
                    .buttonStyle(.glassProminent)
            }
        } else if store.data != nil && isEmpty {
            if query.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "tray", description: Text(emptyMessage))
            } else {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private var emptyTitle: String {
        filter == .mine && store.subscribed.isEmpty ? L("還沒有訂閱任何類別", "No Subscriptions Yet") : L("沒有符合的公告", "No Matching Notices")
    }

    private var emptyMessage: String {
        filter == .mine ? L("到「設定」打開想看的類別", "Turn on categories in Settings") : L("下拉可以重新整理", "Pull down to refresh")
    }
}

/// 公告的點擊效果：按下去或是最後看的那則，背後出現立體的玻璃卡片（Reeder 的樣子）
private struct CardPressStyle: ButtonStyle {
    let highlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        PressedCard(label: configuration.label, isPressed: configuration.isPressed, highlighted: highlighted)
    }
}

/// 按下去的樣子：立刻亮起玻璃卡片；按住超過 0.2 秒才往下沉（縮小一點），放開彈回來。
/// 不一碰到就沉：手指只是要捲動時，卡片不會先縮一下
private struct PressedCard<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let highlighted: Bool
    @State private var sunk = false

    var body: some View {
        label
            .padding(16)
            .background {
                // 立體的玻璃卡片（外圈暗線、內圈亮線、淡陰影），圓角跟 Reeder 一樣約 18pt
                GlassCard(cornerRadius: 18)
                    .opacity(isPressed || highlighted ? 1 : 0)
            }
            .contentShape(.rect(cornerRadius: 18))
            .scaleEffect(sunk ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: isPressed)
            .animation(.spring(duration: 0.3, bounce: 0.3), value: sunk)
            .task(id: isPressed) {
                guard isPressed else { sunk = false; return }
                try? await Task.sleep(for: .milliseconds(200))
                if !Task.isCancelled { sunk = true }
            }
    }
}

/// 右上角的重新整理按鈕，載入中會變成轉圈圈
struct RefreshButton: View {
    @Environment(NoticeStore.self) private var store
    @State private var finishing = false  // 更新完了，箭頭還在轉最後那一圈

    /// 更新中、還有轉完最後那一圈之前都不能按
    private var locked: Bool { store.isLoading || finishing }

    var body: some View {
        Button {
            Task { await store.refresh() }
        } label: {
            // 更新中箭頭一直轉，更新完轉完這一圈再停；停好了才解鎖
            SpinningArrow(spinning: store.isLoading, dimmed: locked) { finishing = false }
        }
        // 不能按：工具列按鈕的標籤是自己畫的（UIKit），只加 disabled 擋不住、看起來也沒變，
        // 所以直接不收觸控，箭頭也變淡（照樣在轉）
        .disabled(locked)
        .allowsHitTesting(!locked)
        .onChange(of: store.isLoading) { _, loading in
            if loading { finishing = true }  // 開始轉就鎖住，等箭頭說轉完了才解開
        }
        .tint(Color.ink)
        .accessibilityLabel(L("重新整理", "Refresh"))
    }
}

/// 重新整理的箭頭。轉動交給 Core Animation（在系統的繪圖程序裡跑），不是 SwiftUI 每一格去算：
/// 更新的時候 App 正忙著下載、解析公告，SwiftUI 的動畫會跟著卡、抽動。
/// Reeder 也是這樣：REA 看到它的轉圈（CoreActivityIndicatorView）設定了 usesThreadedAnimation，動畫不在主執行緒上跑
struct SpinningArrow: UIViewRepresentable {
    var spinning: Bool
    var dimmed = false
    /// 停下來時轉完最後那一圈的時候呼叫
    var onStopped: () -> Void = {}

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: Self.centered(Self.symbol))
        view.tintColor = UIColor(Color.ink)
        view.contentMode = .center
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    /// 要繞「圓圈」的中心轉，不是整張圖的中心：箭頭尖凸在右上角，圖案外框的中心比圓心高。
    /// 在電腦上把 arrow.clockwise 畫出來逐點量過：圓心在圖片寬 49.5%、高 57.6% 的地方。
    /// 重新畫一張正方形的圖，讓圓心剛好在正中間，轉起來就在原地
    private static let symbol = UIImage(systemName: "arrow.clockwise",
                                        withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .large))

    private static func centered(_ image: UIImage?) -> UIImage? {
        guard let image else { return nil }
        let w = image.size.width, h = image.size.height
        let cx = w * 0.495, cy = h * 0.576
        let half = max(cx, w - cx, cy, h - cy)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: half * 2, height: half * 2))
        let drawn = renderer.image { _ in
            image.draw(at: CGPoint(x: half - cx, y: half - cy))
        }
        return drawn.withRenderingMode(.alwaysTemplate)
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        // 更新中變淡，看得出來現在不能按
        let tint = UIColor(dimmed ? Color.inkTertiary : Color.ink)
        if view.tintColor != tint {
            UIView.transition(with: view, duration: 0.2, options: .transitionCrossDissolve) { view.tintColor = tint }
        }
        let layer = view.layer
        let key = "spin"
        if spinning {
            guard layer.animation(forKey: key) == nil else { return }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * Double.pi
            spin.duration = 0.9
            spin.repeatCount = .infinity
            layer.add(spin, forKey: key)
        } else if layer.animation(forKey: key) != nil {
            // 不要一下跳回原位：從現在的角度轉完這一圈，慢慢停下來
            let angle = (layer.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double) ?? 0
            let current = angle < 0 ? angle + 2 * .pi : angle
            layer.removeAnimation(forKey: key)
            let finish = CABasicAnimation(keyPath: "transform.rotation.z")
            finish.fromValue = current
            finish.toValue = 2 * Double.pi
            finish.duration = max(0.15, (2 * .pi - current) / (2 * .pi) * 0.9 * 1.4)
            finish.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let stopped = onStopped
            CATransaction.begin()
            CATransaction.setCompletionBlock { stopped() }
            layer.add(finish, forKey: "finish")
            CATransaction.commit()
        } else if layer.animation(forKey: "finish") == nil {
            // 已經沒在轉（例如 App 到背景時系統把動畫拿掉了，收不到轉完的通知）：直接解鎖，按鈕才不會一直鎖著
            let stopped = onStopped
            DispatchQueue.main.async { stopped() }
        }
    }
}

/// 單則公告
struct NoticeRow: View {
    let notice: Notice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SourceAvatar(source: notice.source, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(TagName.display(SourceStyle.name(notice.source)))
                        .font(.app(.headline))
                        .foregroundStyle(Color.ink)
                    Text(subtitle)
                        .font(.app(.subheadline, .medium))
                        .foregroundStyle(Color.inkTertiary)
                        .lineLimit(1)
                }
                .padding(.top, 2)
                Spacer(minLength: 8)
                Text(notice.relativeTime)
                    .font(.app(.subheadline, .medium))
                    .foregroundStyle(Color.inkTertiary)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.app(.headline))
                    .foregroundStyle(notice.isUrgent ? Color.red : Color.ink)
                    .lineLimit(4)
                if !notice.summary.isEmpty {
                    Text(notice.summary)
                        .font(.app(.body, .medium))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(4)
                }
            }
            .multilineTextAlignment(.leading)

            if let url = notice.imageURL {
                NoticeImage(url: url, cropTall: true)
            }
        }
        // 跟學生無關的公告整則淡一點
        .opacity(notice.forStudents ? 1 : 0.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// 頭像旁邊第二行：分類，例如「教務 · #考試」；沒有分類就寫學校名稱
    private var subtitle: String {
        var parts = notice.tags.map(TagName.displayTag)
        if notice.isUrgent { parts.insert(L("緊急", "Urgent"), at: 0) }
        if !notice.forStudents { parts.append(L("跟學生無關", "Not for students")) }
        return parts.isEmpty ? AppSettings.shared.school.displayName : parts.joined(separator: " · ")
    }
}

/// 公告內頁的一則：照 Reeder 的文章頁。每一則有自己的 NavigationStack 和工具列，工具列跟著那一頁一起滑。
/// 往左滑換到時間軸上面那則（比較新的）、往右滑回時間軸，都由 PageStack 處理：
/// 拉進來的那則跟三層頁面是同一排的頁面（不是包在這一頁裡面），
/// 兩層頁面疊在一起裁圓角的話，拉進來那則的內文不會畫出來
struct NoticeDetailView: View {
    @Environment(Router.self) private var router
    let notice: Notice

    var body: some View {
        NavigationStack {
            NoticeArticle(notice: notice)
                .equatable()  // 拉的時候每一格畫面都會重畫，內文沒變就不用重排
                .paperBackground()
                .navigationBarTitleDisplayMode(.inline)  // 標題在內文裡，導覽列不用留大標題的空間
                .toolbar(removing: .title)
                .toolbar { toolbar }
                .tint(Color.ink)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // 返回時間軸（內頁是自己那一層的第一頁，系統不會自動放返回鍵）
        ToolbarItem(placement: .topBarLeading) {
            Button { router.back() } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(L("返回", "Back"))
        }
        if let url = URL(string: notice.url) {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { SafariPage.open(url) } label: { Image(systemName: "safari") }
                    .accessibilityLabel(L("閱讀原文", "Open Original"))
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
            }
        }
    }
}

/// 一則公告的內文：內頁裡上下捲動的那一頁
private struct NoticeArticle: View, Equatable {
    let notice: Notice

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    SourceAvatar(source: notice.source, size: 34)
                    Text(URL(string: notice.url)?.host() ?? "")
                        .font(.app(.headline))
                        .foregroundStyle(Color.ink)
                }
                .padding(.bottom, 14)

                Text(notice.title)
                    .font(.app(.largeTitle, .bold))
                    .foregroundStyle(notice.isUrgent ? Color.red : Color.ink)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(notice.longDate)
                    // 學校 · 分類，有處室（北一女、成功、中山）再加處室
                    Text(([AppSettings.shared.school.displayName, TagName.display(SourceStyle.name(notice.source)), notice.dept]
                        .filter { !$0.isEmpty }).joined(separator: " · "))
                }
                .font(.app(.subheadline, .semibold))
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 8)

                if !notice.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        // 點分類／主題直接跳到那一類的時間軸
                        ForEach(notice.tags, id: \.self) { tag in
                            TagLink(tag: tag)
                        }
                    }
                    .font(.app(.body, .semibold))
                    .foregroundStyle(Color.brand)
                    .padding(.top, 24)
                }

                if let imageURL = notice.imageURL {
                    NoticeImage(url: imageURL)
                        .padding(.top, 24)
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(notice.content.split(separator: "\n").enumerated()), id: \.offset) { _, paragraph in
                        Text(Linkify.attributed(String(paragraph)))  // 內文裡的網址變成可以點的連結
                    }
                    // 「原文」連結，跟 Reeder 一樣用主色
                    if let url = URL(string: notice.url) {
                        Button { SafariPage.open(url) } label: {
                            Text(L("[原文]", "[Original]")).fontWeight(.semibold)
                        }
                        .foregroundStyle(Color.brand)
                    }
                }
                .font(.app(.body))
                .foregroundStyle(Color.ink)  // Reeder 的 articleText 跟標題同一個顏色
                .lineSpacing(5)
                .textSelection(.enabled)
                .padding(.top, 24)

                // 校網內頁的附件（PDF 每頁直接放上來）和參考網站。
                // 五間學校的內頁格式都看得懂（ExtrasLoader.supports）
                if ExtrasLoader.supports(notice.url) {
                    NoticeExtrasView(pageURL: notice.url)
                }
            }
            // 撐滿整個寬度、靠左：不然內容短的公告整塊比較窄，會被捲動區置中，每則左右留的空不一樣
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        // 上方安全區：內文捲到導覽列底下時，越往上越模糊、越暗（iOS 26 的捲動邊緣效果，Reeder 也是）
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background { Color.paper.ignoresSafeArea() }  // 不透明：換頁時才蓋得住後面那則
        // 內文連結用 App 裡的 Safari 打開（跟「原文」一樣），不要跳出 App
        .environment(\.openURL, OpenURLAction { url in
            guard ["http", "https"].contains(url.scheme?.lowercased()) else { return .systemAction }
            SafariPage.open(url)
            return .handled
        })
    }
}

/// 內頁的分類／主題：點了跳到那一類的時間軸
private struct TagLink: View {
    @Environment(Router.self) private var router
    let tag: String

    var body: some View {
        Button {
            // tags 裡主題前面有 #，篩選用的名稱不含 #
            router.jump(to: .tag(tag.hasPrefix("#") ? String(tag.dropFirst()) : tag))
        } label: {
            Label(TagName.displayTag(tag), systemImage: "circle.fill")
                .labelStyle(BulletLabelStyle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("打開這一類的公告", "Show notices in this category"))
    }
}

/// 把文字裡的網址變成連結
enum Linkify {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    @MainActor static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector, text.contains(".") else { return result }
        let ns = text as NSString
        for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            // 網址後面緊接著中文時，偵測有時會把中文也算進去：只留到第一個非 ASCII 字元
            var raw = ns.substring(with: match.range)
            if let cut = raw.firstIndex(where: { !$0.isASCII }) { raw = String(raw[..<cut]) }
            while let last = raw.last, ".,;:)）".contains(last) { raw.removeLast() }
            guard !raw.isEmpty, let start = Range(NSRange(location: match.range.location, length: (raw as NSString).length), in: text),
                  let range = Range(start, in: result) else { continue }
            let url = raw.contains("://") || raw.hasPrefix("mailto:") ? URL(string: raw) : URL(string: "https://" + raw)
            guard let url else { continue }
            result[range].link = url
            result[range].foregroundColor = Color.brand
        }
        return result
    }
}

/// 前面是小圓點的清單樣式
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.icon.font(.system(size: 6)).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3 }
            configuration.title
        }
    }
}

/// 在 App 裡用 Safari 打開校網原文。
/// 照 Reeder：原文是公告內頁的下一層，從右邊推進來，不是從下面彈出來的卡片；
/// 看完按左上角，或從螢幕左邊緣往右滑，就回到公告。
enum SafariPage {
    static func open(_ url: URL) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        guard !(top is SFSafariViewController) else { return }  // 連點兩下不會開兩個
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = UIColor(Color.brand)
        // 系統預設的開法就是從右邊推進來（跟換頁一樣），不要包成 sheet
        top.present(safari, animated: true)
    }
}

/// 搜尋列。不用系統的 searchable，照 Reeder 自己做（REA：Reeder 用自己的 Glass.SearchPopover）：
/// 系統的搜尋框第一次會出現在鍵盤上面、之後又跑到最上面，而且打開、關閉時整個列表會重建，畫面會抽動。
/// 這裡在時間軸那一頁的最上面疊一層，剛好蓋在工具列的位置（工具列的按鈕這時候收起來了），列表完全不動
struct SearchBar: View {
    @Environment(Router.self) private var router
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var router = router
        if router.searching {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.inkSecondary)
                    TextField(L("搜尋標題和內文", "Search titles and text"), text: $router.searchQuery)
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(Color.ink)
                    if !router.searchQuery.isEmpty {
                        Button { router.searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.inkTertiary)
                        }
                        .accessibilityLabel(L("清除", "Clear"))
                    }
                }
                .font(.app(.body))
                .padding(.horizontal, 16)
                .frame(height: 44)
                .glassEffect(.regular.interactive(), in: .capsule)

                Button {
                    // 先收鍵盤再收搜尋列：等搜尋列動畫跑完才收的話，鍵盤會慢半拍
                    focused = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    router.closeSearch()
                } label: {
                    Image(systemName: "xmark")
                        .font(.app(.body, .medium))
                        .foregroundStyle(Color.ink)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(L("關閉搜尋", "Close Search"))
            }
            .padding(.horizontal, 16)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .onAppear { focused = true }
            // 從搜尋結果點進公告就收鍵盤：不然打開原文再回來，系統會把焦點還給搜尋框、鍵盤又跳出來
            .onChange(of: router.depth) { _, depth in
                if depth != Router.Depth.timeline { focused = false }
            }
        }
    }
}

/// 「捲動到」：直接用 List 底下系統的捲動區（UICollectionView）。
/// SwiftUI 的 proxy.scrollTo 在 List 裡沒有動畫（直接瞬移），而且列表還在慣性滑動時會被滑動蓋掉、看起來沒反應；
/// 系統的 setContentOffset / scrollToItem 會先停下慣性，再用跟點狀態列一樣的動畫捲過去
final class ListScroller {
    weak var scrollView: UIScrollView?

    func scrollToTop() {
        guard let view = scrollView else { return }
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: -view.adjustedContentInset.top), animated: true)
    }

    func scrollTo(row: Int) {
        guard let view = scrollView as? UICollectionView, view.numberOfSections > 0,
              row < view.numberOfItems(inSection: 0) else { return }
        view.scrollToItem(at: IndexPath(item: row, section: 0), at: .centeredVertically, animated: true)
    }
}

/// 放在列表每一行的背景裡：往上找到包住它的捲動區，記下來（找到一次就好）
struct ScrollViewFinder: UIViewRepresentable {
    let scroller: ListScroller

    func makeUIView(context: Context) -> Finder { Finder(scroller: scroller) }
    func updateUIView(_ view: Finder, context: Context) {}

    final class Finder: UIView {
        let scroller: ListScroller
        init(scroller: ListScroller) {
            self.scroller = scroller
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, scroller.scrollView == nil else { return }
            var view = superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    scroller.scrollView = scrollView
                    return
                }
                view = current.superview
            }
        }
    }
}
