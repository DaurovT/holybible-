/// Дизайн-система приложения.
///
/// Главная ставка продукта — что читать здесь приятнее, чем где-либо ещё.
/// Поэтому палитра, кегль и интерлиньяж описаны явно и подчинены тексту, а не
/// наоборот: интерфейс должен исчезать.
library;

import 'package:flutter/material.dart';

enum ReadingPalette {
  light('Светлая'),
  sepia('Сепия'),
  dark('Тёмная'),
  night('Ночная');

  const ReadingPalette(this.title);
  final String title;
}

/// Насколько заметны нажимаемые сущности в тексте.
///
/// Синие ссылки убивают чтение: глаз цепляется за каждое второе слово.
/// Поэтому по умолчанию — едва различимый пунктир в цвете самого текста,
/// и его всегда можно убрать совсем.
enum EntityHintLevel {
  none('Не показывать'),
  subtle('Едва заметно'),
  visible('Заметно');

  const EntityHintLevel(this.title);
  final String title;
}

@immutable
class ReadingColors {
  final Color background;
  final Color surface;
  final Color text;
  final Color muted;
  final Color faint;
  final Color accent;

  /// Слова Христа. Красный приглушён: канонический ярко-красный на экране
  /// выглядит кричаще и утомляет глаз на длинном тексте.
  final Color wordsOfJesus;
  final Color verseNumber;
  final Color divider;
  final Color highlight;

  const ReadingColors({
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.wordsOfJesus,
    required this.verseNumber,
    required this.divider,
    required this.highlight,
  });

  static const _light = ReadingColors(
    background: Color(0xFFFCFCFA),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF1C1B19),
    muted: Color(0xFF6B6862),
    faint: Color(0xFFA8A49C),
    accent: Color(0xFF8A5A2B),
    wordsOfJesus: Color(0xFFA33A2E),
    verseNumber: Color(0xFFB0ACA4),
    divider: Color(0xFFE8E5DE),
    highlight: Color(0xFFF2E4C9),
  );

  static const _sepia = ReadingColors(
    background: Color(0xFFF6EEDC),
    surface: Color(0xFFFBF5E7),
    text: Color(0xFF3A2F22),
    muted: Color(0xFF7A6A54),
    faint: Color(0xFFAE9E86),
    accent: Color(0xFF8A5A2B),
    wordsOfJesus: Color(0xFF9C3A2C),
    verseNumber: Color(0xFFB5A489),
    divider: Color(0xFFE3D6BC),
    highlight: Color(0xFFEBD9AE),
  );

  static const _dark = ReadingColors(
    background: Color(0xFF16181A),
    surface: Color(0xFF1E2124),
    text: Color(0xFFDCDCD8),
    muted: Color(0xFF9A9A94),
    faint: Color(0xFF6A6A66),
    accent: Color(0xFFC8A06A),
    wordsOfJesus: Color(0xFFD9776A),
    verseNumber: Color(0xFF6A6A66),
    divider: Color(0xFF2C2F33),
    highlight: Color(0xFF3D3623),
  );

  /// Для чтения в темноте: чистый чёрный фон гасит пиксели на OLED и не
  /// слепит, текст намеренно приглушён.
  static const _night = ReadingColors(
    background: Color(0xFF000000),
    surface: Color(0xFF0C0D0E),
    text: Color(0xFF9E9E99),
    muted: Color(0xFF6E6E6A),
    faint: Color(0xFF4A4A47),
    accent: Color(0xFF9C7B4E),
    wordsOfJesus: Color(0xFFA85F55),
    verseNumber: Color(0xFF4A4A47),
    divider: Color(0xFF1C1D1F),
    highlight: Color(0xFF2A2617),
  );

  static ReadingColors of(ReadingPalette p) => switch (p) {
        ReadingPalette.light => _light,
        ReadingPalette.sepia => _sepia,
        ReadingPalette.dark => _dark,
        ReadingPalette.night => _night,
      };

  bool get isDark =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
}

/// Цвета выделений.
///
/// На светлом фоне это пастель, на тёмном — тот же оттенок, но настолько
/// приглушённый, чтобы текст поверх оставался читаемым. Одна и та же краска в
/// обеих палитрах не работает: пастель на чёрном светится и слепит.
enum HighlightTint {
  yellow('Жёлтый', Color(0xFFF6E6A8), Color(0xFF4A4120)),
  green('Зелёный', Color(0xFFCFE7C2), Color(0xFF2C4227)),
  blue('Голубой', Color(0xFFC8DEF0), Color(0xFF243B4A)),
  rose('Розовый', Color(0xFFF2D0D8), Color(0xFF482932));

  const HighlightTint(this.title, this._light, this._dark);

  final String title;
  final Color _light;
  final Color _dark;

  Color on(ReadingColors c) => c.isDark ? _dark : _light;

  /// Кружок в выборе цвета — на тёмной палитре берём светлый оттенок,
  /// иначе выбирать пришлось бы между четырьмя почти чёрными точками.
  Color swatch(ReadingColors c) => c.isDark ? _light.withValues(alpha: 0.75) : _light;

  static HighlightTint parse(String s) =>
      values.firstWhere((e) => e.name == s, orElse: () => yellow);
}

/// Настройки чтения, которые пользователь меняет сам.
@immutable
class ReadingSettings {
  final ReadingPalette palette;

  /// Кегль основного текста в логических пикселях.
  final double fontSize;

  /// Множитель интерлиньяжа. 1.0 соответствует 1.62 — пропорция, при которой
  /// длинный текст читается без усилия.
  final double lineHeightScale;

  /// Ширина колонки. Строка длиннее ~70 знаков утомляет: глаз теряет начало
  /// следующей строки.
  final double maxLineWidth;

  final String fontFamily;

  /// Абзацный режим — стихи текут сплошным текстом, как в книге.
  /// Иначе каждый стих с новой строки, как в учебном издании.
  final bool paragraphMode;

  final bool showVerseNumbers;
  final bool showWordsOfJesus;
  final bool showFootnotes;
  final EntityHintLevel entityHints;

  const ReadingSettings({
    this.palette = ReadingPalette.light,
    this.fontSize = 19,
    this.lineHeightScale = 1.0,
    this.maxLineWidth = 620,
    this.fontFamily = 'Literata',
    this.paragraphMode = true,
    this.showVerseNumbers = true,
    this.showWordsOfJesus = true,
    this.showFootnotes = true,
    this.entityHints = EntityHintLevel.subtle,
  });

  double get lineHeight => 1.62 * lineHeightScale;

  ReadingColors get colors => ReadingColors.of(palette);

  ReadingSettings copyWith({
    ReadingPalette? palette,
    double? fontSize,
    double? lineHeightScale,
    double? maxLineWidth,
    String? fontFamily,
    bool? paragraphMode,
    bool? showVerseNumbers,
    bool? showWordsOfJesus,
    bool? showFootnotes,
    EntityHintLevel? entityHints,
  }) =>
      ReadingSettings(
        palette: palette ?? this.palette,
        fontSize: fontSize ?? this.fontSize,
        lineHeightScale: lineHeightScale ?? this.lineHeightScale,
        maxLineWidth: maxLineWidth ?? this.maxLineWidth,
        fontFamily: fontFamily ?? this.fontFamily,
        paragraphMode: paragraphMode ?? this.paragraphMode,
        showVerseNumbers: showVerseNumbers ?? this.showVerseNumbers,
        showWordsOfJesus: showWordsOfJesus ?? this.showWordsOfJesus,
        showFootnotes: showFootnotes ?? this.showFootnotes,
        entityHints: entityHints ?? this.entityHints,
      );

  Map<String, dynamic> toJson() => {
        'palette': palette.name,
        'fontSize': fontSize,
        'lineHeightScale': lineHeightScale,
        'fontFamily': fontFamily,
        'paragraphMode': paragraphMode,
        'showVerseNumbers': showVerseNumbers,
        'showWordsOfJesus': showWordsOfJesus,
        'showFootnotes': showFootnotes,
        'entityHints': entityHints.name,
      };

  factory ReadingSettings.fromJson(Map<String, dynamic> j) => ReadingSettings(
        palette: ReadingPalette.values.firstWhere(
            (e) => e.name == j['palette'],
            orElse: () => ReadingPalette.light),
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 19,
        lineHeightScale: (j['lineHeightScale'] as num?)?.toDouble() ?? 1.0,
        fontFamily: j['fontFamily'] as String? ?? 'Literata',
        paragraphMode: j['paragraphMode'] as bool? ?? true,
        showVerseNumbers: j['showVerseNumbers'] as bool? ?? true,
        showWordsOfJesus: j['showWordsOfJesus'] as bool? ?? true,
        showFootnotes: j['showFootnotes'] as bool? ?? true,
        entityHints: EntityHintLevel.values.firstWhere(
            (e) => e.name == j['entityHints'],
            orElse: () => EntityHintLevel.subtle),
      );
}

/// Собирает ThemeData под выбранную палитру. Интерфейс набирается Inter,
/// текст Писания — Literata: она рисовалась именно для чтения с экрана и
/// имеет полноценную кириллицу, что для двуязычного приложения обязательно.
ThemeData buildTheme(ReadingSettings s) {
  final c = s.colors;
  final base = c.isDark ? ThemeData.dark() : ThemeData.light();

  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    colorScheme: (c.isDark
            ? const ColorScheme.dark()
            : const ColorScheme.light())
        .copyWith(
      surface: c.surface,
      primary: c.accent,
      secondary: c.accent,
      onSurface: c.text,
    ),
    dividerColor: c.divider,
    textTheme: base.textTheme.apply(
      fontFamily: 'Inter',
      bodyColor: c.text,
      displayColor: c.text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: c.text,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: c.text,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: TextStyle(
          fontFamily: 'Inter', fontSize: 15, color: c.text),
      subtitleTextStyle: TextStyle(
          fontFamily: 'Inter', fontSize: 13, color: c.muted),
    ),
  );
}
