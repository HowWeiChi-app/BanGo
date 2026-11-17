// App 的進入點：建立資料來源和訂閱設定，然後顯示主畫面。

import 'package:material_ui/material_ui.dart';

import 'home_page.dart';
import 'repository.dart';
import 'subscriptions.dart';

void main() {
  runApp(NoticeApp(repository: NoticeRepository(), subscriptions: Subscriptions()));
}

class NoticeApp extends StatelessWidget {
  const NoticeApp({super.key, required this.repository, required this.subscriptions});

  final NoticeRepository repository;
  final Subscriptions subscriptions;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '附中公告',
      debugShowCheckedModeBanner: false,
      // 跟著手機設定切換淺色/深色
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1B5E9E), useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1B5E9E),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomePage(repository: repository, subscriptions: subscriptions),
    );
  }
}
