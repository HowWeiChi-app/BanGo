// 設定（語言、字體、顏色主題、學校）和顏色。跟 iPhone 版的 AppSettings.swift、Theme.swift 同一套規則：
// 經典 = 照 Reeder 量的顏色；其他主題的紙張、卡片、分隔線都從主色算出來。

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 支援的學校，跟爬蟲的 scraper/schools.py 一致（id、資料檔路徑要一樣）
class School {
  const School(this.id, this.name, this.englishName, this.dataPath);

  final String id;
  final String name;
  final String englishName;
  final String dataPath; // 相對於 GitHub 上的 scraper/data/

  static const all = [
    School('hsnu', '師大附中', 'HSNU', 'notices.json'),
    School('ck', '建國中學', 'Chien Kuo', 'ck/notices.json'),
    School('fg', '北一女中', 'Taipei First Girls', 'fg/notices.json'),
    School('cksh', '成功高中', 'Cheng Kung', 'cksh/notices.json'),
    School('csghs', '中山女高', 'Zhongshan Girls', 'csghs/notices.json'),
  ];

  Uri get dataUrl =>
      Uri.parse('https://raw.githubusercontent.com/HowWeiChi-app/BanGo/main/scraper/data/$dataPath');

  /// 手機上的備份，每校一份（附中沿用舊的名字，舊版存的資料還讀得到）
  String get cacheKey => id == 'hsnu' ? 'notices_cache' : 'notices_cache_$id';

  String get displayName => L(name, englishName);
}

/// 字體：Android 內建的三種（中文跟著系統的思源黑體／思源宋體）
class FontOption {
  const FontOption(this.name, this.englishName, this.family);
  final String name;
  final String englishName;
  final String? family;

  static const all = [
    FontOption('系統', 'System', null),
    FontOption('襯線', 'Serif', 'serif'),
    FontOption('等寬', 'Monospace', 'monospace'),
  ];
}

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final shared = AppSettings._();

  SharedPreferences? _prefs;
  String _language = 'zh';
  int _fontStyle = 0;
  String _themeID = 'classic';
  String _schoolID = 'hsnu';

  /// App 一打開就先讀，第一個畫面就是對的語言和顏色
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _language = _prefs!.getString('language') ?? 'zh';
    _fontStyle = _prefs!.getInt('fontStyle') ?? 0;
    _themeID = _prefs!.getString('themeID') ?? 'classic';
    _schoolID = _prefs!.getString('schoolID') ?? 'hsnu';
  }

  String get language => _language;
  set language(String v) => _set(() => _language = v, (p) => p.setString('language', v));

  int get fontStyle => _fontStyle;
  set fontStyle(int v) => _set(() => _fontStyle = v, (p) => p.setInt('fontStyle', v));

  String get themeID => _themeID;
  set themeID(String v) => _set(() => _themeID = v, (p) => p.setString('themeID', v));

  String get schoolID => _schoolID;
  set schoolID(String v) => _set(() => _schoolID = v, (p) => p.setString('schoolID', v));

  bool get isEnglish => _language == 'en';
  AppTheme get theme => AppTheme.all.firstWhere((t) => t.id == _themeID, orElse: () => AppTheme.all.first);
  School get school => School.all.firstWhere((s) => s.id == _schoolID, orElse: () => School.all.first);
  FontOption get font => FontOption.all[_fontStyle.clamp(0, FontOption.all.length - 1)];

  void _set(void Function() change, void Function(SharedPreferences) save) {
    change();
    notifyListeners();
    if (_prefs != null) save(_prefs!);
  }
}

/// 依照語言設定選中文或英文的字
String L(String zh, String en) => AppSettings.shared.isEnglish ? en : zh;

/// 校網上的類別、主題、來源名稱是中文資料；英文版顯示對應的英文（沒有對照的就照原樣）
class TagName {
  static const _english = {
    '教務': 'Academic', '學務': 'Student Affairs', '輔導': 'Counseling', '獎學金': 'Scholarships',
    '比賽': 'Competitions', '考試': 'Exams', '停課': 'Class Cancellations', '總務': 'General Affairs',
    '圖書館': 'Library', '人事': 'Personnel', '會計': 'Accounting', '國中部': 'Junior High',
    '重要公告': 'Important', '學生': 'Students', '來文公告': 'Official Letters', '行事曆': 'Calendar',
    '校網': 'School Site',
    '最新消息': 'Latest News', '學生園地': 'Student Corner', '來文宣導': 'Announcements',
    '行政公告': 'Administration', '活動競賽': 'Events & Contests', '升學訊息': 'Admissions',
    '獎助學金': 'Financial Aid', '學生專區': 'Students',
  };

  static String display(String name) => AppSettings.shared.isEnglish ? _english[name] ?? name : name;
  static String displayTag(String tag) => tag.startsWith('#') ? '#${display(tag.substring(1))}' : display(tag);
}

// MARK: 顏色

/// 顏色主題。主色決定紙張的色相；經典是照 Reeder 量的
class AppTheme {
  const AppTheme(this.id, this.name, this.englishName, this.accentHex);
  final String id;
  final String name;
  final String englishName;
  final int accentHex;

  String get displayName => L(name, englishName);
  bool get classic => id == 'classic';

  static const all = [
    AppTheme('classic', '經典', 'Classic', 0xE06050),
    AppTheme('amber', '琥珀', 'Amber', 0xB0661A),
    AppTheme('pine', '松針', 'Pine', 0x2F6B4F),
    AppTheme('ink', '墨藍', 'Ink', 0x24407A),
    AppTheme('plum', '梅子', 'Plum', 0x7A2C5C),
    AppTheme('graphite', '石墨', 'Graphite', 0x3B3A38),
    AppTheme('sky', '天空藍', 'Sky', 0x0066CC),
  ];

  Color get _base => Color(0xFF000000 | accentHex);

  /// 主色。深色模式往白色調亮一點，在深色紙上才看得清楚
  Color accent(bool dark) {
    if (classic) return dark ? const Color(0xFFFFC600) : const Color(0xFFE06050);
    return dark ? _mix(_base, Colors.white, 0.38) : _base;
  }

  /// 紙張底色。經典是 Reeder 量的；其他用主色的色相，淺色幾乎白、深色很深
  Color paper(bool dark) {
    if (classic) return dark ? const Color(0xFF1F1E1C) : const Color(0xFFFDFDFC);
    final hsv = HSVColor.fromColor(_base);
    final k = (hsv.saturation / 0.6).clamp(0.0, 1.0); // 灰色系（石墨）就是中性灰
    return dark
        ? HSVColor.fromAHSV(1, hsv.hue, 0.25 * k, 0.125).toColor()
        : HSVColor.fromAHSV(1, hsv.hue, 0.05 * k, 0.99).toColor();
  }
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
Color _rgb(int r, int g, int b) => Color.fromARGB(255, r, g, b);
Color _white(double alpha) => Color.fromRGBO(255, 255, 255, alpha);
Color _black(double alpha) => Color.fromRGBO(0, 0, 0, alpha);

/// 一個主題在淺色或深色模式下的全部顏色。放在 ThemeData 的 extension 裡，畫面用 context.palette 拿
class Palette extends ThemeExtension<Palette> {
  Palette(AppTheme theme, this.dark) {
    final paperColor = theme.paper(dark);
    final c = theme.classic;
    paper = paperColor;
    if (dark) {
      // 深色模式的各種深淺都從紙張顏色算：經典的紙張是 31，下面這些比例剛好算回 Reeder 量到的 44、20、47、65、7
      paperChip = c ? const Color(0xFF33302E) : _mix(paperColor, Colors.white, 0.09);
      cardFill = c ? _rgb(44, 44, 42) : _mix(paperColor, Colors.white, 0.058);
      edgeDark = c ? _rgb(20, 20, 18) : _mix(paperColor, Colors.black, 0.35);
      grooveLight = c ? _rgb(47, 46, 44) : _mix(paperColor, Colors.white, 0.072);
      cardHighlight = c ? _rgb(65, 65, 63) : _mix(paperColor, Colors.white, 0.152);
      edgeShadow = c ? _rgb(7, 7, 6) : _mix(paperColor, Colors.black, 0.77);
      pageRim = cardHighlight;
      ink = _white(0.9);
      inkSecondary = _white(0.6);
      inkTertiary = _white(0.4);
      pageShadow = _black(0.4);
    } else {
      paperChip = c ? const Color(0xFFE3E0D9) : _mix(paperColor, Colors.black, 0.11);
      cardFill = c ? const Color(0xFFEBE8E3) : _mix(paperColor, Colors.black, 0.07);
      edgeDark = _black(0.09);
      grooveLight = _white(0.75);
      cardHighlight = _white(0.9);
      edgeShadow = _black(0.15);
      pageRim = _black(0.12);
      ink = _black(0.75);
      inkSecondary = _black(0.5);
      inkTertiary = _black(0.33);
      pageShadow = _black(0.15);
    }
    brand = theme.accent(dark);

    // 來源的顏色：每個來源的色相固定（重要公告都是橘紅、學生都是藍…），容易分辨；
    // 主題只決定風格：飽和度、亮度跟著主色走（墨藍、松針深而沉，天空藍鮮豔，石墨低彩度）
    final hsv = HSVColor.fromColor(theme.classic ? const Color(0xFFE06050) : theme._base);
    final gray = hsv.saturation < 0.15;
    final lightS = gray ? 0.24 : hsv.saturation.clamp(0.4, 0.8);
    final lightB = gray ? 0.5 : hsv.value.clamp(0.5, 0.82);
    final s = dark ? lightS * 0.8 : lightS;
    final b = dark ? (lightB > (gray ? 0.72 : 0.85) ? lightB : (gray ? 0.72 : 0.85)) : lightB;
    // 橘紅、藍、綠、紫、金：色相彼此至少差 36°
    sources = [0.025, 0.6, 0.4, 0.78, 0.12].map((h) => HSVColor.fromAHSV(1, h * 360, s, b).toColor()).toList();
  }

  final bool dark;
  late final Color paper, paperChip, cardFill, edgeDark, grooveLight, cardHighlight, edgeShadow, pageRim, brand;
  late final Color ink, inkSecondary, inkTertiary, pageShadow;
  late final List<Color> sources;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension PaletteContext on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
}

/// 公告來源的圖示和顏色
class SourceStyle {
  static IconData icon(String source) => switch (source) {
        '重要公告' => Icons.campaign,
        '學生' || '學生園地' || '學生專區' => Icons.groups,
        '來文公告' || '來文宣導' => Icons.mail,
        '行事曆' => Icons.calendar_month,
        '最新消息' => Icons.newspaper,
        '行政公告' => Icons.account_balance,
        '活動競賽' => Icons.emoji_events,
        '升學訊息' => Icons.school,
        '獎助學金' => Icons.paid,
        _ => Icons.description,
      };

  /// 每個來源固定一個顏色（橘紅、藍、綠、紫、金），深淺鮮豔程度跟著顏色主題
  static Color color(BuildContext context, String source) {
    final index = switch (source) {
      '重要公告' || '最新消息' || '行政公告' => 0,
      '學生' || '學生園地' || '學生專區' => 1,
      '來文公告' || '來文宣導' => 2,
      '行事曆' || '升學訊息' => 3,
      '活動競賽' || '獎助學金' => 4,
      _ => -1,
    };
    return index < 0 ? context.palette.inkTertiary : context.palette.sources[index];
  }

  static String name(String source) => source.isEmpty ? '校網' : source;
}

/// 類別、主題的圖示（側邊欄用）
IconData tagIcon(String name) => switch (name) {
      '教務' => Icons.menu_book_outlined,
      '學務' => Icons.directions_walk,
      '輔導' => Icons.favorite_border,
      '獎學金' => Icons.monetization_on_outlined,
      '比賽' => Icons.emoji_events_outlined,
      '考試' => Icons.edit_note,
      '停課' => Icons.warning_amber_rounded,
      _ => Icons.tag,
    };
