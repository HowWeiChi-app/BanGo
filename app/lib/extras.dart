// 公告內頁下面的「參考資料」（附件）和「參考網站」，跟 iPhone 版 NoticeExtras.swift 同一套規則。
// RSS 裡沒有（或不完整），所以打開內頁時才去抓校網那一頁，從 HTML 裡找出來。各校的系統不一樣：
//   師大附中   <div class="file_odd"> … <a class="download_btn …" href="….pdf" download="檔名.pdf">
//              <div class="link_odd"> … <a href="https://…" title="名稱">名稱</a>
//   建中（NSS）  附件標題 FEZ012、相關連結 FEZ013 底下，到下一條 <hr> 為止，每個 <a> 是一個檔案／連結
//   北一女、成功、中山（WordPress）  <ul class="nojs_modal_list"><li><a href="…/wp-content/uploads/….pdf">檔名.pdf</a>
// 附件在背景下載，PDF 每一頁畫成圖片直接放在頁面上（點了可以放大）；圖片附件直接顯示。

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app_scope.dart';
import 'images.dart';
import 'router.dart';
import 'settings.dart';
import 'widgets.dart';

class RefLink {
  const RefLink(this.title, this.url);
  final String title;
  final Uri url;
}

class Attachment {
  const Attachment(this.name, this.url);
  final String name;
  final Uri url;

  String get _ext {
    final path = url.path.toLowerCase();
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot + 1);
  }

  bool get isPdf => _ext == 'pdf' || name.toLowerCase().endsWith('.pdf');
  bool get isImage => const ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(_ext);
}

class PageExtras {
  PageExtras([List<Attachment>? files, List<RefLink>? links])
      : files = files ?? [],
        links = links ?? [];
  final List<Attachment> files;
  final List<RefLink> links;
}

// MARK: 解析 HTML

abstract final class ExtrasParser {
  static const hosts = ['www.hs.ntnu.edu.tw', 'www.ck.tp.edu.tw', 'www.fg.tp.edu.tw', 'www.cksh.tp.edu.tw', 'www.csghs.tp.edu.tw'];

  /// 看得懂附件格式的學校（校網網址）
  static bool supports(String pageUrl) => hosts.contains(Uri.tryParse(pageUrl)?.host);

  static PageExtras parse(String html, Uri page) => switch (page.host) {
        'www.hs.ntnu.edu.tw' => _hsnu(html, page),
        'www.ck.tp.edu.tw' => _nss(html, page),
        _ => _wordPress(html, page),
      };

  static final _anchor = RegExp(r'<a\b([^>]*)>(.*?)</a>', dotAll: true);

  /// 師大附中：參考資料、參考網站兩塊
  static PageExtras _hsnu(String html, Uri base) {
    final extras = PageExtras();
    final files = _section(html, 'file_odd');
    if (files != null) {
      for (final tag in RegExp(r'<a\b[^>]*download_btn[^>]*>').allMatches(files)) {
        final attrs = tag.group(0)!;
        final href = _attribute('href', attrs);
        if (href == null) continue;
        final url = base.resolve(_decode(href));
        extras.files.add(Attachment(_decode(_attribute('download', attrs) ?? _lastPath(url)), url));
      }
    }
    final links = _section(html, 'link_odd');
    if (links != null) {
      for (final m in _anchor.allMatches(links)) {
        final href = _attribute('href', m.group(1)!);
        if (href == null) continue;
        final url = base.resolve(_decode(href));
        final text = _plainText(m.group(2)!);
        final title = text.isNotEmpty ? text : (_attribute('title', m.group(1)!).map(_decode) ?? url.toString());
        extras.links.add(RefLink(title, url));
      }
    }
    return extras;
  }

  /// 建中（NSS）：FEZ012 = 附件、FEZ013 = 相關連結，兩塊在同一條 <hr> 之前
  static PageExtras _nss(String html, Uri base) {
    final extras = PageExtras();
    final fileMark = html.indexOf('FEZ012'), linkMark = html.indexOf('FEZ013');
    final marks = [fileMark, linkMark].where((i) => i >= 0).toList();
    if (marks.isEmpty) return extras;
    final first = marks.reduce((a, b) => a < b ? a : b);
    final end = html.indexOf('<hr', first + 6);
    if (end < 0) return extras;
    if (fileMark >= 0 && fileMark + 6 < end) {
      final stop = linkMark > fileMark ? (linkMark < end ? linkMark : end) : end;
      extras.files.addAll(_files(html.substring(fileMark + 6, stop), base));
    }
    if (linkMark >= 0 && linkMark + 6 < end) {
      extras.links.addAll(_files(html.substring(linkMark + 6, end), base).map((f) => RefLink(f.name, f.url)));
    }
    return extras;
  }

  /// WordPress 三校：每個附件一個 <ul class="nojs_modal_list">；同一個檔案可能出現兩次，去掉重複的
  static PageExtras _wordPress(String html, Uri base) {
    final files = <Attachment>[];
    var from = 0;
    while (true) {
      final start = html.indexOf('nojs_modal_list', from);
      if (start < 0) break;
      final end = html.indexOf('</ul>', start);
      if (end < 0) break;
      files.addAll(_files(html.substring(start + 15, end), base));
      from = end + 5;
    }
    final seen = <String>{};
    return PageExtras(files.where((f) => seen.add(f.url.toString())).toList());
  }

  /// 一段 HTML 裡的每個 <a href>：連結 → 附件，連結文字（沒有就用網址最後一段）→ 檔名
  static List<Attachment> _files(String block, Uri base) => [
        for (final m in _anchor.allMatches(block))
          if (_attribute('href', m.group(1)!) case final href?)
            () {
              final url = base.resolve(_decode(href));
              final text = _plainText(m.group(2)!);
              return Attachment(text.isEmpty ? _lastPath(url) : text, url);
            }(),
      ];

  static String _lastPath(Uri url) => url.pathSegments.isEmpty ? url.toString() : Uri.decodeComponent(url.pathSegments.last);

/// 從 `<div class="名稱">` 到它後面第一個 `</ul>`
  static String _plainText(String html) => _decode(html
          .replaceAll(RegExp(r'<svg.*?</svg>', dotAll: true), '')
          .replaceAll(RegExp(r'<[^>]+>'), ''))
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .join(' ');

  /// 從 <div class="名稱"> 到它後面第一個 </ul>
  static String? _section(String html, String className) {
    final start = html.indexOf('<div class="$className"');
    if (start < 0) return null;
    final end = html.indexOf('</ul>', start);
    return end < 0 ? null : html.substring(start, end + 5);
  }

  static String? _attribute(String name, String tag) {
    final i = tag.indexOf(' $name="');
    if (i < 0) return null;
    final from = i + name.length + 3;
    final close = tag.indexOf('"', from);
    if (close < 0) return null;
    final value = tag.substring(from, close);
    return value.isEmpty ? null : value;
  }

  static String _decode(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        final code = int.tryParse(m.group(1)!);
        return code == null || code > 0x10FFFF ? '' : String.fromCharCode(code);
      });
}

extension<T> on T? {
  R? map<R>(R Function(T) f) => this == null ? null : f(this as T);
}

// MARK: 下載

/// 下載好的 PDF。頁面要顯示時才畫，畫好的放在記憶體裡
class PdfPages {
  PdfPages(this._doc);
  final PdfDocument _doc;
  static const maxShown = 10; // 最多顯示幾頁，再多就點檔名看

  final _cache = <String, Future<ui.Image?>>{};

  int get pageCount => _doc.pages.length;

  /// 寬 ÷ 高（pdfrx 的寬高已經算進旋轉了）
  double ratio(int i) {
    final page = _doc.pages[i];
    return page.height > 0 ? page.width / page.height : 1 / 1.414;
  }

  /// 畫一頁，寬 width 像素（白底）
  Future<ui.Image?> render(int i, int width) => _cache.putIfAbsent('$i@$width', () {
        final page = _doc.pages[i];
        final height = (width / ratio(i)).round();
        return page.renderForDisplay(
          width: width,
          height: height,
          fullWidth: width.toDouble(),
          fullHeight: height.toDouble(),
          backgroundColor: 0xFFFFFFFF,
        );
      });

  /// 已經畫好的（放大時先拿來當小圖）
  ui.Image? cachedNow(int i, int width) => _done['$i@$width'];
  final _done = <String, ui.Image>{};

  Future<ui.Image?> renderAndKeep(int i, int width) async {
    final image = await render(i, width);
    if (image != null) _done['$i@$width'] = image;
    return image;
  }
}

sealed class FileContent {}

class PdfContent extends FileContent {
  PdfContent(this.pages);
  final PdfPages pages;
}

class UnsupportedContent extends FileContent {} // Word、Excel 這類，只給下載

class FailedContent extends FileContent {}

/// 抓內頁、下載附件，結果記在記憶體裡：同一則來回滑不用重抓
class ExtrasLoader {
  ExtrasLoader._();
  static final shared = ExtrasLoader._();

  static const _headers = {'User-Agent': 'SchoolNoticeApp/1.0 (student project)'};
  static const _maxFileBytes = 15000000;

  final _pages = <String, Future<PageExtras?>>{};
  final _files = <String, Future<FileContent>>{};

  /// 內頁的附件和參考網站；抓不到回傳 null（下次再試）
  Future<PageExtras?> extras(String pageUrl) {
    final running = _pages.putIfAbsent(pageUrl, () async {
      try {
        final url = Uri.parse(pageUrl);
        final res = await http.get(url, headers: _headers).timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) return null;
        return ExtrasParser.parse(_utf8(res.bodyBytes), url);
      } catch (_) {
        return null;
      }
    });
    running.then((r) {
      if (r == null) _pages.remove(pageUrl);
    });
    return running;
  }

  /// 下載一個附件並取出內容
  Future<FileContent> content(Attachment file) => _files.putIfAbsent(file.url.toString(), () async {
        if (!file.isPdf) return UnsupportedContent();
        try {
          final res = await http.get(file.url, headers: _headers).timeout(const Duration(seconds: 30));
          if (res.statusCode != 200 || res.bodyBytes.length > _maxFileBytes) return FailedContent();
          final doc = await PdfDocument.openData(Uint8List.fromList(res.bodyBytes), sourceName: file.url.toString());
          return doc.pages.isEmpty ? FailedContent() : PdfContent(PdfPages(doc));
        } catch (_) {
          return FailedContent();
        }
      });

  static String _utf8(List<int> bytes) {
    try {
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }
}

// MARK: 畫面

/// 內頁下面的附件和參考網站
class NoticeExtras extends StatefulWidget {
  const NoticeExtras({super.key, required this.pageUrl});
  final String pageUrl;

  @override
  State<NoticeExtras> createState() => _NoticeExtrasState();
}

class _NoticeExtrasState extends State<NoticeExtras> {
  PageExtras? _extras;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    ExtrasLoader.shared.extras(widget.pageUrl).then((r) {
      if (!mounted) return;
      setState(() => r == null ? _failed = true : _extras = r);
    });
  }

  Widget _header(String title) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Groove(length: double.infinity),
        const SizedBox(height: 14),
        Text(title, style: AppText.title3.copyWith(fontWeight: FontWeight.w700, color: p.ink)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final extras = _extras;
    if (extras == null) {
      return _failed
          ? Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(L('附件讀取失敗，請看原文。', 'Couldn\'t load attachments. See the original.'),
                  style: AppText.footnote.copyWith(color: p.inkTertiary)),
            )
          : const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (extras.files.isNotEmpty) ...[
        _header(L('參考資料', 'Attachments')),
        for (final (i, file) in extras.files.indexed) ...[
          if (i > 0) const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Groove(length: double.infinity)),
          _AttachmentView(file: file),
        ],
      ],
      if (extras.links.isNotEmpty) ...[
        _header(L('參考網站', 'Links')),
        for (final link in extras.links)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LinkLabel(icon: Icons.link, text: link.title, onTap: () => openWeb(link.url.toString())),
          ),
      ],
    ]);
  }
}

/// 主色的連結：圖示 + 文字
class LinkLabel extends StatelessWidget {
  const LinkLabel({super.key, required this.icon, required this.text, required this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      link: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 20, color: p.brand)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppText.headline.copyWith(color: p.brand))),
        ]),
      ),
    );
  }
}

/// 一個附件：檔名（點了用瀏覽器打開／下載），下面直接放 PDF 每一頁的圖，點了放大
class _AttachmentView extends StatefulWidget {
  const _AttachmentView({required this.file});
  final Attachment file;

  @override
  State<_AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<_AttachmentView> {
  FileContent? _content;

  @override
  void initState() {
    super.initState();
    if (!widget.file.isImage) {
      ExtrasLoader.shared.content(widget.file).then((c) {
        if (mounted) setState(() => _content = c);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final file = widget.file;
    Widget note(String text) => Text(text, style: AppText.footnote.copyWith(color: p.inkTertiary));
    final content = _content;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LinkLabel(
        icon: file.isPdf ? Icons.picture_as_pdf_outlined : (file.isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined),
        text: file.name,
        onTap: () => openWeb(file.url.toString()),
      ),
      const SizedBox(height: 12),
      if (file.isImage)
        NoticeImage(url: file.url)
      else
        switch (content) {
          null => Row(children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: p.inkTertiary)),
              const SizedBox(width: 8),
              note(L('正在讀取附件…', 'Reading attachment…')),
            ]),
          PdfContent(:final pages) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < pages.pageCount && i < PdfPages.maxShown; i++)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: _PdfPageImage(pages: pages, index: i)),
              if (pages.pageCount > PdfPages.maxShown)
                note(L('還有 ${pages.pageCount - PdfPages.maxShown} 頁，點上面的檔名看完整檔案。',
                    '${pages.pageCount - PdfPages.maxShown} more pages. Tap the file name to see them all.')),
            ]),
          UnsupportedContent() => note(L('這種檔案沒辦法直接顯示，點檔名下載。', 'This file type can\'t be shown here. Tap to download.')),
          FailedContent() => note(L('附件讀取失敗，點檔名用瀏覽器打開。', 'Couldn\'t read this file. Tap to open it in the browser.')),
        },
    ]);
  }
}

/// PDF 的一頁：白底紙張，點了放大（放大後再畫一張更清楚的）
class _PdfPageImage extends StatefulWidget {
  const _PdfPageImage({required this.pages, required this.index});
  final PdfPages pages;
  final int index;

  static const width = 1200; // 列表裡的畫質（像素）
  static const largeWidth = 2600; // 放大後

  @override
  State<_PdfPageImage> createState() => _PdfPageImageState();
}

class _PdfPageImageState extends State<_PdfPageImage> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    widget.pages.renderAndKeep(widget.index, _PdfPageImage.width).then((img) {
      if (mounted) setState(() => _image = img);
    });
  }

  void _zoom() {
    final box = context.findRenderObject() as RenderBox?;
    if (_image == null || box == null) return;
    final pages = widget.pages;
    // 同一個 PDF 的每一頁做成一本相簿：放大後左右滑換頁
    final count = pages.pageCount < PdfPages.maxShown ? pages.pageCount : PdfPages.maxShown;
    AppScope.of(context, listen: false).router.zoom(ZoomRequest(
          pages: [
            for (var i = 0; i < count; i++)
              ZoomPage(
                ratio: pages.ratio(i),
                preview: pages.cachedNow(i, _PdfPageImage.width).map((img) => ZoomImage(raw: img)),
                large: () async {
                  final img = await pages.render(i, _PdfPageImage.largeWidth);
                  return img == null ? null : ZoomImage(raw: img);
                },
              ),
          ],
          start: widget.index,
          from: box.localToGlobal(Offset.zero) & box.size,
          sourceId: this,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final router = AppScope.of(context).router;
    final image = _image;
    return Semantics(
      button: true,
      label: L('附件第 ${widget.index + 1} 頁', 'Attachment page ${widget.index + 1}'),
      child: GestureDetector(
        onTap: _zoom,
        child: Opacity(
          opacity: router.zoomed?.sourceId == this ? 0 : 1,
          child: AspectRatio(
            aspectRatio: widget.pages.ratio(widget.index),
            child: Container(
              foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.edgeDark)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: Colors.white,
                  child: image == null
                      ? const SizedBox.expand()
                      : RawImage(image: image, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
