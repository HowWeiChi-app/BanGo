// 顏色和小圖示。排版參考 RSS 閱讀器 Reeder：米白色紙張底色、圓形來源頭像。

import SwiftUI

extension Color {
    /// 紙張底色：淺色模式是米白，深色模式是深灰
    static let paper = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.11, green: 0.11, blue: 0.10, alpha: 1)
        : UIColor(red: 0.95, green: 0.94, blue: 0.92, alpha: 1) })

    /// 數字小膠囊、選取狀態的底色
    static let paperChip = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.20, green: 0.19, blue: 0.18, alpha: 1)
        : UIColor(red: 0.89, green: 0.88, blue: 0.85, alpha: 1) })

    /// 文字顏色：不是純黑，是偏暖的深灰，看起來比較像紙上的字
    static let ink = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.92, green: 0.91, blue: 0.89, alpha: 1)
        : UIColor(red: 0.23, green: 0.22, blue: 0.21, alpha: 1) })

    /// App 的主色（橘紅）
    static let brand = Color(red: 0.85, green: 0.36, blue: 0.24)
}

/// 公告來源的資訊：名稱、圖示、顏色
enum SourceStyle {
    static func symbol(_ source: String) -> String {
        switch source {
        case "重要公告": "megaphone.fill"
        case "學生": "person.2.fill"
        case "來文公告": "envelope.fill"
        case "行事曆": "calendar"
        default: "doc.text.fill"
        }
    }

    static func color(_ source: String) -> Color {
        switch source {
        case "重要公告": .orange
        case "學生": .blue
        case "來文公告": .teal
        case "行事曆": .purple
        default: .gray
        }
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
