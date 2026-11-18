// 官網截圖用的展示模式，由 tools/capture_screens.sh 用 --dart-define-from-file 編譯。
// 一般編譯時 demoOn 是 false，下面的內容不會進到 App。展示版另用 .demo 套件 ID，碰不到平常使用的校板。

import 'dart:convert';

const demoOn = bool.fromEnvironment('DEMO');

/// 一開始就打開標題以這段文字開頭的公告
const demoOpen = String.fromEnvironment('DEMO_OPEN');

const _notices = String.fromEnvironment('DEMO_NOTICES');

/// 編進展示版的 notices.json
String? get demoNotices => demoOn && _notices.isNotEmpty ? utf8.decode(base64.decode(_notices)) : null;
