// 公告內頁，照 iPhone 版 NoticeDetailView：
// 來源、大標題、日期、分類（點了跳到那一類）、圖片、內文（網址變成連結）、[原文]，
// 最後是校網內頁的附件（PDF 每一頁直接放上來）和參考網站。
// 左上角返回時間軸；右上角打開原文、分享。往左滑換到上面那則、往右滑回時間軸由 PageStack 處理。

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'app_scope.dart';
import 'extras.dart';
import 'images.dart';
import 'models.dart';
import 'settings.dart';
import 'store.dart';
import 'widgets.dart';

class ArticlePage extends StatefulWidget {
  const ArticlePage({super.key, required this.notice});
  final Notice notice;

  @override
  State<ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends State<ArticlePage> {
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final s = _scroll.offset > 1;
      if (s != _scrolled) setState(() => _scrolled = s);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = AppScope.of(context).router;
    final notice = widget.notice;
    final url = Uri.tryParse(notice.url);
    return Paper(
      child: Stack(children: [
        SelectionArea(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(22, MediaQuery.paddingOf(context).top + TopBar.height + 8, 22,
                40 + MediaQuery.paddingOf(context).bottom),
            child: _ArticleBody(notice: notice),
          ),
        ),
        TopBar(
          solid: _scrolled,
          leading: GlassPill(circle: true, child: PillButton(icon: Icons.arrow_back_ios_new, label: L('返回', 'Back'), onTap: router.back)),
          trailing: url == null
              ? null
              : GlassPill(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    PillButton(icon: Icons.explore_outlined, label: L('閱讀原文', 'Open Original'), onTap: () => openWeb(notice.url)),
                    Builder(
                      builder: (context) => PillButton(
                        icon: Icons.ios_share,
                        label: L('分享', 'Share'),
                        onTap: () {
                          final box = context.findRenderObject() as RenderBox?;
                          SharePlus.instance.share(ShareParams(
                            uri: url,
                            subject: notice.title,
                            sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
                          ));
                        },
                      ),
                    ),
                  ]),
                ),
        ),
      ]),
    );
  }
}

/// 內文本身：拉的時候每一格都會重畫外面，這一塊沒變就不用重排
class _ArticleBody extends StatelessWidget {
  const _ArticleBody({required this.notice});
  final Notice notice;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final router = AppScope.of(context, listen: false).router;
    final host = Uri.tryParse(notice.url)?.host ?? '';
    final meta = [AppSettings.shared.school.displayName, TagName.display(SourceStyle.name(notice.source)), notice.dept]
        .where((s) => s.isNotEmpty)
        .join(' · ');
    final paragraphs = notice.content.split('\n').where((s) => s.trim().isNotEmpty).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SourceAvatar(source: notice.source, size: 34),
        const SizedBox(width: 10),
        Flexible(child: Text(host, style: AppText.headline.copyWith(color: p.ink))),
      ]),
      const SizedBox(height: 14),
      Text(notice.title, style: AppText.largeTitle.copyWith(color: notice.isUrgent ? Colors.red : p.ink)),
      const SizedBox(height: 8),
      DefaultTextStyle.merge(
        style: AppText.subheadline.copyWith(fontWeight: FontWeight.w600, color: p.inkSecondary),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(notice.longDate),
          const SizedBox(height: 2),
          Text(meta),
        ]),
      ),
      if (notice.tags.isNotEmpty) ...[
        const SizedBox(height: 24),
        for (final tag in notice.tags)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Semantics(
              button: true,
              hint: L('打開這一類的公告', 'Show notices in this category'),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // tags 裡主題前面有 #，篩選用的名稱不含 #
                onTap: () => router.jump(NoticeFilter.tag(tag.startsWith('#') ? tag.substring(1) : tag)),
                child: Row(children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Text(TagName.displayTag(tag), style: AppText.headline.copyWith(color: p.brand)),
                ]),
              ),
            ),
          ),
      ],
      if (notice.imageUri != null) ...[
        const SizedBox(height: 24),
        NoticeImage(url: notice.imageUri!),
      ],
      const SizedBox(height: 24),
      for (final paragraph in paragraphs)
        Padding(padding: const EdgeInsets.only(bottom: 14), child: _LinkedText(paragraph)),
      // 「原文」連結用主色
      GestureDetector(
        onTap: () => openWeb(notice.url),
        child: Text(L('[原文]', '[Original]'), style: AppText.body.copyWith(fontWeight: FontWeight.w600, color: p.brand)),
      ),
      if (ExtrasParser.supports(notice.url)) NoticeExtras(pageUrl: notice.url),
    ]);
  }
}

/// 一段內文：裡面的網址變成可以點的連結（用 App 裡的瀏覽器打開）
class _LinkedText extends StatefulWidget {
  const _LinkedText(this.text);
  final String text;

  @override
  State<_LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<_LinkedText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final spans = <InlineSpan>[];
    var last = 0;
    for (final link in Linkify.find(widget.text)) {
      if (link.start > last) spans.add(TextSpan(text: widget.text.substring(last, link.start)));
      final recognizer = TapGestureRecognizer()..onTap = () => openWeb(link.url);
      _recognizers.add(recognizer);
      spans.add(TextSpan(text: widget.text.substring(link.start, link.end), style: TextStyle(color: p.brand), recognizer: recognizer));
      last = link.end;
    }
    if (last < widget.text.length) spans.add(TextSpan(text: widget.text.substring(last)));
    return Text.rich(TextSpan(children: spans), style: AppText.body.copyWith(color: p.ink, height: 1.55));
  }
}

/// 找出文字裡的網址
abstract final class Linkify {
  static final _pattern = RegExp(r'(?:https?://|www\.)[^\s<>"]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', caseSensitive: false);

  static List<({int start, int end, String url})> find(String text) {
    final result = <({int start, int end, String url})>[];
    for (final m in _pattern.allMatches(text)) {
      var raw = m.group(0)!;
      // 網址後面緊接著中文時，只留到第一個非 ASCII 字元；去掉結尾的標點
      final cut = raw.runes.toList().indexWhere((c) => c > 127);
      if (cut >= 0) raw = String.fromCharCodes(raw.runes.take(cut));
      while (raw.isNotEmpty && '.,;:)）'.contains(raw[raw.length - 1])) {
        raw = raw.substring(0, raw.length - 1);
      }
      if (raw.isEmpty) continue;
      final url = raw.contains('://')
          ? raw
          : raw.contains('@') && !raw.toLowerCase().startsWith('www.')
              ? 'mailto:$raw'
              : 'https://$raw';
      result.add((start: m.start, end: m.start + raw.length, url: url));
    }
    return result;
  }
}
