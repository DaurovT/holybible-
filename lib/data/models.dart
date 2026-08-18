/// Модели предметной области.
///
/// Формат стиха повторяет то, что заложено на сборке: текст лежит одной
/// строкой, а разметка — это диапазоны символов в ней. Такая форма нужна,
/// чтобы подсветка сущностей, выделение пользователя, спаны Стронга и
/// результаты поиска говорили об одних и тех же координатах.
library;

import 'dart:convert';

/// Стиль абзаца из USFM. Определяет отступ и отбивку.
enum ParagraphStyle {
  prose,
  poetry1,
  poetry2,
  poetry3,
  listItem,
  psalmTitle,
  speaker,
  indented;

  static ParagraphStyle parse(String? code) => switch (code) {
        'q1' || 'qc' || 'qr' => ParagraphStyle.poetry1,
        'q2' => ParagraphStyle.poetry2,
        'q3' || 'q4' => ParagraphStyle.poetry3,
        'li1' || 'li2' || 'ili' || 'ili1' || 'ili2' => ParagraphStyle.listItem,
        'd' => ParagraphStyle.psalmTitle,
        'sp' => ParagraphStyle.speaker,
        'pi1' || 'pi2' || 'mi' => ParagraphStyle.indented,
        _ => ParagraphStyle.prose,
      };

  bool get isPoetry =>
      this == poetry1 || this == poetry2 || this == poetry3;
}

/// Отрезок текста с единым начертанием либо якорь сноски.
class TextRun {
  final int start;
  final int end;
  final Set<String> marks;

  /// 'f' — сноска, 'x' — перекрёстная ссылка. У таких run'ов нет текста.
  final String? noteKind;
  final String? noteText;

  const TextRun({
    this.start = 0,
    this.end = 0,
    this.marks = const {},
    this.noteKind,
    this.noteText,
  });

  bool get isNote => noteKind != null;

  /// Слова Христа — их принято выделять цветом.
  bool get isWordsOfJesus => marks.contains('wj');

  /// Добавлено переводчиками; в Синодальном набирается курсивом.
  bool get isSupplied => marks.contains('add');

  /// Имя Бога, набираемое капителью.
  bool get isDivineName => marks.contains('nd');

  factory TextRun.fromJson(Map<String, dynamic> j) => TextRun(
        start: (j['a'] as int?) ?? 0,
        end: (j['z'] as int?) ?? 0,
        marks: {...?(j['m'] as List?)?.cast<String>()},
        noteKind: j['n'] as String?,
        noteText: j['x'] as String?,
      );
}

/// Строка или абзац внутри стиха. Стих может состоять из нескольких: в поэзии
/// он регулярно разбит на строки с разными отступами.
class VerseSegment {
  final ParagraphStyle style;

  /// Начинает ли сегмент новую строку. Если нет — продолжает предыдущий
  /// абзац, и стих просто дописывается к соседям.
  final bool breaksLine;
  final List<TextRun> runs;

  const VerseSegment({
    required this.style,
    required this.breaksLine,
    required this.runs,
  });

  factory VerseSegment.fromJson(Map<String, dynamic> j) => VerseSegment(
        style: ParagraphStyle.parse(j['p'] as String?),
        breaksLine: j['b'] == 1,
        runs: [
          for (final r in (j['r'] as List? ?? const []))
            TextRun.fromJson(r as Map<String, dynamic>)
        ],
      );
}

/// Нажимаемая область: слово в тексте, за которым стоит сущность.
class Mention {
  final int start;
  final int end;
  final String entityId;
  final double confidence;
  const Mention(this.start, this.end, this.entityId, this.confidence);
}

class Verse {
  final int id;
  final String translationId;
  final String bookId;
  final int chapter;
  final int number;

  /// Единый ключ стиха, одинаковый во всех переводах.
  final int vkey;

  /// Текст одной строкой. Все диапазоны считаются по нему.
  final String text;
  final List<VerseSegment> segments;
  final List<Mention> mentions;

  /// Смещение, с которого идут слова Христа. Заполнено только у переводов без
  /// своей разметки: в Синодальном USFM маркера \wj нет, и границы перенесены
  /// на сборке из английского издания.
  final int? wjFrom;

  const Verse({
    required this.id,
    required this.translationId,
    required this.bookId,
    required this.chapter,
    required this.number,
    required this.vkey,
    required this.text,
    required this.segments,
    this.mentions = const [],
    this.wjFrom,
  });

  static List<VerseSegment> parseSegments(String json) => [
        for (final s in (jsonDecode(json) as List))
          VerseSegment.fromJson(s as Map<String, dynamic>)
      ];

  Verse withMentions(List<Mention> m) => Verse(
        id: id,
        translationId: translationId,
        bookId: bookId,
        chapter: chapter,
        number: number,
        vkey: vkey,
        text: text,
        segments: segments,
        mentions: m,
        wjFrom: wjFrom,
      );
}

/// Заголовок раздела, стоящий перед стихом.
class Heading {
  final int chapter;
  final int beforeVerse;
  final int level;
  final String text;
  const Heading(this.chapter, this.beforeVerse, this.level, this.text);
}

class Book {
  final String id;
  final int order;
  final bool isNewTestament;
  final int chapters;
  final String name;
  final String shortName;
  final String abbrev;

  const Book({
    required this.id,
    required this.order,
    required this.isNewTestament,
    required this.chapters,
    required this.name,
    required this.shortName,
    required this.abbrev,
  });
}

class Translation {
  final String id;
  final String name;
  final String abbrev;
  final String language;
  final String copyright;
  const Translation({
    required this.id,
    required this.name,
    required this.abbrev,
    required this.language,
    required this.copyright,
  });
}

/// Глава целиком — единица загрузки для экрана чтения.
class Chapter {
  final Book book;
  final int number;
  final List<Verse> verses;
  final List<Heading> headings;
  const Chapter({
    required this.book,
    required this.number,
    required this.verses,
    required this.headings,
  });
}

enum EntityKind {
  person,
  place,
  other;

  static EntityKind parse(String s) => switch (s) {
        'place' => EntityKind.place,
        'other' => EntityKind.other,
        _ => EntityKind.person,
      };
}

/// Связь между сущностями — ребро графа отношений.
class EntityRelation {
  final String rel; // parent | sibling | partner | child | founder | inhabitant
  final String otherId;
  final String? otherName;
  final String? otherBrief;
  final EntityKind? otherKind;
  const EntityRelation({
    required this.rel,
    required this.otherId,
    this.otherName,
    this.otherBrief,
    this.otherKind,
  });

  /// Подпись связи по-русски, с учётом пола связанной сущности.
  String label(String? gender) => switch (rel) {
        'parent' => gender == 'Female' ? 'мать' : 'отец',
        'sibling' => gender == 'Female' ? 'сестра' : 'брат',
        'partner' => gender == 'Female' ? 'жена' : 'муж',
        'child' => gender == 'Female' ? 'дочь' : 'сын',
        'founder' => 'основатель',
        'inhabitant' => 'житель',
        _ => rel,
      };
}

class BibleEntity {
  final String id;
  final EntityKind kind;
  final String? nameRu;
  final String nameEn;
  final String? gender;
  final String? tribe;
  final String? geoArea;
  final double? lat;
  final double? lon;
  final String? modernName;
  final String? placeType;
  final String? imageUrl;
  final String? strong;
  final String? original;
  final String? description;

  /// Четыре длины описания из TIPNR: от подписи в одну строку до статьи.
  final String? briefest;
  final String? brief;
  final String? short;
  final String? article;

  final int refCount;
  final int? firstVkey;

  /// Начало русской статьи, если она есть. Английские `brief` и `article`
  /// пришли из TIPNR и в русском интерфейсе читаются как поломка, поэтому
  /// подпись в списках берётся отсюда, а не из них.
  final String? ruLead;

  const BibleEntity({
    required this.id,
    required this.kind,
    required this.nameEn,
    required this.refCount,
    this.nameRu,
    this.gender,
    this.tribe,
    this.geoArea,
    this.lat,
    this.lon,
    this.modernName,
    this.placeType,
    this.imageUrl,
    this.strong,
    this.original,
    this.description,
    this.briefest,
    this.brief,
    this.short,
    this.article,
    this.firstVkey,
    this.ruLead,
  });

  String get displayName => nameRu ?? nameEn;
  bool get hasLocation => lat != null && lon != null;

  bool get isNewTestament => (firstVkey ?? 0) >= 40000000;

  /// Подпись, которую можно показать всегда: завет и сколько раз встречается.
  /// Нужна там, где русской статьи нет, — иначе половина списка осталась бы
  /// по-английски, а половина по-русски.
  String get factsLine =>
      '${isNewTestament ? 'Новый Завет' : 'Ветхий Завет'} · '
      '$refCount ${mentionsWord(refCount)}';
}

/// «упоминание / упоминания / упоминаний»
String mentionsWord(int n) {
  final mod10 = n % 10, mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return 'упоминание';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return 'упоминания';
  }
  return 'упоминаний';
}
