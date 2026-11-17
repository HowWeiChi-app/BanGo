// 公告內頁下面的「參考資料」（附件）和「參考網站」。
// RSS 裡沒有（或不完整），所以打開內頁時才去抓校網那一頁，從 HTML 裡找出來。各校的系統不一樣：
//   師大附中   <div class="file_odd"><h3>參考資料</h3> … <a class="download_btn …" href="/static/webroot/….pdf" download="檔名.pdf">
//              <div class="link_odd"><h3>參考網站</h3> … <a href="https://…" title="名稱">名稱</a>
//   建中（NSS）  附件標題 {{ $t('FEZ012') }} 底下，一個檔案一顆按鈕：<button …><a href="/uploads/….pdf"><span><svg…/> 檔名.pdf</span></a>
//   北一女、成功、中山（WordPress）  內文裡 <ul class="nojs_modal_list"><li><a href="https://…/wp-content/uploads/….pdf">檔名.pdf</a>
// 附件在背景下載，PDF 每一頁畫成圖片直接放在頁面上（點了可以放大）；圖片附件直接顯示。

import SwiftUI
import PDFKit

nonisolated struct RefLink: Hashable, Sendable {
    let title: String
    let url: URL
}

nonisolated struct Attachment: Hashable, Sendable {
    let name: String
    let url: URL
    var isPDF: Bool { url.pathExtension.lowercased() == "pdf" || name.lowercased().hasSuffix(".pdf") }
    var isImage: Bool { ["jpg", "jpeg", "png", "gif", "heic"].contains(url.pathExtension.lowercased()) }
}

nonisolated struct PageExtras: Sendable {
    var files: [Attachment] = []
    var links: [RefLink] = []
}

/// 附件解析出來的內容
nonisolated enum FileContent: Sendable {
    case pdf(PDFPages)
    case unsupported           // Word、Excel 這類，只給下載
    case failed
}

/// 下載好的 PDF。頁面要顯示時才畫（不一次全部畫好，不然很吃記憶體），畫好的放快取
nonisolated final class PDFPages: @unchecked Sendable {
    static let maxShown = 10   // 最多顯示幾頁，再多就點檔名看
    private let document: PDFDocument
    private let lock = NSLock()   // PDFKit 不保證多執行緒同時畫同一份文件沒問題
    private let key: String
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 120_000_000
        return cache
    }()

    init(document: PDFDocument, key: String) {
        self.document = document
        self.key = key
    }

    var pageCount: Int { lock.withLock { document.pageCount } }

    /// 寬 ÷ 高
    func ratio(_ index: Int) -> CGFloat {
        lock.withLock {
            guard let page = document.page(at: index) else { return 1 / 1.414 }
            let b = page.bounds(for: .cropBox)
            // 橫放的頁面（rotation 90/270）寬高對調
            let (w, h) = page.rotation % 180 == 0 ? (b.width, b.height) : (b.height, b.width)
            return h > 0 ? w / h : 1 / 1.414
        }
    }

    func cached(_ index: Int, width: CGFloat) -> UIImage? {
        Self.cache.object(forKey: "\(key)#\(index)@\(Int(width))" as NSString)
    }

    /// 畫一頁，寬 width 像素
    func render(_ index: Int, width: CGFloat) -> UIImage? {
        let cacheKey = "\(key)#\(index)@\(Int(width))" as NSString
        if let image = Self.cache.object(forKey: cacheKey) { return image }
        let image: UIImage? = lock.withLock {
            guard let page = document.page(at: index) else { return nil }
            let ratio = { let b = page.bounds(for: .cropBox)
                return page.rotation % 180 == 0 ? b.width / b.height : b.height / b.width }()
            guard ratio > 0 else { return nil }
            // 自己畫，不用 page.thumbnail：thumbnail 實際畫出來的像素比要的少，看起來糊。
            // 這裡倍率設 1，圖片就剛好 width 像素寬
            let size = CGSize(width: width.rounded(), height: (width / ratio).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let cg = context.cgContext
                // PDF 的座標是左下角原點、往上為正：翻過來，再縮放到要的寬度
                cg.translateBy(x: 0, y: size.height)
                let scale = width / (page.rotation % 180 == 0 ? page.bounds(for: .cropBox).width : page.bounds(for: .cropBox).height)
                cg.scaleBy(x: scale, y: -scale)
                cg.concatenate(page.transform(for: .cropBox))  // 處理頁面的旋轉、裁切框的原點
                page.draw(with: .cropBox, to: cg)
            }
        }
        if let image, let cg = image.cgImage {
            Self.cache.setObject(image, forKey: cacheKey, cost: cg.bytesPerRow * cg.height)
        }
        return image
    }
}

/// 抓內頁、下載附件，結果記在記憶體裡：同一則來回滑不用重抓
actor ExtrasLoader {
    static let shared = ExtrasLoader()

    /// 看得懂附件格式的學校（校網網址）
    nonisolated static func supports(_ pageURL: String) -> Bool {
        guard let host = URL(string: pageURL)?.host() else { return false }
        return ["www.hs.ntnu.edu.tw", "www.ck.tp.edu.tw", "www.fg.tp.edu.tw", "www.cksh.tp.edu.tw", "www.csghs.tp.edu.tw"]
            .contains(host)
    }
    private static let maxFileBytes = 15_000_000

    private var pages: [String: PageExtras] = [:]
    private var files: [URL: FileContent] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "SchoolNoticeApp/1.0 (student project)"]
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    /// 內頁的附件和參考網站；抓不到回傳 nil
    func extras(for pageURL: String) async -> PageExtras? {
        if let cached = pages[pageURL] { return cached }
        guard let url = URL(string: pageURL),
              let (data, _) = try? await session.data(from: url),
              let html = String(data: data, encoding: .utf8) else { return nil }
        let result = Self.parse(html, page: url)
        pages[pageURL] = result
        return result
    }

    /// 下載一個附件並取出內容
    func content(of file: Attachment) async -> FileContent {
        if let cached = files[file.url] { return cached }
        let result: FileContent
        if !file.isPDF {
            result = .unsupported
        } else if let (data, _) = try? await session.data(from: file.url), data.count <= Self.maxFileBytes,
                  let document = PDFDocument(data: data), document.pageCount > 0 {
            result = .pdf(PDFPages(document: document, key: file.url.absoluteString))
        } else {
            result = .failed
        }
        files[file.url] = result
        return result
    }

    // MARK: - 解析 HTML

    nonisolated static func parse(_ html: String, page: URL) -> PageExtras {
        switch page.host() {
        case "www.hs.ntnu.edu.tw": parseHSNU(html, base: page)
        case "www.ck.tp.edu.tw": parseNSS(html, base: page)
        default: parseWordPress(html, base: page)
        }
    }

    /// 師大附中：參考資料、參考網站兩塊
    private nonisolated static func parseHSNU(_ html: String, base: URL) -> PageExtras {
        var extras = PageExtras()
        if let block = section(html, className: "file_odd") {
            for tag in block.matches(of: /<a\b[^>]*download_btn[^>]*>/) {
                let attrs = String(tag.output)
                guard let href = attribute("href", in: attrs),
                      let url = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
                let name = attribute("download", in: attrs) ?? url.lastPathComponent
                extras.files.append(Attachment(name: decode(name), url: url))
            }
        }
        if let block = section(html, className: "link_odd") {
            for match in block.matches(of: /<a\b([^>]*)>(.*?)<\/a>/.dotMatchesNewlines()) {
                let attrs = String(match.output.1)
                guard let href = attribute("href", in: attrs),
                      let url = URL(string: decode(href), relativeTo: base)?.absoluteURL else { continue }
                let text = plainText(String(match.output.2))
                let title = text.isEmpty ? (attribute("title", in: attrs).map(decode) ?? url.absoluteString) : text
                extras.links.append(RefLink(title: title, url: url))
            }
        }
        return extras
    }

    /// 建中（NSS）：附件標題 FEZ012、相關連結標題 FEZ013，兩塊在同一條 <hr> 之前；每個 <a> 是一個檔案／連結
    private nonisolated static func parseNSS(_ html: String, base: URL) -> PageExtras {
        var extras = PageExtras()
        let fileMark = html.range(of: "FEZ012"), linkMark = html.range(of: "FEZ013")
        guard let first = [fileMark, linkMark].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }),
              let end = html.range(of: "<hr", range: first.upperBound..<html.endIndex) else { return extras }
        if let fileMark, fileMark.upperBound < end.lowerBound {
            let stop = linkMark.map { $0.lowerBound > fileMark.upperBound ? min($0.lowerBound, end.lowerBound) : end.lowerBound }
                ?? end.lowerBound
            extras.files = files(in: html[fileMark.upperBound..<stop], base: base)
        }
        if let linkMark, linkMark.upperBound < end.lowerBound {
            extras.links = files(in: html[linkMark.upperBound..<end.lowerBound], base: base)
                .map { RefLink(title: $0.name, url: $0.url) }
        }
        return extras
    }

    /// WordPress 三校：每個附件一個 <ul class="nojs_modal_list">（沒開 JavaScript 時顯示的清單，裡面就是下載連結）
    private nonisolated static func parseWordPress(_ html: String, base: URL) -> PageExtras {
        var extras = PageExtras()
        var rest = html[...]
        while let start = rest.range(of: "nojs_modal_list"),
              let end = rest.range(of: "</ul>", range: start.upperBound..<rest.endIndex) {
            extras.files += files(in: rest[start.upperBound..<end.lowerBound], base: base)
            rest = rest[end.upperBound...]
        }
        // 同一個檔案可能出現兩次，去掉重複的
        var seen = Set<URL>()
        extras.files = extras.files.filter { seen.insert($0.url).inserted }
        return extras
    }

    /// 一段 HTML 裡的每個 <a href>：連結 → 附件，連結文字（沒有就用網址最後一段）→ 檔名
    private nonisolated static func files(in block: Substring, base: URL) -> [Attachment] {
        block.matches(of: /<a\b([^>]*)>(.*?)<\/a>/.dotMatchesNewlines()).compactMap { match in
            guard let href = attribute("href", in: String(match.output.1)),
                  let url = URL(string: decode(href), relativeTo: base)?.absoluteURL else { return nil }
            let text = plainText(String(match.output.2))
            return Attachment(name: text.isEmpty ? url.lastPathComponent : text, url: url)
        }
    }

    /// 拿掉標籤（含 <svg> 圖示）、轉回特殊符號、去掉前後空白
    private nonisolated static func plainText(_ html: String) -> String {
        decode(html.replacing(/<svg.*?<\/svg>/.dotMatchesNewlines(), with: "").replacing(/<[^>]+>/, with: ""))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// 從 <div class="名稱"> 到它後面第一個 </ul>（兩塊裡面都只有一個清單）
    private nonisolated static func section(_ html: String, className: String) -> Substring? {
        guard let start = html.range(of: "<div class=\"\(className)\""),
              let end = html.range(of: "</ul>", range: start.upperBound..<html.endIndex) else { return nil }
        return html[start.lowerBound..<end.upperBound]
    }

    private nonisolated static func attribute(_ name: String, in tag: String) -> String? {
        guard let range = tag.range(of: " \(name)=\"") else { return nil }
        let rest = tag[range.upperBound...]
        guard let close = rest.firstIndex(of: "\"") else { return nil }
        let value = String(rest[..<close])
        return value.isEmpty ? nil : value
    }

    private nonisolated static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            // &#8211; 這種數字編號的符號
            .replacing(/&#(\d+);/) { match in
                Int(match.output.1).flatMap(UnicodeScalar.init).map { String(Character($0)) } ?? ""
            }
    }
}

/// 內頁下面的附件和參考網站
struct NoticeExtrasView: View {
    let pageURL: String
    @State private var extras: PageExtras?
    @State private var failed = false

    var body: some View {
        // 用 VStack 不用 Group：還沒載入時裡面是空的，Group 沒有東西可以掛 .task，就永遠不會去抓
        VStack(alignment: .leading, spacing: 0) {
            if let extras {
                VStack(alignment: .leading, spacing: 0) {
                    if !extras.files.isEmpty {
                        header(L("參考資料", "Attachments"))
                        ForEach(Array(extras.files.enumerated()), id: \.element) { index, file in
                            if index > 0 { Groove().padding(.vertical, 18) }
                            AttachmentView(file: file)
                        }
                    }
                    if !extras.links.isEmpty {
                        header(L("參考網站", "Links"))
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(extras.links, id: \.self) { link in
                                Button { SafariPage.open(link.url) } label: {
                                    Label(link.title, systemImage: "link")
                                        .multilineTextAlignment(.leading)
                                }
                                .font(.app(.body, .semibold))
                                .foregroundStyle(Color.brand)
                            }
                        }
                    }
                }
            } else if failed {
                Text(L("附件讀取失敗，請看原文。", "Couldn't load attachments. See the original."))
                    .font(.app(.footnote))
                    .foregroundStyle(Color.inkTertiary)
                    .padding(.top, 24)
            }
        }
        .task(id: pageURL) {
            // 已經有了就不重抓：打開連結（Safari）再回來時 task 會重跑，
            // 如果先清空，頁面會變短、捲動位置被往上推，閱讀進度就跑掉了
            guard extras == nil else { return }
            failed = false
            if let result = await ExtrasLoader.shared.extras(for: pageURL) {
                extras = result
            } else {
                failed = true
            }
        }
    }

    private func header(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Groove()
            Text(title)
                .font(.app(.title3, .bold))
                .foregroundStyle(Color.ink)
        }
        .padding(.top, 32)
        .padding(.bottom, 14)
    }
}

/// 一個附件：檔名（點了用 Safari 打開／下載），下面直接放 PDF 每一頁的圖，點了放大
private struct AttachmentView: View {
    let file: Attachment
    @State private var content: FileContent?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { SafariPage.open(file.url) } label: {
                Label(file.name, systemImage: file.isPDF ? "doc.richtext" : (file.isImage ? "photo" : "doc"))
                    .multilineTextAlignment(.leading)
            }
            .font(.app(.body, .semibold))
            .foregroundStyle(Color.brand)

            if file.isImage {
                NoticeImage(url: file.url)   // 圖片附件：跟內文的圖一樣，點了放大
            } else {
                switch content {
                case nil:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L("正在讀取附件…", "Reading attachment…"))
                    }
                    .font(.app(.footnote))
                    .foregroundStyle(Color.inkTertiary)
                case .pdf(let pages):
                    let count = pages.pageCount
                    ForEach(0..<min(count, PDFPages.maxShown), id: \.self) { index in
                        PDFPageImage(pages: pages, index: index)
                    }
                    if count > PDFPages.maxShown {
                        note(L("還有 \(count - PDFPages.maxShown) 頁，點上面的檔名看完整檔案。",
                               "\(count - PDFPages.maxShown) more pages. Tap the file name to see them all."))
                    }
                case .unsupported:
                    note(L("這種檔案沒辦法直接顯示，點檔名下載。", "This file type can't be shown here. Tap to download."))
                case .failed:
                    note(L("附件讀取失敗，點檔名用 Safari 打開。", "Couldn't read this file. Tap to open it in Safari."))
                }
            }
        }
        .task(id: file) {
            guard content == nil, !file.isImage else { return }
            content = await ExtrasLoader.shared.content(of: file)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.app(.footnote)).foregroundStyle(Color.inkTertiary)
    }
}

/// PDF 的一頁：白底紙張，點了放大（放大後再畫一張更清楚的）
private struct PDFPageImage: View {
    @Environment(Router.self) private var router
    let pages: PDFPages
    let index: Int

    @State private var image: UIImage?
    @State private var size = SizeBox()
    @State private var id = UUID()

    static let width: CGFloat = 1200        // 列表裡的畫質（像素），比 iPhone 內文寬度的 3 倍再多一點
    static let largeWidth: CGFloat = 2600   // 放大後

    var body: some View {
        Color.white
            .aspectRatio(pages.ratio(index), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipShape(.rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.edgeDark))
            .opacity(router.zoomed?.sourceID == id ? 0 : 1)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size.value = $0 }
            .contentShape(.rect)
            .highPriorityGesture(tap)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(L("附件第 \(index + 1) 頁", "Attachment page \(index + 1)"))
            .accessibilityAction { zoom(from: CGRect(origin: .zero, size: size.value)) }
            .task {
                guard image == nil else { return }
                if let cached = pages.cached(index, width: Self.width) { image = cached; return }
                let pages = pages, index = index
                image = await Task.detached(priority: .userInitiated) { pages.render(index, width: Self.width) }.value
            }
    }

    private var tap: some Gesture {
        SpatialTapGesture(coordinateSpace: .local)
            .simultaneously(with: SpatialTapGesture(coordinateSpace: .global))
            .onEnded { value in
                guard let local = value.first?.location, let global = value.second?.location else { return }
                zoom(from: CGRect(origin: CGPoint(x: global.x - local.x, y: global.y - local.y), size: size.value))
            }
    }

    private func zoom(from frame: CGRect) {
        guard let image else { return }
        let pages = pages, index = index
        // 同一個 PDF 的每一頁做成一本相簿：放大後左右滑換頁
        let gallery = (0..<min(pages.pageCount, PDFPages.maxShown)).map { i in
            GalleryPage(preview: pages.cached(i, width: Self.width), ratio: pages.ratio(i)) {
                await Task.detached(priority: .userInitiated) { pages.render(i, width: Self.largeWidth) }.value
            }
        }
        router.zoomed = ZoomedImage(sourceID: id, url: nil, preview: image, from: frame,
                                    loadLarge: gallery[index].load, gallery: gallery, startIndex: index)
    }
}
