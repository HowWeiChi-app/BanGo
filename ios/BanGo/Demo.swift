// 官網截圖用的展示模式，由 tools/capture_screens.sh 啟動。
// 只有 Debug 版、套件 ID 以 .demo 結尾，而且帶了 BANGO_DEMO 時才生效：
// 展示版是另一個 App，有自己的資料夾，碰不到平常使用的校板。

import Foundation

enum Demo {
    static let isOn: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["BANGO_DEMO"] != nil
            && Bundle.main.bundleIdentifier?.hasSuffix(".demo") == true
        #else
        false
        #endif
    }()

    static var isDark: Bool { isOn && ProcessInfo.processInfo.environment["BANGO_DARK"] != nil }

    /// 一開始就打開標題以這段文字開頭的公告
    static var openTitle: String? {
        isOn ? ProcessInfo.processInfo.environment["BANGO_OPEN"] : nil
    }
}
