// 公告列表相關的元件：單則公告、可下拉更新的列表、「全部公告」頁的篩選。

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';

/// 單則公告。點下去用瀏覽器打開校網原文。
class NoticeTile extends StatelessWidget {
  const NoticeTile({super.key, required this.notice});

  final Notice notice;

  Future<void> _open(BuildContext context) async {
    final ok = await launchUrl(Uri.parse(notice.url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('打不開這個網址')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // 判定跟學生無關的公告用淡一點的顏色，提醒使用者這則不會推播
    final titleColor = notice.forStudents ? null : colors.outline;

    return ListTile(
      title: Text(notice.title, style: TextStyle(color: titleColor)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${notice.date} · ${notice.source}'),
            for (final tag in notice.tags) _Tag(tag),
            if (!notice.forStudents) _Tag('跟學生無關', muted: true),
          ],
        ),
      ),
      onTap: () => _open(context),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: muted ? colors.surfaceContainerHighest : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: muted ? colors.outline : colors.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// 可以下拉更新的公告列表。
class NoticeList extends StatelessWidget {
  const NoticeList({
    super.key,
    required this.notices,
    required this.onRefresh,
    required this.emptyText,
    this.header,
  });

  final List<Notice> notices;
  final Future<void> Function() onRefresh;
  final String emptyText;
  final String? header;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return RefreshIndicator(
      onRefresh: onRefresh,
      // 列表是空的也要能下拉，所以永遠保持可以捲動
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (header != null)
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(header!, style: style)),
          if (notices.isEmpty)
            Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(emptyText))),
          for (final n in notices) ...[NoticeTile(notice: n), const Divider(height: 1)],
        ],
      ),
    );
  }
}

/// 「全部公告」頁：上面一排可以點的類別／主題，篩選要看哪些。
class AllNoticesView extends StatefulWidget {
  const AllNoticesView({super.key, required this.data, required this.onRefresh});

  final NoticeData data;
  final Future<void> Function() onRefresh;

  @override
  State<AllNoticesView> createState() => _AllNoticesViewState();
}

class _AllNoticesViewState extends State<AllNoticesView> {
  String? _filter; // null = 全部
  bool _showUnrelated = false; // 是否顯示跟學生無關的公告

  @override
  Widget build(BuildContext context) {
    final options = [...widget.data.categories, ...widget.data.topics];
    final notices = widget.data.notices
        .where((n) => _showUnrelated || n.forStudents)
        .where((n) => _filter == null || n.hasTag(_filter!))
        .toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              _chip('全部', _filter == null, () => setState(() => _filter = null)),
              for (final o in options)
                _chip(widget.data.topics.contains(o) ? '#$o' : o, _filter == o,
                    () => setState(() => _filter = _filter == o ? null : o)),
            ],
          ),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('也顯示跟學生無關的公告（教師研習、標案…）'),
          value: _showUnrelated,
          onChanged: (v) => setState(() => _showUnrelated = v),
        ),
        const Divider(height: 1),
        Expanded(
          child: NoticeList(
            notices: notices,
            onRefresh: widget.onRefresh,
            emptyText: '沒有符合的公告',
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
    );
  }
}
