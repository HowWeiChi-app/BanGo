// 讓每個畫面都拿得到公告資料（NoticeStore）、換頁狀態（AppRouter）和設定（AppSettings）。
// 用 InheritedNotifier：三個裡面任何一個有變動，用到的畫面就會重畫。

import 'package:material_ui/material_ui.dart';

import 'router.dart';
import 'settings.dart';
import 'store.dart';

class AppScope extends InheritedNotifier<Listenable> {
  AppScope({super.key, required this.store, required this.router, required super.child})
      : super(notifier: Listenable.merge([store, router, AppSettings.shared]));

  final NoticeStore store;
  final AppRouter router;
  AppSettings get settings => AppSettings.shared;

  /// listen: false 用在 initState、按鈕的動作裡（只是要拿來用，不用跟著重畫）
  static AppScope of(BuildContext context, {bool listen = true}) => listen
      ? context.dependOnInheritedWidgetOfExactType<AppScope>()!
      : context.getInheritedWidgetOfExactType<AppScope>()!;
}
