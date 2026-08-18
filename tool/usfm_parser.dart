/// Парсер USFM в модель, пригодную для рендера.
///
/// Ключевое решение: стих — это НЕ строка с одним стилем абзаца, а список
/// сегментов. В поэтических книгах один стих регулярно разбит на несколько
/// строк с разными отступами (\q1 / \q2), и модель «один стих — один абзац»
/// превращает Псалтирь в сплошную простыню.
library;

import 'dart:convert';

/// Стили абзаца, которые влияют на отступ и отбивку при рендере.
const paragraphStyles = {
  'p', 'm', 'nb', 'pi1', 'pi2', 'mi', 'cls', // проза
  'q1', 'q2', 'q3', 'q4', 'qc', 'qr', // поэзия
  'li1', 'li2', 'ili', 'ili1', 'ili2', // списки
  'd', // надписание псалма
  'sp', // указание говорящего (Песнь песней)
};

/// Маркеры, которые продолжают начатую мысль от левого края, а не начинают
/// новый абзац.
///
/// По спецификации \m — абзац без отступа, но в Синодальном USFM им помечена
/// каждая печатная строка бумажного издания: в одном Матфее 2615 раз против
/// 1008 обычных \p, а в Послании Петра разорваны даже отдельные слова
/// («Симон» / «Петр,» / «раб» / «и Апостол…»). Считать это новым абзацем —
/// значит показывать прозу рваными обрывками. В KJV таких маркеров нет вовсе.
const continuationStyles = {'m', 'nb'};

/// Заголовки разделов. Не являются частью стиха и хранятся отдельно,
/// иначе они попадут в поиск и в копируемый текст.
const headingStyles = {
  's1': 1, 's2': 2, 's3': 3, 's': 1,
  'ms1': 0, 'ms': 0, 'is1': 1,
};

/// Символьные маркеры, влияющие на начертание внутри стиха.
const inlineMarks = {
  'wj', // слова Христа
  'add', // добавлено переводчиком (в Синодальном — курсив)
  'nd', // имя Бога капителью
  'qs', // «Селах»
  'tl', // транслитерация
  'bk', // название книги
  'sc', // капитель
  'em', 'it', 'bd',
};

class Run {
  String text;
  final List<String> marks;

  /// Для сносок и перекрёстных ссылок: 'f' или 'x'. Такой run не имеет
  /// видимого текста — он рисуется как маркер-якорь.
  final String? noteKind;
  final String? noteText;

  /// Номер Стронга для этого слова (только WEB). В JSON не попадает: хранится
  /// отдельно, иначе разметка удваивает размер БД.
  final String? strong;

  /// Границы run'а в [Verse.plainText]. Проставляются в [finalize].
  ///
  /// Хранить смещения, а не копию текста, принципиально: иначе текст стиха
  /// лежит в БД дважды и, что хуже, две копии могут разойтись при любой
  /// правке нормализации — рендер покажет одно, а поиск найдёт другое.
  int start = -1;
  int end = -1;

  Run(this.text, this.marks, {this.noteKind, this.noteText, this.strong});

  bool get isNote => noteKind != null;
  bool get isEmpty => !isNote && (start < 0 || end <= start);

  Map<String, dynamic> toJson() => {
        if (!isNote) 'a': start,
        if (!isNote) 'z': end,
        if (marks.isNotEmpty) 'm': marks,
        if (noteKind != null) 'n': noteKind,
        if (noteText != null && noteText!.isNotEmpty) 'x': noteText,
      };
}

/// Привязка слова к номеру Стронга через смещения в [Verse.plainText].
/// Смещения, а не индексы слов: по ним UI сразу находит слово под пальцем,
/// и та же схема используется для спанов сущностей.
class StrongSpan {
  final int start;
  final int end;
  final String strong;
  StrongSpan(this.start, this.end, this.strong);
}

class Segment {
  final String style;

  /// true — сегмент начинает новую строку/абзац. false — продолжает предыдущий
  /// (обычный случай, когда несколько стихов идут одним абзацем прозы).
  final bool brk;
  final List<Run> runs = [];

  Segment(this.style, this.brk);

  Map<String, dynamic> toJson() => {
        'p': style,
        if (brk) 'b': 1,
        'r': runs.map((r) => r.toJson()).toList(),
      };
}

class Verse {
  final int chapter;
  final int verse;
  final List<Segment> segments = [];

  /// Чистый текст без сносок — для поиска, копирования и озвучки.
  String plainText = '';

  /// Заполняется в [finalize] по смещениям в [plainText].
  final List<StrongSpan> strongs = [];

  Verse(this.chapter, this.verse);

  /// Приводит стих к финальному виду: считает [plainText] и смещения Стронга,
  /// затем схлопывает соседние runs с одинаковым начертанием.
  ///
  /// Порядок важен: смещения снимаются ДО слияния, пока границы слов ещё
  /// соответствуют исходным `\w`-маркерам.
  void finalize() {
    // Пробелы схлопываются на лету, а границы слов снимаются уже по итоговой
    // строке. Иначе переносы строк из поэзии попадают в plainText, а любая
    // нормализация постфактум сдвигает смещения Стронга.
    final b = StringBuffer();
    var len = 0;
    var pendingSpace = false;

    for (final s in segments) {
      // Сегменты приходят с разных строк исходника, и между ними всегда есть
      // перевод строки — в тексте он становится пробелом. Полагаться на пробел
      // в конце предыдущей строки нельзя: в USFM он стоит не везде, и слова
      // склеиваются в «Авраамродил».
      if (len > 0) pendingSpace = true;
      for (final r in s.runs) {
        if (r.isNote) continue;
        var i = 0;
        var wordStart = -1;
        var wordEnd = -1;
        while (i < r.text.length) {
          final c = r.text[i];
          // «¶» в KJV 2006 — печатный знак абзаца, оставшийся в тексте стиха
          // (2970 стихов). Те же места уже помечены маркером \p, так что
          // символ лишний: иначе он лезет в чтение, в поиск и в копирование.
          if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '¶') {
            if (len > 0) pendingSpace = true;
            i++;
            continue;
          }
          if (pendingSpace) {
            // Пробел-разделитель приписываем этому run'у, чтобы соседние
            // run'ы оставались непрерывными и их можно было схлопывать.
            if (r.start < 0) r.start = len;
            b.write(' ');
            len++;
            pendingSpace = false;
          }
          if (r.start < 0) r.start = len;
          if (wordStart < 0) wordStart = len;
          b.write(c);
          len++;
          wordEnd = len;
          r.end = len;
          i++;
        }
        if (r.strong != null && wordStart >= 0) {
          strongs.add(StrongSpan(wordStart, wordEnd, r.strong!));
        }
      }
    }

    plainText = b.toString();
    strongs.removeWhere(
        (s) => s.start < 0 || s.end > plainText.length || s.start >= s.end);

    // Соседние сегменты одного стиля, не начинающие строку, — это один абзац.
    // Склеиваем их, иначе стих вроде «Авраам родил Исаака…» едет в базу
    // четырьмя сегментами вместо одного.
    for (var i = segments.length - 1; i > 0; i--) {
      final prev = segments[i - 1], cur = segments[i];
      if (cur.brk || cur.style != prev.style) continue;
      prev.runs.addAll(cur.runs);
      segments.removeAt(i);
    }

    for (final s in segments) {
      _mergeRuns(s.runs);
    }
    segments.removeWhere((s) => s.runs.isEmpty);
  }

  static void _mergeRuns(List<Run> runs) {
    runs.removeWhere((r) => r.isEmpty);
    for (var i = runs.length - 1; i > 0; i--) {
      final a = runs[i - 1], b = runs[i];
      if (a.isNote || b.isNote) continue;
      if (a.end != b.start) continue; // непрерывность обязательна
      if (a.marks.length != b.marks.length) continue;
      if (!a.marks.every(b.marks.contains)) continue;
      a.end = b.end;
      runs.removeAt(i);
    }
  }

  String get segmentsJson => jsonEncode(segments.map((s) => s.toJson()).toList());
}

class Heading {
  final int chapter;
  final int beforeVerse;
  final int level;
  final String text;
  Heading(this.chapter, this.beforeVerse, this.level, this.text);
}

class ParsedBook {
  String id = '';
  String name = '';
  String shortName = '';
  String abbrev = '';
  String title = '';
  final List<Verse> verses = [];
  final List<Heading> headings = [];
  int chapterCount = 0;
}

/// Один элемент потока USFM: маркер и относящийся к нему текст.
class _Token {
  final String marker;
  final String text;
  _Token(this.marker, this.text);
}

/// Разбивает исходник на маркеры верхнего уровня. Текст, идущий после маркера
/// (в том числе на следующих строках), приклеивается к нему.
List<_Token> _tokenize(String src) {
  final tokens = <_Token>[];
  final re = RegExp(r'\\([a-z0-9]+\*?)[ \t]?');
  var pos = 0;
  String? marker;
  final buf = StringBuffer();

  void flush() {
    if (marker != null) tokens.add(_Token(marker, buf.toString()));
    buf.clear();
  }

  for (final m in re.allMatches(src)) {
    final tag = m.group(1)!;
    // Символьные маркеры остаются внутри текста — их разбирает _parseInline.
    if (inlineMarks.contains(tag.replaceAll('*', '')) ||
        tag.startsWith('f') && tag != 'fig' ||
        tag.startsWith('x') ||
        tag.startsWith('w')) {
      if (!_isBlockMarker(tag)) continue;
    }
    if (!_isBlockMarker(tag)) continue;
    buf.write(src.substring(pos, m.start));
    flush();
    marker = tag;
    pos = m.end;
  }
  buf.write(src.substring(pos));
  flush();
  return tokens;
}

bool _isBlockMarker(String tag) {
  if (tag.endsWith('*')) return false;
  if (paragraphStyles.contains(tag)) return true;
  if (headingStyles.containsKey(tag)) return true;
  const other = {
    'id', 'ide', 'h', 'toc1', 'toc2', 'toc3', 'mt1', 'mt2', 'mt3', 'mt',
    'c', 'v', 'b', 'ip', 'imt1', 'is1', 'rem', 'cl', 'cp', 'r', 'sr', 'qa',
    'pb', 'periph', 'usfm',
  };
  return other.contains(tag);
}

/// Разбирает символьную разметку внутри текста стиха: слова Христа, курсив
/// переводчика, сноски и перекрёстные ссылки.
List<Run> _parseInline(String raw) {
  final runs = <Run>[];
  final marks = <String>[];
  final buf = StringBuffer();

  void flushText() {
    if (buf.isEmpty) return;
    runs.add(Run(buf.toString(), List.of(marks)));
    buf.clear();
  }

  var i = 0;
  while (i < raw.length) {
    if (raw[i] != '\\') {
      buf.write(raw[i]);
      i++;
      continue;
    }
    // `\+w` — вложенный символьный маркер (встречается внутри сносок и \wj).
    final m = RegExp(r'\\(\+?)([a-z0-9]+)(\*?)').matchAsPrefix(raw, i);
    if (m == null) {
      buf.write(raw[i]);
      i++;
      continue;
    }
    final tag = m.group(2)!;
    // Вложенные маркеры закрываются собственным префиксом: `\+w ... \+w*`.
    // Без учёта `+` поиск закрывающего тега улетает за пределы конструкции и
    // проглатывает остаток стиха.
    final nest = m.group(1)!;
    final closing = m.group(3) == '*';
    i = m.end;
    // Пробел после открывающего маркера — часть синтаксиса USFM и в текст не
    // идёт. После закрывающего он настоящий, и съедать его нельзя: иначе
    // соседние слова слипаются.
    if (!closing && i < raw.length && (raw[i] == ' ' || raw[i] == '\t')) i++;

    if (tag == 'f' || tag == 'x' || tag == 'fe') {
      if (closing) continue;
      // Сноска: дочитываем до закрывающего маркера и извлекаем полезный текст.
      final close = _findClose(raw, nest + tag, i);
      final body = close < 0 ? raw.substring(i) : raw.substring(i, close);
      i = close < 0 ? raw.length : close + nest.length + tag.length + 2;
      flushText();
      runs.add(Run('', const [],
          noteKind: tag == 'x' ? 'x' : 'f', noteText: _cleanNote(body)));
      continue;
    }

    if (tag == 'w') {
      if (closing) continue;
      final close = _findClose(raw, nest + tag, i);
      final body = close < 0 ? raw.substring(i) : raw.substring(i, close);
      i = close < 0 ? raw.length : close + nest.length + tag.length + 2;
      // `\w слово|strong="G1161" lemma="..."\w*` — до вертикальной черты текст,
      // после неё атрибуты.
      final bar = body.indexOf('|');
      final word = bar < 0 ? body : body.substring(0, bar);
      final attrs = bar < 0 ? '' : body.substring(bar + 1);
      final sm = RegExp(r'strong="?([HG][0-9]+[a-z]?)"?').firstMatch(attrs) ??
          RegExp(r'^"?([HG][0-9]+[a-z]?)"?$').firstMatch(attrs.trim());
      flushText();
      runs.add(Run(word, List.of(marks), strong: sm?.group(1)));
      continue;
    }

    if (inlineMarks.contains(tag)) {
      flushText();
      if (closing) {
        marks.remove(tag);
      } else {
        marks.add(tag);
      }
      continue;
    }
    // Прочие символьные маркеры игнорируем, текст внутри них сохраняется.
  }
  flushText();
  return runs;
}

/// Ищет закрывающий маркер `\tag*`, пропуская вложенные пары того же тега.
int _findClose(String raw, String tag, int from) {
  final close = '\\$tag*';
  final open = '\\$tag ';
  var depth = 0;
  var i = from;
  while (i < raw.length) {
    final c = raw.indexOf(close, i);
    if (c < 0) return -1;
    final o = raw.indexOf(open, i);
    if (o >= 0 && o < c) {
      depth++;
      i = o + open.length;
      continue;
    }
    if (depth == 0) return c;
    depth--;
    i = c + close.length;
  }
  return -1;
}

/// Из тела сноски убираем служебные маркеры, оставляя читаемый текст.
String _cleanNote(String body) {
  var s = body;
  s = s.replaceAll(RegExp(r'\\(fr|fq|fqa|fk|fl|fv|ft|fp|xo|xt|xq)\*?'), ' ');
  s = s.replaceAll(RegExp(r'\\[a-z0-9]+\*?'), ' ');
  s = s.replaceFirst(RegExp(r'^\s*[+\-–]\s*'), '');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

ParsedBook parseUsfm(String src) {
  final book = ParsedBook();
  final tokens = _tokenize(src);

  var chapter = 0;
  Verse? verse;
  var currentPara = 'p';
  var pendingBreak = true;
  String? pendingHeading;
  var pendingHeadingLevel = 1;

  void closeVerse() {
    if (verse != null) {
      verse!.finalize();
      if (verse!.segments.isNotEmpty) book.verses.add(verse!);
    }
    verse = null;
  }

  for (final t in tokens) {
    final tag = t.marker;
    final text = t.text;

    switch (tag) {
      case 'id':
        book.id = text.trim().split(RegExp(r'\s+')).first.toUpperCase();
        continue;
      case 'h':
        book.name = text.trim();
        continue;
      case 'toc1':
        if (text.trim().isNotEmpty) book.name = text.trim();
        continue;
      case 'toc2':
        book.shortName = text.trim();
        continue;
      case 'toc3':
        book.abbrev = text.trim();
        continue;
      case 'mt1':
      case 'mt':
        book.title = text.trim();
        continue;
      case 'c':
        closeVerse();
        chapter = int.tryParse(text.trim()) ?? chapter + 1;
        book.chapterCount = chapter > book.chapterCount ? chapter : book.chapterCount;
        pendingBreak = true;
        continue;
      case 'b':
        // Пустая строка между строфами — помечаем разрывом следующий сегмент.
        pendingBreak = true;
        continue;
      case 'v':
        final m = RegExp(r'^\s*([0-9]+)(?:[-–]([0-9]+))?\s*').firstMatch(text);
        if (m == null) continue;
        closeVerse();
        final num = int.parse(m.group(1)!);
        verse = Verse(chapter, num);
        if (pendingHeading != null) {
          book.headings
              .add(Heading(chapter, num, pendingHeadingLevel, pendingHeading));
          pendingHeading = null;
        }
        final seg = Segment(currentPara, pendingBreak);
        pendingBreak = false;
        seg.runs.addAll(_parseInline(text.substring(m.end)));
        verse!.segments.add(seg);
        continue;
    }

    if (headingStyles.containsKey(tag)) {
      pendingHeading = _cleanNote(text);
      pendingHeadingLevel = headingStyles[tag]!;
      continue;
    }

    if (paragraphStyles.contains(tag)) {
      // Продолжение остаётся в том же абзаце и с тем же стилем: иначе рендер
      // всё равно разорвёт строку, увидев смену стиля.
      final continues = continuationStyles.contains(tag) &&
          verse != null &&
          text.trim().isNotEmpty;
      if (!continues) currentPara = tag;
      if (verse == null) {
        // Маркер до первого стиха (например \d — надписание псалма).
        pendingBreak = true;
        if (tag == 'd' && text.trim().isNotEmpty) {
          pendingHeading = _cleanNote(text);
          pendingHeadingLevel = 4; // отдельный уровень для надписаний
        }
        continue;
      }
      // Маркер внутри стиха — новая строка того же стиха.
      final seg = Segment(continues ? currentPara : tag, !continues);
      seg.runs.addAll(_parseInline(text));
      if (seg.runs.any((r) => r.isNote || r.text.trim().isNotEmpty)) {
        verse!.segments.add(seg);
        pendingBreak = false;
      } else {
        // Маркер без текста (обычно стоит перед следующим \v) — сегмент не
        // создаём, но помним, что следующий стих начнёт новую строку.
        pendingBreak = true;
      }
      continue;
    }

    // Текст без собственного маркера дописываем в текущий сегмент.
    if (verse != null && text.trim().isNotEmpty) {
      verse!.segments.last.runs.addAll(_parseInline(text));
    }
  }
  closeVerse();

  if (book.name.isEmpty) book.name = book.title;
  if (book.shortName.isEmpty) book.shortName = book.name;
  if (book.abbrev.isEmpty) book.abbrev = book.shortName;
  return book;
}
