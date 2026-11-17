// 設定頁：選擇要訂閱的類別和主題。

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';
import 'subscriptions.dart';

// 還沒載入到資料時用的預設清單（跟爬蟲 filters.py 的類別、主題一致）
const _fallbackCategories = ['教務', '學務', '輔導', '獎學金', '比賽'];
const _fallbackTopics = ['考試', '停課'];

const repoUrl = 'https://github.com/cyy-615/hsnu-notice';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.subscriptions, required this.data});

  final Subscriptions subscriptions;
  final NoticeData? data;

  @override
  Widget build(BuildContext context) {
    final categories = data?.categories ?? _fallbackCategories;
    final topics = data?.topics ?? _fallbackTopics;
    final textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: subscriptions,
      builder: (context, _) {
        final items = subscriptions.items;
        Widget toggle(String name, String label) => SwitchListTile(
              title: Text(label),
              value: items.contains(name),
              onChanged: (v) => subscriptions.set(name, v),
            );

        return ListView(
          children: [
            _section(context, '類別', '依公告是哪個處室、哪種事情分類'),
            for (final c in categories) toggle(c, c),
            _section(context, '主題', '比類別更細，把同一件事的公告收在一起'),
            for (final t in topics) toggle(t, '#$t'),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('推播通知開發中'),
              subtitle: const Text('目前請打開 App 下拉更新。想即時收到通知，可以先加入班上的 Discord 公告頻道。'),
            ),
            if (data != null)
              ListTile(
                leading: const Icon(Icons.update),
                title: const Text('最後一次有新公告'),
                // 這個時間只有公告有變動才會更新，所以好幾天沒變不代表壞掉
                subtitle: Text('${data!.updated}（每 30 分鐘檢查一次校網）'),
              ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('原始碼'),
              subtitle: const Text(repoUrl),
              onTap: () => launchUrl(Uri.parse(repoUrl), mode: LaunchMode.externalApplication),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '本 App 只讀取師大附中校網的公開公告，不需要登入，也不會收集任何個人資料。',
                style: textTheme.bodySmall,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _section(BuildContext context, String title, String subtitle) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
          Text(subtitle, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}
