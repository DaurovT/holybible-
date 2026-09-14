/// Кладёт в bible.db русские статьи из энциклопедии Никифора (1891).
///
/// До сих пор все статьи в приложении были английскими — переводом с TIPNR.
/// Здесь появляется русский текст, а заодно и глоссарий: в энциклопедии есть
/// статьи о предметах и понятиях (скиния, ефод, ковчег), которых в нашем слое
/// сущностей нет вовсе.
///
/// Запуск: dart run tool/build_articles_ru.dart (после build_entities)
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const schema = '''
DROP TABLE IF EXISTS articles_ru;
CREATE TABLE articles_ru (
  id        INTEGER PRIMARY KEY,
  title     TEXT NOT NULL,
  text      TEXT NOT NULL,
  -- К какой сущности привязана статья. NULL — статья о предмете или понятии,
  -- которого в слое сущностей нет: из таких и складывается глоссарий.
  entity_id TEXT
);
CREATE INDEX idx_articles_entity ON articles_ru(entity_id);
CREATE INDEX idx_articles_title ON articles_ru(title);
''';

/// Разбирает содержимое шаблона `{{…}}`.
///
/// `{{Библия|Исх|28:1|т=XXVIII, 1}}` — это ссылка на место Писания, её
/// превращаем в обычный текст «Исх 28:1». Остальные шаблоны — служебные
/// (качество страницы, оформление), они выбрасываются.
String _template(String body) {
  final parts = body.split('|');
  final name = parts.first.trim().toLowerCase();
  if (name != 'библия' || parts.length < 3) return '';
  final book = parts[1].trim();
  final ref = parts[2].trim();
  // Метки, чтобы потом отличить ссылку от обычного текста: в источнике перед
  // шаблоном обычно уже стоит название книги, и без этого выходит «Исх. Исх».
  return '\u0001$book\u0002$ref\u0001';
}

/// Одна ли это книга: «Числ.» и «Чис», «Осии» и «Ос», «I Цар.» и «1Цар».
bool _sameBook(String a, String b) {
  String norm(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'^iii\s*'), '3')
      .replaceAll(RegExp(r'^ii\s*'), '2')
      .replaceAll(RegExp(r'^iv\s*'), '4')
      .replaceAll(RegExp(r'^i\s*'), '1')
      .replaceAll(RegExp(r'[^а-я0-9]'), '');
  final x = norm(a), y = norm(b);
  if (x.isEmpty || y.isEmpty) return false;
  return x.startsWith(y) || y.startsWith(x);
}

/// Убирает удвоение названия книги вокруг ссылки.
String _collapseRefs(String text) {
  // Строка не «сырая» намеренно: метки \u0001 и \u0002 должны попасть в шаблон
  // символами, а не буквами.
  final pattern = RegExp(
      '((?:[IVX]+\\s+)?[А-Яа-яЁё]+\\.?)?\\s*\u0001([^\u0002]+)\u0002([^\u0001]+)\u0001');
  return text.replaceAllMapped(pattern, (m) {
    final before = m.group(1);
    final book = m.group(2)!;
    final ref = m.group(3)!;
    if (before != null && _sameBook(before, book)) return '$before $ref';
    return before == null ? '$book $ref' : '$before $book $ref';
  }).replaceAll('\u0001', '').replaceAll('\u0002', ' ');
}

/// Снимает вики-разметку, оставляя читаемый текст.
final _serviceLink = RegExp(
    r'^\s*(Категория|Category|Файл|File|Изображение|Image)\s*:',
    caseSensitive: false);

String cleanWikitext(String src) {
  final out = StringBuffer();
  var i = 0;

  while (i < src.length) {
    // Шаблоны, в том числе вложенные.
    if (src.startsWith('{{', i)) {
      var depth = 1;
      var j = i + 2;
      final body = StringBuffer();
      while (j < src.length && depth > 0) {
        if (src.startsWith('{{', j)) {
          depth++;
          j += 2;
        } else if (src.startsWith('}}', j)) {
          depth--;
          j += 2;
          if (depth == 0) break;
        } else {
          if (depth == 1) body.write(src[j]);
          j++;
        }
      }
      out.write(_template(body.toString()));
      i = j;
      continue;
    }

    // Ссылки: [[страница|подпись]] → подпись.
    if (src.startsWith('[[', i)) {
      final end = src.indexOf(']]', i);
      if (end > 0) {
        final inner = src.substring(i + 2, end);
        // Служебные метки Викитеки — не текст. Без подписи их разбор ниже
        // выводил как есть, и в конце 4574 статей из 4581 стояло
        // «Категория:БЭАН:Статьи без категорий».
        if (_serviceLink.hasMatch(inner)) {
          i = end + 2;
          continue;
        }
        final pipe = inner.lastIndexOf('|');
        out.write(pipe < 0 ? inner : inner.substring(pipe + 1));
        i = end + 2;
        continue;
      }
    }

    // Сноски выбрасываем целиком, остальные теги — только сами скобки.
    if (src.startsWith('<ref', i)) {
      final close = src.indexOf('</ref>', i);
      final selfClose = src.indexOf('/>', i);
      if (close > 0) {
        i = close + 6;
        continue;
      }
      if (selfClose > 0) {
        i = selfClose + 2;
        continue;
      }
    }
    if (src[i] == '<') {
      final end = src.indexOf('>', i);
      if (end > 0 && end - i < 60) {
        i = end + 1;
        continue;
      }
    }

    out.write(src[i]);
    i++;
  }

  var text = _collapseRefs(out.toString());
  // Начертание, заголовки разделов, внешние ссылки.
  text = text.replaceAll(RegExp("'{2,5}"), '');
  text = text.replaceAll(RegExp(r'^=+.*=+$', multiLine: true), '');
  text = text.replaceAllMapped(
      RegExp(r'\[https?://\S+\s+([^\]]+)\]'), (m) => m.group(1)!);
  text = text.replaceAll(RegExp(r'\[https?://\S+\]'), '');
  // Пробелы и пустые строки.
  text = text.replaceAll('\u00a0', ' ');
  // «28:6,Исх 39:2» — в источнике ссылки идут через запятую без пробела.
  text = text.replaceAll(RegExp(r',(?=[А-ЯA-Zа-яa-z])'), ', ');
  text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
  text = text.replaceAll(RegExp(r' *\n *'), '\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

String _normalize(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().replaceAll('ё', 'е').split('')) {
    if (RegExp(r'[а-яa-z0-9]').hasMatch(ch)) b.write(ch);
  }
  return b.toString();
}

/// Заголовок статьи → имена, под которыми её стоит искать.
///
/// «Аварим, Аваримские горы» — это два имени одной статьи, а «Авдон (город)» —
/// имя с уточнением, которое в наших данных не встречается.
List<String> namesFromTitle(String title) {
  var name = title.startsWith('БЭАН/') ? title.substring(5) : title;
  name = name.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
  return [
    for (final part in name.split(','))
      if (part.trim().isNotEmpty) part.trim()
  ];
}

void main() {
  final root = Directory.current.path;
  final source = File('$root/data/raw/nikifor/articles.json');
  if (!source.existsSync()) {
    stderr.writeln('нет ${source.path} — сначала dart run tool/fetch_nikifor.dart');
    exit(1);
  }

  final raw = jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
  final db = sqlite3.open('$root/assets/db/bible.db');
  db.execute('PRAGMA journal_mode = OFF');
  db.execute(schema);

  // Сущности по нормализованному русскому имени; при совпадении имён держим
  // самую упоминаемую — статья энциклопедии почти всегда именно о ней.
  final byName = <String, ({String id, int refs})>{};
  for (final r in db.select(
      "SELECT id, name_ru, ref_count FROM entities WHERE name_ru IS NOT NULL")) {
    final key = _normalize(r['name_ru'] as String);
    final refs = r['ref_count'] as int;
    final known = byName[key];
    if (known == null || refs > known.refs) {
      byName[key] = (id: r['id'] as String, refs: refs);
    }
  }

  final insert = db.prepare(
      'INSERT INTO articles_ru(title,text,entity_id) VALUES(?,?,?)');

  var kept = 0, linked = 0, redirects = 0, empty = 0;
  db.execute('BEGIN');
  for (final entry in raw.entries) {
    final wiki = entry.value as String;
    if (RegExp(r'^\s*#(REDIRECT|ПЕРЕНАПРАВЛЕНИЕ)', caseSensitive: false)
        .hasMatch(wiki)) {
      redirects++;
      continue;
    }

    final text = cleanWikitext(wiki);
    // Заглушки в две строки пользы не несут.
    if (text.length < 40) {
      empty++;
      continue;
    }

    final names = namesFromTitle(entry.key);
    if (names.isEmpty) continue;

    String? entityId;
    for (final n in names) {
      final match = byName[_normalize(n)];
      if (match != null) {
        entityId = match.id;
        break;
      }
    }
    if (entityId != null) linked++;

    insert.execute([names.first, text, entityId]);
    kept++;
  }
  db.execute('COMMIT');
  insert.dispose();
  db.execute('VACUUM');

  final glossary = db
      .select('SELECT COUNT(*) c FROM articles_ru WHERE entity_id IS NULL')
      .first['c'];
  final withRu = db
      .select('SELECT COUNT(DISTINCT entity_id) c FROM articles_ru '
          'WHERE entity_id IS NOT NULL')
      .first['c'];

  stdout.writeln('── русские статьи ──');
  stdout.writeln('всего в источнике:   ${raw.length}');
  stdout.writeln('перенаправлений:     $redirects');
  stdout.writeln('пустых и заглушек:   $empty');
  stdout.writeln('сохранено статей:    $kept');
  stdout.writeln('привязано к людям и местам: $linked (сущностей: $withRu)');
  stdout.writeln('осталось для глоссария:     $glossary');

  for (final title in ['Аарон', 'Скиния', 'Ефод']) {
    final r = db.select(
        'SELECT text, entity_id FROM articles_ru WHERE title = ?', [title]);
    if (r.isEmpty) continue;
    final t = r.first['text'] as String;
    stdout.writeln('\n$title (${r.first['entity_id'] ?? 'глоссарий'}):');
    stdout.writeln('  ${t.substring(0, t.length < 180 ? t.length : 180)}…');
  }

  db.dispose();
  final mb = (File('$root/assets/db/bible.db').lengthSync() / 1048576)
      .toStringAsFixed(1);
  stdout.writeln('\nbible.db — $mb МБ');
}
