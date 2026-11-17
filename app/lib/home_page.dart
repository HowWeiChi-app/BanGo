// 主畫面：下方三個分頁「我的公告」「全部公告」「設定」，並負責載入資料。

import 'package:material_ui/material_ui.dart';

import 'models.dart';
import 'notice_list.dart';
import 'repository.dart';
import 'settings_page.dart';
import 'subscriptions.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.repository, required this.subscriptions});

  final NoticeRepository repository;
  final Subscriptions subscriptions;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  NoticeData? _data;
  bool _loading = true;
  String? _error;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// 先顯示手機上存的舊資料（打開馬上有東西看），再到網路抓新的。
  Future<void> _start() async {
    await widget.subscriptions.load();
    final cached = await widget.repository.loadCached();
    if (mounted && cached != null) setState(() => _data = cached);
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final data = await widget.repository.fetch();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '更新失敗，請檢查網路（$e）');
      if (_data != null) {
        // 已經有舊資料可以看，就用底部提示，不要整頁蓋掉
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('更新失敗，目前顯示的是上次的資料')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['我的公告', '全部公告', '設定'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        bottom: _loading && _data != null
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator())
            : null,
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: '我的公告'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: '全部公告'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '設定'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final data = _data;

    if (_tab == 2) {
      return SettingsPage(subscriptions: widget.subscriptions, data: data);
    }

    // 第一次打開、還沒有任何資料
    if (data == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _ErrorView(message: _error ?? '沒有資料', onRetry: _refresh);
    }

    if (_tab == 0) {
      // 訂閱設定一改就重畫
      return ListenableBuilder(
        listenable: widget.subscriptions,
        builder: (context, _) {
          final subscribed = widget.subscriptions.items;
          final mine = data.notices.where((n) => n.matches(subscribed)).toList();
          return NoticeList(
            notices: mine,
            onRefresh: _refresh,
            header: '依你訂閱的 ${subscribed.length} 個類別篩選（可到「設定」調整）',
            emptyText: subscribed.isEmpty ? '你還沒有訂閱任何類別，到「設定」打開幾個吧' : '目前沒有符合你訂閱類別的公告',
          );
        },
      );
    }

    return AllNoticesView(data: data, onRefresh: _refresh);
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重試')),
          ],
        ),
      ),
    );
  }
}
