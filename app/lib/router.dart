// 記住目前在第幾層、每一層放什麼；任何畫面都可以叫它換頁。跟 iPhone 版 ContentView.swift 的 Router 一樣：
//   側邊欄（0）｜ 時間軸（1）｜ 內頁（2）三層左右並排，沒有下方分頁列。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'store.dart';

/// 長按時間軸跳出選單的那一則，和它在螢幕上的位置
class RowMenuRequest {
  const RowMenuRequest(this.notice, this.rect);
  final Notice notice;
  final Rect rect;
}

/// 要放大的圖片：好幾張可以左右滑（PDF 的每一頁），從畫面上哪個位置放大
class ZoomRequest {
  const ZoomRequest({required this.pages, required this.start, required this.from, this.sourceId});
  final List<ZoomPage> pages;
  final int start;
  final Rect from;
  final Object? sourceId; // 被點的那個圖片元件：放大時把它藏起來，看起來像圖片被拿起來
}

/// 相簿裡的一張：先顯示的小圖、寬高比、怎麼拿到清楚的大圖
class ZoomPage {
  const ZoomPage({required this.ratio, required this.large, this.preview});
  final double ratio; // 寬 ÷ 高
  final ZoomImage? preview; // 頁面上已經有的圖，放大的動畫先用它
  final Future<ZoomImage?> Function() large;
}

/// 放大用的圖：網路圖片給 provider，PDF 頁面給畫好的 rawImage
class ZoomImage {
  const ZoomImage({this.provider, this.raw});
  final Object? provider; // ImageProvider
  final Object? raw; // ui.Image
}

/// 每一頁在第幾層
abstract final class Depth {
  static const sidebar = 0, timeline = 1, article = 2;
}

class AppRouter extends ChangeNotifier {

  int depth = Depth.timeline; // 打開 App 時直接停在時間軸
  NoticeFilter filter = NoticeFilter.mine; // 回到側邊欄後還記得，往左拉就回到這個分類
  Notice? article; // 內頁顯示哪一則

  String? lastOpened; // 最後看的那則公告：時間軸上用灰色卡片標出來
  RowMenuRequest? rowMenu;
  ZoomRequest? zoomed;
  bool searching = false;
  String searchQuery = '';
  String? toast;
  List<Notice> readingList = []; // 點進內頁時那個時間軸上的公告（由新到舊），內頁往左滑換到上面那則用

  /// 時間軸要不要把 lastOpened 捲到中間（打開公告、內頁換則時）
  int scrollRequest = 0;

  void _changed() => notifyListeners();

  /// 從側邊欄打開一種公告的時間軸
  void openFilter(NoticeFilter f) {
    if (depth != Depth.sidebar) return; // 連點兩下不會出事
    filter = f;
    searching = false;
    searchQuery = '';
    depth = Depth.timeline;
    _changed();
  }

  /// 從時間軸打開一則公告
  void openNotice(Notice notice, List<Notice> list) {
    if (depth != Depth.timeline) return;
    readingList = list;
    lastOpened = notice.id;
    article = notice;
    depth = Depth.article;
    scrollRequest++;
    _changed();
  }

  /// 回到上一層
  void back() {
    if (depth <= Depth.sidebar) return;
    if (depth == Depth.timeline) {
      searching = false;
      searchQuery = '';
    }
    depth--;
    _changed();
  }

  /// 換頁動畫跑完：內頁已經滑走了，不用留著
  void pageSettled() {
    if (depth < Depth.article && article != null) {
      article = null;
      _changed();
    }
  }

  /// 拖曳放手後，直接設定停在哪一層（動畫由拖曳那邊負責）
  void settle(int newDepth) {
    depth = newDepth;
    if (depth < Depth.timeline) {
      searching = false;
      searchQuery = '';
    }
    if (depth < Depth.article) article = null;
    _changed();
  }

  /// 時間軸上在目前這則上面的那則（比較新）；已經是最上面一則、或不在內頁時是 null
  Notice? get newer {
    final a = article;
    if (a == null) return null;
    final i = readingList.indexWhere((n) => n.id == a.id);
    return i > 0 ? readingList[i - 1] : null;
  }

  /// 這一層往左拉，有沒有下一頁：側邊欄拉回時間軸；內頁拉進上面那則（比較新的）公告
  bool get hasForward => depth == Depth.sidebar || (depth == Depth.article && newer != null);

  /// 往左拉到下一頁放手後，直接換過去
  void settleForward() {
    final next = newer;
    if (depth == Depth.article && next != null) {
      article = next; // 還是在內頁這一層，只是換成上面那則
      lastOpened = next.id; // 時間軸的灰色卡片跟著換到這則
      scrollRequest++;
      _changed();
    } else {
      settle(depth + 1);
    }
  }

  /// 從內頁點分類／主題：直接回到那一類的時間軸
  void jump(NoticeFilter f) {
    if (depth != Depth.article) return;
    filter = f;
    searching = false;
    searchQuery = '';
    depth = Depth.timeline;
    _changed();
  }

  /// 設定裡換了學校：舊學校的分類、內頁都不適用了，回到「我的公告」
  void schoolChanged() {
    filter = NoticeFilter.mine;
    article = null;
    readingList = [];
    lastOpened = null;
    searching = false;
    searchQuery = '';
    _changed();
  }

  void setSearching(bool on) {
    searching = on;
    if (!on) searchQuery = '';
    _changed();
  }

  void setQuery(String q) {
    searchQuery = q;
    _changed();
  }

  void showRowMenu(RowMenuRequest? request) {
    rowMenu = request;
    _changed();
  }

  void zoom(ZoomRequest? request) {
    zoomed = request;
    _changed();
  }

  Timer? _toastTimer;

  /// 顯示一下提示，1.5 秒後自己消失
  void showToast(String text) {
    toast = text;
    HapticFeedback.mediumImpact();
    _changed();
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 1500), () {
      toast = null;
      _changed();
    });
  }
}
