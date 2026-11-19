// 設定裡的「外觀」：語言（中文／English）、字體、顏色。做法比照 JuanGo：
//   - 設定存在 UserDefaults，改了整個 App 馬上跟著變（@Observable）
//   - 字體同時換英文和中文：圓體配 SF Rounded、宋體配 New York。中文字型是 iOS 內建、用到才下載，
//     還沒下載好（或沒網路）時先用蘋方，不會壞掉
//   - 顏色：主色＋用主色的色相調出來的紙張底色。預設是「校板」：青綠色配米白紙

import SwiftUI
import UIKit
import CoreText

@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// "zh"（中文）或 "en"（English）
    var language: String { didSet { defaults.set(language, forKey: "language") } }
    /// AppFont.options 的第幾個
    var fontStyle: Int { didSet { defaults.set(fontStyle, forKey: "fontStyle"); AppFont.shared.styleChanged() } }
    /// AppTheme.all 裡的 id
    var themeID: String { didSet { defaults.set(themeID, forKey: "themeID") } }
    /// School.all 裡的 id：看哪一間學校的公告
    var schoolID: String { didSet { defaults.set(schoolID, forKey: "schoolID") } }

    var isEnglish: Bool { language == "en" }
    var theme: AppTheme { AppTheme.all.first { $0.id == themeID } ?? AppTheme.all[0] }
    var school: School { School.all.first { $0.id == schoolID } ?? School.all[0] }

    private init() {
        defaults.register(defaults: ["language": "zh", "fontStyle": 0, "themeID": "classic", "schoolID": "hsnu"])
        language = defaults.string(forKey: "language") ?? "zh"
        fontStyle = defaults.integer(forKey: "fontStyle")
        themeID = defaults.string(forKey: "themeID") ?? "classic"
        schoolID = defaults.string(forKey: "schoolID") ?? "hsnu"
    }
}

/// 支援的學校，跟爬蟲的 scraper/schools.py 一致（id、資料檔路徑要一樣）
nonisolated struct School: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let englishName: String
    /// 公告資料檔，相對於 GitHub 上的 scraper/data/
    let dataPath: String

    static let all = [
        School(id: "hsnu", name: "師大附中", englishName: "HSNU", dataPath: "notices.json"),
        School(id: "ck", name: "建國中學", englishName: "Chien Kuo", dataPath: "ck/notices.json"),
        School(id: "fg", name: "北一女中", englishName: "Taipei First Girls", dataPath: "fg/notices.json"),
        School(id: "cksh", name: "成功高中", englishName: "Cheng Kung", dataPath: "cksh/notices.json"),
        School(id: "csghs", name: "中山女高", englishName: "Zhongshan Girls", dataPath: "csghs/notices.json"),
    ]

    var dataURL: URL {
        URL(string: "https://raw.githubusercontent.com/HowWeiChi-app/BanGo/main/scraper/data/")!.appending(path: dataPath)
    }

    /// 手機上的備份：每校一份，換學校時才不會先閃一下別校的公告（附中沿用舊檔名）
    var cacheURL: URL {
        URL.cachesDirectory.appending(path: id == "hsnu" ? "notices.json" : "notices-\(id).json")
    }

    @MainActor var displayName: String { L(name, englishName) }
}

/// 依照語言設定選中文或英文的字
@MainActor func L(_ zh: String, _ en: String) -> String {
    AppSettings.shared.isEnglish ? en : zh
}

/// 校網上的類別、主題、來源名稱是中文資料；英文版顯示對應的英文（沒有對照的就照原樣）
@MainActor enum TagName {
    private static let english: [String: String] = [
        "教務": "Academic", "學務": "Student Affairs", "輔導": "Counseling", "獎學金": "Scholarships",
        "比賽": "Competitions", "考試": "Exams", "停課": "Class Cancellations", "總務": "General Affairs",
        "圖書館": "Library", "人事": "Personnel", "會計": "Accounting", "國中部": "Junior High",
        "重要公告": "Important", "學生": "Students", "來文公告": "Official Letters", "行事曆": "Calendar",
        "校網": "School Site",
        // 其他學校的分類
        "最新消息": "Latest News", "學生園地": "Student Corner", "來文宣導": "Announcements",
        "行政公告": "Administration", "活動競賽": "Events & Contests", "升學訊息": "Admissions",
        "獎助學金": "Financial Aid", "學生專區": "Students",
    ]

    static func display(_ name: String) -> String {
        AppSettings.shared.isEnglish ? english[name] ?? name : name
    }

    /// 公告上的標籤，主題前面有 #
    static func displayTag(_ tag: String) -> String {
        tag.hasPrefix("#") ? "#" + display(String(tag.dropFirst())) : display(tag)
    }
}

// MARK: - 顏色

struct AppTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let englishName: String
    let accentHex: UInt32

    @MainActor var displayName: String { L(name, englishName) }

    /// 主色。深色模式往白色調亮一點，在深色紙上才看得清楚（跟 JuanGo 一樣）
    var accent: Color {
        let base = RGB(hex: accentHex)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? base.mix(.white, 0.38).ui : base.ui })
    }

    /// 選顏色時色票上的紙張顏色：跟 App 實際的紙張一樣，深色模式是深色的
    var swatch: Color {
        let light = paperRGB(dark: false).ui, dark = paperRGB(dark: true).ui
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// 紙張底色。預設的「校板」是偏暖的米白、深色是帶一點冷的深灰；其他用主色的色相，淺色幾乎白、深色很深
    func paperRGB(dark: Bool) -> RGB {
        if id == "classic" {
            return dark ? RGB(hex: 0x1A1C1D) : RGB(hex: 0xFAF8F3)
        }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        RGB(hex: accentHex).ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let k = min(1, s / 0.6)  // 灰色系（石墨）就是中性灰
        let c = dark ? UIColor(hue: h, saturation: 0.25 * k, brightness: 0.125, alpha: 1)
                     : UIColor(hue: h, saturation: 0.05 * k, brightness: 0.99, alpha: 1)
        return RGB(c)
    }

    static let all: [AppTheme] = [
        .init(id: "classic", name: "校板", englishName: "BanGo", accentHex: 0x128A8F),  // id 沿用舊的，選過的人不用重選
        .init(id: "amber", name: "琥珀", englishName: "Amber", accentHex: 0xB0661A),
        .init(id: "pine", name: "松針", englishName: "Pine", accentHex: 0x2F6B4F),
        .init(id: "ink", name: "墨藍", englishName: "Ink", accentHex: 0x24407A),
        .init(id: "plum", name: "梅子", englishName: "Plum", accentHex: 0x7A2C5C),
        .init(id: "graphite", name: "石墨", englishName: "Graphite", accentHex: 0x3B3A38),
        .init(id: "sky", name: "天空藍", englishName: "Sky", accentHex: 0x0066CC),
    ]
}

/// 0–255 的 RGB，算顏色用
struct RGB: Hashable {
    var r, g, b: CGFloat

    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) { self.r = r; self.g = g; self.b = b }
    init(hex: UInt32) { self.init(CGFloat((hex >> 16) & 0xFF), CGFloat((hex >> 8) & 0xFF), CGFloat(hex & 0xFF)) }
    init(_ c: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r * 255, g * 255, b * 255)
    }

    static let white = RGB(255, 255, 255)
    static let black = RGB(0, 0, 0)

    /// 往 other 混 t（0–1）
    func mix(_ other: RGB, _ t: CGFloat) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    var ui: UIColor { UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1) }
}

/// 一組顏色的所有深淺。每種顏色只建一次：每次都新建動態顏色的話，SwiftUI 會以為顏色變了，整頁重畫
@MainActor struct Palette {
    let paper, paperChip, cardFill, edgeDark, grooveLight, cardHighlight, edgeShadow, pageRim, brand: Color
    /// 來源頭像的顏色：每個來源固定一個色相，飽和度、亮度跟著主題（SourceStyle.color 用）
    let sources: [Color]

    private static var cache: [String: Palette] = [:]

    static var current: Palette {
        let theme = AppSettings.shared.theme  // 在畫面裡讀到這裡，換顏色時畫面就會重畫
        if let p = cache[theme.id] { return p }
        let p = Palette(theme)
        cache[theme.id] = p
        return p
    }

    private init(_ theme: AppTheme) {
        func dynamic(light: UIColor, dark: UIColor) -> Color {
            Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
        }
        let darkPaper = theme.paperRGB(dark: true), lightPaper = theme.paperRGB(dark: false)
        // 深色模式的各種深淺都從紙張顏色算，每個主題用同一套比例
        paper = dynamic(light: lightPaper.ui, dark: darkPaper.ui)
        paperChip = dynamic(light: lightPaper.mix(.black, 0.11).ui, dark: darkPaper.mix(.white, 0.09).ui)
        cardFill = dynamic(light: lightPaper.mix(.black, 0.07).ui, dark: darkPaper.mix(.white, 0.058).ui)
        edgeDark = dynamic(light: UIColor(white: 0, alpha: 0.09), dark: darkPaper.mix(.black, 0.35).ui)
        grooveLight = dynamic(light: UIColor(white: 1, alpha: 0.75), dark: darkPaper.mix(.white, 0.072).ui)
        let highlight = darkPaper.mix(.white, 0.152).ui
        cardHighlight = dynamic(light: UIColor(white: 1, alpha: 0.9), dark: highlight)
        edgeShadow = dynamic(light: UIColor(white: 0, alpha: 0.15), dark: darkPaper.mix(.black, 0.77).ui)
        // 換頁時移動中那頁外圈的邊：深色是亮邊；淺色是暗色的邊
        pageRim = dynamic(light: UIColor(white: 0, alpha: 0.12), dark: highlight)
        brand = theme.accent

        // 來源的顏色：每個來源的色相固定（不管哪個主題，重要公告都是橘紅、學生都是藍…），容易分辨；
        // 主題只決定「風格」：飽和度、亮度跟著主色走（墨藍、松針深而沉，天空藍鮮豔，石墨低彩度）
        var h: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        RGB(hex: theme.accentHex).ui
            .getHue(&h, saturation: &sat, brightness: &bri, alpha: &alpha)
        let gray = sat < 0.15  // 石墨：主色幾乎是灰的
        let lightS = gray ? 0.24 : min(0.8, max(0.4, sat))
        let lightB = gray ? 0.5 : min(0.82, max(0.5, bri))
        // 深色模式：亮一點、彩度降一點，在深色紙上才看得清楚又不刺眼
        let darkS = lightS * 0.8, darkB = max(lightB, gray ? 0.72 : 0.85)
        // 橘紅、藍、綠、紫、金：色相彼此至少差 36°
        sources = [0.025, 0.6, 0.4, 0.78, 0.12].map { hue in
            dynamic(light: UIColor(hue: hue, saturation: lightS, brightness: lightB, alpha: 1),
                    dark: UIColor(hue: hue, saturation: darkS, brightness: darkB, alpha: 1))
        }
    }
}

// MARK: - 字體（照 JuanGo 的 Fonts.swift）

@MainActor @Observable
final class AppFont {
    static let shared = AppFont()

    struct Option {
        let name: String
        let englishName: String
        let design: UIFontDescriptor.SystemDesign
        let swiftDesign: Font.Design
        /// 中文字型 細／一般／粗 的 PostScript 名稱；nil = 蘋方（系統預設）
        let cjk: [String]?
        let cjkName: String
    }

    static let options: [Option] = [
        .init(name: "系統", englishName: "System", design: .default, swiftDesign: .default, cjk: nil, cjkName: "蘋方"),
        .init(name: "圓體", englishName: "Rounded", design: .rounded, swiftDesign: .rounded,
              cjk: ["STYuanti-TC-Light", "STYuanti-TC-Regular", "STYuanti-TC-Bold"], cjkName: "圓體"),
        .init(name: "襯線", englishName: "Serif", design: .serif, swiftDesign: .serif,
              cjk: ["STSongti-TC-Light", "STSongti-TC-Regular", "STSongti-TC-Bold"], cjkName: "宋體"),
        // 中文沒有等寬字型；中文字本來就一樣寬，所以還是蘋方
        .init(name: "等寬", englishName: "Monospaced", design: .monospaced, swiftDesign: .monospaced, cjk: nil, cjkName: "蘋方"),
    ]

    /// 中文字型下載好、或設定改了，就加一：所有 Font.app 重新建
    private(set) var version = 0
    private(set) var downloading: String?
    /// 打開 App 時，之前下載過的中文字型要重新接上（iOS 每次開 App 都要再要一次，很快）。
    /// 接上之前先不顯示畫面，不然會先閃一下系統字體
    private(set) var warming = false
    private(set) var failed: String?
    @ObservationIgnored private var cache: [String: Font] = [:]
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private var readyCache: [Int: Bool] = [:]

    var option: Option { Self.options[min(Self.options.count - 1, max(0, AppSettings.shared.fontStyle))] }

    private var cjkReady: Bool {
        let i = AppSettings.shared.fontStyle
        if let r = readyCache[i] { return r }
        let r = option.cjk.map { $0.allSatisfy(Self.installed) } ?? false
        readyCache[i] = r
        return r
    }

    static func installed(_ name: String) -> Bool { UIFont(name: name, size: 12) != nil }

    /// 第 i 種字體的樣本（選字體時用），中文字型在手機上的話用它
    static func preview(_ i: Int, size: CGFloat) -> Font {
        let o = options[i]
        if let names = o.cjk, installed(names[1]) { return .custom(names[1], fixedSize: size) }
        return .system(size: size, design: o.swiftDesign)
    }

    /// 目前選的中文字型還沒在手機上的話，請 iOS 下載
    func prepare() {
        guard let names = option.cjk, !names.allSatisfy(Self.installed) else { return }
        let key = names.joined()
        guard !requested.contains(key) else { return }
        requested.insert(key)
        let downloadedBefore = UserDefaults.standard.bool(forKey: "cjkReady." + key)
        if downloadedBefore {
            // 已經在手機上，只是這次開 App 還沒接上：等一下下就好，最多 0.5 秒
            warming = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                AppFont.shared.warming = false
            }
        } else {
            downloading = option.cjkName
        }
        failed = nil
        let label = option.cjkName
        let descriptors = names.map { CTFontDescriptorCreateWithNameAndSize($0 as CFString, 0) } as CFArray
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descriptors, nil) { state, _ in
            switch state {
            case .didFinish:
                Task { @MainActor in
                    let s = AppFont.shared
                    s.downloading = nil
                    s.warming = false
                    if names.allSatisfy(Self.installed) {
                        UserDefaults.standard.set(true, forKey: "cjkReady." + key)
                    } else {
                        s.failed = label; s.requested.remove(key)
                    }
                    s.cache = [:]; s.readyCache = [:]; s.version += 1
                    s.applyAppearance()
                }
            case .didFailWithError:
                Task { @MainActor in
                    let s = AppFont.shared
                    s.downloading = nil; s.warming = false; s.failed = label; s.requested.remove(key)
                }
            default: break
            }
            return true
        }
    }

    func styleChanged() {
        cache = [:]
        readyCache = [:]
        version += 1
        prepare()
        applyAppearance()
    }

    /// UIKit 畫的導覽列標題也換成同一種字體
    func applyAppearance() {
        let large = uiFont(style: .largeTitle, size: nil, weight: .bold)
        let inline = uiFont(style: .headline, size: nil, weight: .semibold)
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: large]
        nav.titleTextAttributes = [.font: inline]
        // appearance 只管之後建立的導覽列；已經在畫面上的也換掉
        func visit(_ v: UIView) {
            if let n = v as? UINavigationBar {
                n.largeTitleTextAttributes = [.font: large]
                n.titleTextAttributes = [.font: inline]
            }
            v.subviews.forEach(visit)
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes { scene.windows.forEach(visit) }
    }

    func font(_ style: Font.TextStyle?, size: CGFloat?, weight: Font.Weight?) -> Font {
        _ = version
        let opt = option
        let w = weight ?? (style == .headline ? .semibold : .regular)
        // 系統／等寬，或中文字型還沒下載好：用一般的系統字體（保留動態字體大小）
        guard opt.cjk != nil, cjkReady else {
            if let style { return .system(style, design: opt.swiftDesign, weight: w) }
            return .system(size: size ?? 17, weight: w, design: opt.swiftDesign)
        }
        let key = "\(AppSettings.shared.fontStyle)|\(style.map { "\($0)" } ?? "-")|\(size ?? 0)|\(w)"
        if let f = cache[key] { return f }
        let f = Font(uiFont(style: style.map(Self.uiStyle), size: size, weight: Self.uiWeight(w)) as CTFont)
        cache[key] = f
        return f
    }

    func uiFont(style: UIFont.TextStyle?, size: CGFloat?, weight: UIFont.Weight) -> UIFont {
        let opt = option
        let pointSize = size ?? UIFont.preferredFont(forTextStyle: style ?? .body).pointSize
        var base = UIFont.systemFont(ofSize: pointSize, weight: weight)
        if let d = base.fontDescriptor.withDesign(opt.design) { base = UIFont(descriptor: d, size: pointSize) }
        guard let names = opt.cjk, cjkReady else { return base }
        let face = weight >= .semibold ? names[2] : weight <= .light ? names[0] : names[1]
        let desc = base.fontDescriptor.addingAttributes([.cascadeList: [UIFontDescriptor(name: face, size: pointSize)]])
        return UIFont(descriptor: desc, size: pointSize)
    }

    private static func uiStyle(_ s: Font.TextStyle) -> UIFont.TextStyle {
        switch s {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }

    private static func uiWeight(_ w: Font.Weight) -> UIFont.Weight {
        switch w {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

extension Font {
    /// App 的字體：設定裡選的英文字體設計，加上搭配的中文字型
    @MainActor static func app(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        AppFont.shared.font(style, size: nil, weight: weight)
    }
    @MainActor static func app(size: CGFloat, _ weight: Font.Weight? = nil) -> Font {
        AppFont.shared.font(nil, size: size, weight: weight ?? .regular)
    }
}
