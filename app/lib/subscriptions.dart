// 使用者訂閱了哪些類別和主題，存在手機上。
//
// 用 ChangeNotifier：設定頁一改，「我的公告」頁面就會自動重畫。

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Subscriptions extends ChangeNotifier {
  static const _key = 'subscribed';

  /// 第一次打開 App 時預設訂閱的項目。
  /// 企劃的原則是「預設只開最重要的類別」，避免一開始就太吵，其他讓使用者自己打開。
  static const defaults = {'教務', '學務', '考試'};

  Set<String> _items = {...defaults};
  Set<String> get items => _items;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_key);
    if (saved != null) {
      _items = saved.toSet();
      notifyListeners();
    }
  }

  Future<void> set(String name, bool subscribed) async {
    _items = {..._items};
    if (subscribed) {
      _items.add(name);
    } else {
      _items.remove(name);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _items.toList());
  }
}
