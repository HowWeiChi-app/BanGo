// App 的進入點：先讀設定和上次的公告，再顯示畫面（第一個畫面就是對的語言、顏色、資料）。
// 畫面的排法照 iPhone 版：側邊欄 ｜ 時間軸 ｜ 內頁三層左右並排（PageStack），
// 上面再蓋放大圖片、長按選單、提示三層。

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app_scope.dart';
import 'images.dart';
import 'overlays.dart';
import 'page_stack.dart';
import 'router.dart';
import 'settings.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  await AppSettings.shared.load();
  final store = NoticeStore();
  await store.load();
  runApp(NoticeApp(store: store, router: AppRouter()));
}

class NoticeApp extends StatefulWidget {
  const NoticeApp({super.key, required this.store, required this.router});
  final NoticeStore store;
  final AppRouter router;

  @override
  State<NoticeApp> createState() => _NoticeAppState();
}

class _NoticeAppState extends State<NoticeApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.refreshIfStale();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 從背景回到 App：超過 10 分鐘沒更新就重新下載
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.store.refreshIfStale();
  }

  ThemeData _theme(Brightness brightness) {
    final settings = AppSettings.shared;
    final dark = brightness == Brightness.dark;
    final palette = Palette(settings.theme, dark);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: settings.font.family,
      scaffoldBackgroundColor: palette.paper,
      colorScheme: ColorScheme.fromSeed(seedColor: palette.brand, brightness: brightness, surface: palette.paper),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.brand,
        selectionColor: palette.brand.withValues(alpha: 0.3),
        selectionHandleColor: palette.brand,
      ),
      splashFactory: NoSplash.splashFactory,
      extensions: [palette],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: widget.store,
      router: widget.router,
      child: ListenableBuilder(
        listenable: AppSettings.shared,
        builder: (context, _) => MaterialApp(
          title: '校板',
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          home: const _Home(),
        ),
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final router = AppScope.of(context).router;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      // 系統的返回（手勢或按鍵）：先關掉放大的圖、選單、搜尋，再一層一層回去；在側邊欄才離開 App
      child: PopScope(
        canPop: router.depth == 0 && router.zoomed == null && router.rowMenu == null,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (router.zoomed != null) {
            router.zoom(null);
          } else if (router.rowMenu != null) {
            router.showRowMenu(null);
          } else if (router.searching && router.depth == 1) {
            router.setSearching(false);
          } else {
            router.back();
          }
        },
        child: const Scaffold(
          body: Stack(children: [
            PageStack(),
            Positioned.fill(child: RowMenuLayer()),
            Positioned.fill(child: ZoomLayer()),
            Positioned.fill(child: ToastLayer()),
          ]),
        ),
      ),
    );
  }
}
