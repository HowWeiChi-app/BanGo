// 顏色和小圖示。排版參考 RSS 閱讀器：米白色紙張底色、圓形來源頭像。

import SwiftUI

extension Color {
    // 跟著設定裡的「顏色」變的那些（AppSettings.swift 的 Palette）。括號裡是預設「校板」深色模式的值：
    /// 紙張底色（淺色 FAF8F3 米白、深色 1A1C1D）
    @MainActor static var paper: Color { Palette.current.paper }
    /// 數字小膠囊、選取狀態的底色
    @MainActor static var paperChip: Color { Palette.current.paperChip }
    /// 選中卡片的底色（紙張往白混 5.8%）
    @MainActor static var cardFill: Color { Palette.current.cardFill }
    /// 暗線：分隔線的上面那條、卡片的外圈（紙張往黑混 35%）
    @MainActor static var edgeDark: Color { Palette.current.edgeDark }
    /// 分隔線下面那條亮線（紙張往白混 7.2%）
    @MainActor static var grooveLight: Color { Palette.current.grooveLight }
    /// 卡片內圈的亮邊（紙張往白混 15.2%）
    @MainActor static var cardHighlight: Color { Palette.current.cardHighlight }
    /// 工具列硬邊下面那條很暗的線（紙張往黑混 77%）
    @MainActor static var edgeShadow: Color { Palette.current.edgeShadow }
    /// 換頁時移動中那頁外圈 1pt 的邊：深色是亮邊，淺色是暗邊
    @MainActor static var pageRim: Color { Palette.current.pageRim }
    /// App 的主色（校板：淺色 128A8F 青綠，深色往白調亮）
    @MainActor static var brand: Color { Palette.current.brand }

    // 文字的三種深淺：
    /// 標題、內文：淺色黑 75%、深色白 90%（量到 232）
    static let ink = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.9) : UIColor(white: 0, alpha: 0.75) })

    /// 摘要：淺色黑 50%、深色白 60%（量到 165）
    static let inkSecondary = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.6) : UIColor(white: 0, alpha: 0.5) })

    /// 時間、來源下面那行小字：淺色黑 33%、深色白 40%（量到 121）
    static let inkTertiary = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.4) : UIColor(white: 0, alpha: 0.33) })

    /// 捲動後工具列後面的模糊底再壓暗一點：系統的硬邊底太亮
    static let barShade = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0, alpha: 0.25)
        : UIColor(white: 0, alpha: 0) })

    /// 換頁時移動中那頁的陰影（深色黑 40%、淺色黑 15%，半徑 5）
    static let pageShadow = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0, alpha: 0.4)
        : UIColor(white: 0, alpha: 0.15) })

}

/// 公告來源的資訊：名稱、圖示、顏色
enum SourceStyle {
    static func symbol(_ source: String) -> String {
        switch source {
        case "重要公告": "megaphone.fill"
        case "學生": "person.2.fill"
        case "來文公告": "envelope.fill"
        case "行事曆": "calendar"
        // 其他學校的分類
        case "最新消息": "newspaper.fill"
        case "學生園地", "學生專區": "person.2.fill"
        case "來文宣導": "envelope.fill"
        case "行政公告": "building.columns.fill"
        case "活動競賽": "trophy.fill"
        case "升學訊息": "graduationcap.fill"
        case "獎助學金": "dollarsign.circle.fill"
        default: "doc.text.fill"
        }
    }

    /// 每個來源固定一個顏色（橘紅、藍、綠、紫、金），深淺鮮豔程度跟著設定裡的顏色主題（Palette.sources）
    @MainActor static func color(_ source: String) -> Color {
        let index: Int? = switch source {
        case "重要公告", "最新消息", "行政公告": 0
        case "學生", "學生園地", "學生專區": 1
        case "來文公告", "來文宣導": 2
        case "行事曆", "升學訊息": 3
        case "活動競賽", "獎助學金": 4
        default: nil
        }
        guard let index else { return .inkTertiary }
        return Palette.current.sources[index]
    }

    static func name(_ source: String) -> String { source.isEmpty ? "校網" : source }
}

/// 圓形的來源頭像，像 RSS 閱讀器裡每個網站的小 icon
struct SourceAvatar: View {
    let source: String
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: SourceStyle.symbol(source))
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(SourceStyle.color(source))
            .frame(width: size, height: size)
            .background(Color(UIColor.secondarySystemGroupedBackground), in: .circle)
            .overlay(Circle().strokeBorder(.primary.opacity(0.08)))
            // 底下墊一個往下偏 1pt 的淡色圓，看起來像陰影。
            // 不用 .shadow：模糊陰影每個頭像都要另外算一次，列表捲很快時會卡
            .background(Circle().fill(.black.opacity(0.07)).offset(y: 1))
            .accessibilityHidden(true)
    }
}

/// 類別、主題的圖示（側邊欄用）
enum TagStyle {
    static func symbol(_ name: String) -> String {
        switch name {
        case "教務": "book"
        case "學務": "figure.walk"
        case "輔導": "heart.text.square"
        case "獎學金": "dollarsign.circle"
        case "比賽": "trophy"
        case "考試": "pencil.and.list.clipboard"
        case "停課": "exclamationmark.triangle"
        default: "number"
        }
    }
}

/// 分隔線：1pt 暗線 + 1pt 亮線，看起來像在紙上刻了一道溝
struct Groove: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.edgeDark.frame(height: 1)
            Color.grooveLight.frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

/// 選中的卡片：比底色亮一點，外圈 1pt 暗線、內圈 1pt 亮線，
/// 亮線像被右上方的光照到，到左下角就淡掉；外面一圈很淡、上下一樣寬的陰影
struct GlassCard: View {
    var cornerRadius: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(Color.cardFill)
            .overlay {
                // 只有左下角那一塊變暗（像光從右上照過來）。
                // 不用「右上到左下」的直線漸層：卡片很寬，直線漸層會連左上角也變暗
                shape.inset(by: 1).strokeBorder(
                    RadialGradient(colors: [.cardFill, .cardHighlight], center: .bottomLeading,
                                   startRadius: 10, endRadius: 90),
                    lineWidth: 1)
            }
            .overlay { shape.strokeBorder(Color.edgeDark, lineWidth: 1) }
            .shadow(color: .black.opacity(0.08), radius: 4)
    }
}

/// 工具列硬邊的光影（深色模式 3x 像素）：
/// 模糊底壓暗；下緣 1pt 亮線（47）＋ 1pt 暗線（7），再往下約 11pt 的陰影從 24 慢慢亮回紙張 31。
/// 亮線、暗線、陰影到螢幕左右兩邊約 65pt 內會淡掉，像光從上面打下來。
/// 放在列表最上面（安全區的下緣）：亮線剛好蓋住系統那條比較亮的細線。
struct BarEdgeShade: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.grooveLight.frame(height: 1)
            Color.edgeShadow.frame(height: 1)
            LinearGradient(colors: [.black.opacity(0.23), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 11)
        }
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16),
                                   .init(color: .black, location: 0.84), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        // 兩邊亮線淡掉的地方，系統那條比較亮的細線會透出來：先墊一條紙張顏色整排蓋掉
        .background(alignment: .top) { Color.paper.frame(height: 1) }
        // 往上一大片壓暗模糊底（蓋到狀態列那邊，工具列的玻璃按鈕在更上面一層，不會被壓到）
        .background(alignment: .bottom) {
            Color.barShade.frame(height: 300).offset(y: -13)
        }
        .offset(y: -1)  // 亮線在安全區邊線的上面 1pt，暗線在下面 1pt
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// 米白紙張底色，連上下的安全區域（瀏海、底部橫條那邊）一起蓋滿。
    /// containerBackground(for: .navigation) 是系統導覽容器自己的底色，
    /// 沒設的話換頁、往右滑返回時，邊緣會露出系統預設的白色。
    func paperBackground() -> some View {
        self
            .background { Color.paper.ignoresSafeArea() }
            .containerBackground(Color.paper, for: .navigation)
    }
}
