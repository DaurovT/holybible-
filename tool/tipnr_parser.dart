/// Парсер TIPNR (Tyndale House / STEPBible, CC BY 4.0).
///
/// Даёт то, что вручную собирать пришлось бы годами: 4553 сущности с уже
/// разрешёнными тёзками (Abdi@1Ch.6.44 и Abdi@2Ch.29.12 — разные люди),
/// граф родства, полный список упоминаний и готовые статьи четырёх длин.
library;

import 'canon.dart';

enum EntityKind { person, place, other }

class EntityName {
  /// Значимость формы: Named, Greek, Variant и т. п.
  final String significance;
  final String english;
  final String original; // иврит или греческий
  final String strong;
  final List<int> refs; // vkey
  EntityName(this.significance, this.english, this.original, this.strong, this.refs);
}

class Entity {
  late String id; // 'Aaron@Exo.4.14-Heb'
  late EntityKind kind;
  String uStrong = '';
  String description = '';
  String summary = '';
  String gender = '';
  String tribe = '';

  /// Только для мест.
  String openBibleName = '';
  String geoArea = '';

  final List<String> parents = [];
  final List<String> siblings = [];
  final List<String> partners = [];
  final List<String> offspring = [];

  /// Для мест: основатель и жители — те же связи, другой смысл.
  final List<String> founders = [];
  final List<String> inhabitants = [];

  String briefest = '';
  String brief = '';
  String short = '';
  String article = '';

  final List<EntityName> names = [];

  /// Все упоминания, объединённые по всем формам имени.
  Set<int> get allRefs => {for (final n in names) ...n.refs};

  String get englishName {
    for (final n in names) {
      if (n.english.isNotEmpty) return n.english;
    }
    return id.split('@').first;
  }

  String get primaryStrong => uStrong.isNotEmpty
      ? uStrong
      : (names.isNotEmpty ? names.first.strong : '');

  String get original {
    for (final n in names) {
      if (n.original.isNotEmpty) return n.original;
    }
    return '';
  }
}

/// Убирает пометки TIPNR: (?) — спорное отождествление, (d) — родоначальник
/// народа, (a) — предок, (f) — основатель места.
String _cleanRef(String s) =>
    s.replaceAll(RegExp(r'\((\?|d|a|f)\)'), '').trim();

/// Разбирает ссылку вида `Exo.4.14` в единый ключ стиха.
/// Возвращает null для форм, которые нельзя разложить однозначно
/// (сокращения `4.27ff` в строке Total и диапазоны).
int? _parseRef(String raw) {
  final s = _cleanRef(raw);
  if (s.isEmpty) return null;
  final m = RegExp(r'^([1-3]?[A-Za-z]{2,3})\.(\d+)\.(\d+)').firstMatch(s);
  if (m == null) return null;
  final usfm = tipnrToUsfm[m.group(1)!];
  if (usfm == null) return null;
  return verseKey(usfm, int.parse(m.group(2)!), int.parse(m.group(3)!));
}

List<int> _parseRefList(String field) {
  final out = <int>[];
  for (final part in field.split(';')) {
    final v = _parseRef(part);
    if (v != null) out.add(v);
  }
  return out;
}

/// Разбирает список связанных сущностей: `Amram@Exo.6.18-1Ch + Jochebed@...`
/// или запятыми. Возвращает уникальные имена без пометок.
List<String> _parseLinks(String field) {
  if (field.trim().isEmpty || field.trim() == '>') return const [];
  return field
      .split(RegExp(r'[,+]'))
      .map(_cleanRef)
      .where((s) => s.isNotEmpty && s.contains('@'))
      .toList();
}

List<Entity> parseTipnr(String src) {
  final out = <Entity>[];
  final lines = src.split('\n');

  EntityKind? section;
  Entity? cur;
  var inData = false;

  void flush() {
    if (cur != null && cur!.names.isNotEmpty) out.add(cur!);
    cur = null;
  }

  for (final raw in lines) {
    final line = raw.trimRight();

    if (line.startsWith(r'$=')) {
      flush();
      if (line.contains('PERSON')) {
        section = EntityKind.person;
      } else if (line.contains('PLACE')) {
        section = EntityKind.place;
      } else if (line.contains('OTHER')) {
        section = EntityKind.other;
      }
      // Первые вхождения этих заголовков — часть документации формата,
      // настоящие записи начинаются после блока с разделителями.
      inData = true;
      continue;
    }
    if (section == null || !inData) continue;

    final f = line.split('\t');

    // Подзапись с формой имени.
    if (line.startsWith('–') || line.startsWith('-')) {
      if (cur == null) continue;
      final sig = f[0].replaceFirst(RegExp(r'^[–-]\s*'), '').trim();
      if (sig == 'Total' || sig.isEmpty) continue;
      if (f.length < 6) continue;

      // `H0175«H0175=אַהֲרֹן` → отделяем номер Стронга от оригинала.
      final strongField = f[2];
      final eq = strongField.indexOf('=');
      final strong = (eq < 0 ? strongField : strongField.substring(0, eq))
          .split('«')
          .first
          .trim();
      final original = eq < 0 ? '' : strongField.substring(eq + 1).trim();

      // `Aaron (KJV: Aaron)` — берём первое, основное написание.
      final english = f[3].split('(').first.trim();

      cur!.names.add(EntityName(sig, english, original, strong, _parseRefList(f[5])));
      continue;
    }

    if (line.startsWith('@')) {
      if (cur == null) continue;
      final i = line.indexOf('=');
      if (i < 0) continue;
      final key = line.substring(1, i).trim();
      final val = line.substring(i + 1).trim();
      switch (key) {
        case 'Briefest':
          cur!.briefest = val;
        case 'Brief':
          cur!.brief = val;
        case 'Short':
          cur!.short = val;
        case 'Article':
          cur!.article = _stripRefTags(val);
      }
      continue;
    }

    // Заголовок новой записи: первое поле содержит уникальное имя с '@'.
    if (f.isNotEmpty && f[0].contains('@')) {
      flush();
      final e = Entity()..kind = section;
      final head = f[0];
      final eq = head.lastIndexOf('=');
      e.id = _cleanRef(eq < 0 ? head : head.substring(0, eq));
      e.uStrong = eq < 0 ? '' : head.substring(eq + 1).trim();

      String at(int i) => i < f.length ? f[i].trim() : '';

      if (section == EntityKind.place) {
        e.openBibleName = at(1).split('=').first.trim();
        e.founders.addAll(_parseLinks(at(2)));
        e.inhabitants.addAll(_parseLinks(at(3)));
        e.geoArea = at(6) == '>' ? '' : at(6);
      } else {
        e.description = at(1);
        e.parents.addAll(_parseLinks(at(2)));
        e.siblings.addAll(_parseLinks(at(3)));
        e.partners.addAll(_parseLinks(at(4)));
        e.offspring.addAll(_parseLinks(at(5)));
        final tr = at(6);
        e.tribe = tr == '>' ? '' : tr;
        e.gender = at(8);
      }
      e.summary = at(7).replaceFirst(RegExp(r'^#'), '').trim();
      e.summary = _stripRefTags(e.summary);
      cur = e;
    }
  }
  flush();
  return out;
}

/// В статьях ссылки размечены как `<ref="Exo.4.14">Exo.4.14</ref>`.
/// Разметку снимаем, но сами ссылки сохраняем в тексте — их подсветит
/// приложение, разобрав уже по своим правилам.
///
/// `<br>` в TIPNR разделяет абзацы статьи и написан то строчными, то
/// прописными: разбор по точному совпадению пропускал 3368 статей, и тег
/// показывался читателю как текст.
String _stripRefTags(String s) => s
    .replaceAll(RegExp(r'<ref="[^"]*">'), '')
    .replaceAll('</ref>', '')
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n\n')
    // Остальная разметка в тексте статьи не нужна: начертание, ссылки на сайт.
    .replaceAll(RegExp(r'</?(strong|b|i|a)\b[^>]*>', caseSensitive: false), '')
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAll(RegExp(r' *\n *'), '\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
