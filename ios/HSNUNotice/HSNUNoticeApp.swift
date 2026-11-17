// App 的進入點。

import SwiftUI

@main
struct HSNUNoticeApp: App {
    init() {
        // 越早越好：選了圓體、宋體的話，在第一個畫面出來前就開始接上中文字型
        AppFont.shared.prepare()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                // 中文字型接上之前，用紙張底色蓋住（通常不到 0.1 秒），不會先閃一下系統字體；接上後慢慢淡出
                if AppFont.shared.warming {
                    Color.paper.ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.3), value: AppFont.shared.warming)
        }
    }
}
