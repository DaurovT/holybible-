/// Собирает assets/db/bible.db из USFM-исходников.
///
/// Запуск: dart run tool/build_bible_db.dart
library;

import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:holy_bible/core/text/russian_stemmer.dart';

import 'canon.dart';
import 'usfm_parser.dart';

class TranslationSpec {
  final String id;
  final String dir;
  final String name;
  final String abbrev;
  final String lang;
  final String copyright;
  const TranslationSpec(
      this.id, this.dir, this.name, this.abbrev, this.lang, this.copyright);
}

/// KJV убран 16 августа 2026: два английских перевода в общественном достоянии
/// дублировали друг друга, а платили за это 25 МБ — сам текст плюс половина
/// привязок Стронга. WEB современнее и, в отличие от KJV, размечен номерами.
const translations = <TranslationSpec>[
  TranslationSpec('syn', 'data/raw/russyn', 'Синодальный перевод', 'СИН', 'ru',
      'Public Domain'),
  TranslationSpec('web', 'data/raw/engwebp', 'World English Bible', 'WEB', 'en',
      'Public Domain'),
];

const schema = '''
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;

CREATE TABLE translations (
  id        TEXT PRIMARY KEY,
  name      TEXT NOT NULL,
  abbrev    TEXT NOT NULL,
  lang      TEXT NOT NULL,
  copyright TEXT NOT NULL,
  ord       INTEGER NOT NULL
);

CREATE TABLE books (
  id        TEXT PRIMARY KEY,
  ord       INTEGER NOT NULL,
  testament TEXT NOT NULL,
  chapters  INTEGER NOT NULL
);

CREATE TABLE book_names (
  translation_id TEXT NOT NULL,
  book_id        TEXT NOT NULL,
  name           TEXT NOT NULL,
  short          TEXT NOT NULL,
  abbrev         TEXT NOT NULL,
  PRIMARY KEY (translation_id, book_id)
);

CREATE TABLE verses (
  id             INTEGER PRIMARY KEY,
  translation_id TEXT NOT NULL,
  book_id        TEXT NOT NULL,
  chapter        INTEGER NOT NULL,
  verse          INTEGER NOT NULL,
  vkey           INTEGER NOT NULL,
  text           TEXT NOT NULL,
  segments       TEXT NOT NULL,
  -- Смещение, с которого в стихе начинаются слова Христа. Переводам со своей
  -- разметкой не нужно: там границы лежат прямо в сегментах.
  wj_from        INTEGER
);

CREATE TABLE headings (
  translation_id TEXT NOT NULL,
  book_id        TEXT NOT NULL,
  chapter        INTEGER NOT NULL,
  before_verse   INTEGER NOT NULL,
  level          INTEGER NOT NULL,
  text           TEXT NOT NULL
);
''';

const indexes = '''
CREATE UNIQUE INDEX idx_verses_ref ON verses(translation_id, book_id, chapter, verse);
CREATE INDEX idx_verses_chapter ON verses(translation_id, book_id, chapter);
CREATE INDEX idx_verses_vkey ON verses(vkey, translation_id);
CREATE INDEX idx_headings_ref ON headings(translation_id, book_id, chapter);
''';

void main(List<String> args) {
  final root = Directory.current.path;
  final outPath = '$root/assets/db/bible.db';
  final outFile = File(outPath);
  if (outFile.existsSync()) outFile.deleteSync();
  Directory('$root/assets/db').createSync(recursive: true);

  final db = sqlite3.open(outPath);
  _requireFts5(db);
  db.execute(schema);

  // Номера Стронга живут в отдельном файле: они есть только у WEB, нужны лишь
  // при разборе конкретного слова и весят больше, чем весь остальной текст.
  // В основной БД они утроили бы вес того, что читается при каждом запуске.
  final strongPath = '$root/assets/db/strongs.db';
  if (File(strongPath).existsSync()) File(strongPath).deleteSync();
  final sdb = sqlite3.open(strongPath);
  sdb.execute('PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;');
  sdb.execute('CREATE TABLE strongs('
      'verse_id INTEGER NOT NULL, start INTEGER NOT NULL, '
      'finish INTEGER NOT NULL, strong TEXT NOT NULL);');
  db.execute('''
    CREATE VIRTUAL TABLE verse_fts USING fts5(
      stems,
      red,
      content='',
      tokenize = "unicode61 remove_diacritics 0"
    );
  ''');

  var verseId = 0;
  final bookMeta = <String, ({int ord, String testament, int chapters})>{};

  final insVerse = db.prepare(
      'INSERT INTO verses(id,translation_id,book_id,chapter,verse,vkey,text,segments) '
      'VALUES(?,?,?,?,?,?,?,?)');
  final insFts =
      db.prepare('INSERT INTO verse_fts(rowid,stems,red) VALUES(?,?,?)');
  final insHeading = db.prepare(
      'INSERT INTO headings(translation_id,book_id,chapter,before_verse,level,text) '
      'VALUES(?,?,?,?,?,?)');
  final insStrong = sdb.prepare(
      'INSERT INTO strongs(verse_id,start,finish,strong) VALUES(?,?,?,?)');
  final insBookName = db.prepare(
      'INSERT OR REPLACE INTO book_names(translation_id,book_id,name,short,abbrev) '
      'VALUES(?,?,?,?,?)');

  for (var t = 0; t < translations.length; t++) {
    final spec = translations[t];
    db.execute(
        'INSERT INTO translations(id,name,abbrev,lang,copyright,ord) VALUES(?,?,?,?,?,?)',
        [spec.id, spec.name, spec.abbrev, spec.lang, spec.copyright, t]);

    final dir = Directory('$root/${spec.dir}');
    if (!dir.existsSync()) {
      stderr.writeln('нет каталога ${spec.dir}');
      exit(1);
    }
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.usfm'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    var books = 0, verses = 0, skipped = 0;
    db.execute('BEGIN');
    sdb.execute('BEGIN');

    for (final f in files) {
      final book = parseUsfm(f.readAsStringSync());
      final ord = bookOrder(book.id);
      if (ord == null) {
        // Второканонические книги есть в некоторых изданиях eBible, но канон
        // у переводов разный — держим единый набор из 66 книг.
        skipped++;
        continue;
      }
      books++;
      bookMeta[book.id] = (
        ord: ord,
        testament: isNewTestament(book.id) ? 'NT' : 'OT',
        chapters: book.chapterCount,
      );
      insBookName.execute([
        spec.id,
        book.id,
        book.name,
        book.shortName,
        book.abbrev,
      ]);

      for (final h in book.headings) {
        insHeading
            .execute([spec.id, book.id, h.chapter, h.beforeVerse, h.level, h.text]);
      }

      for (final v in book.verses) {
        if (v.plainText.isEmpty) continue;
        final id = ++verseId;
        insVerse.execute([
          id,
          spec.id,
          book.id,
          v.chapter,
          v.verse,
          verseKey(book.id, v.chapter, v.verse),
          v.plainText,
          v.segmentsJson,
        ]);
        final stems = tokenizeAndStem(v.plainText);
        insFts.execute([
          id,
          stems.join(' '),
          stems.map(reduceFleeting).join(' '),
        ]);
        for (final s in v.strongs) {
          insStrong.execute([id, s.start, s.end, s.strong]);
        }
        verses++;
      }
    }
    db.execute('COMMIT');
    sdb.execute('COMMIT');
    stdout.writeln('${spec.abbrev.padRight(4)} книг $books  стихов $verses'
        '${skipped > 0 ? "  (пропущено неканонических: $skipped)" : ""}');
  }

  final ordered = bookMeta.entries.toList()
    ..sort((a, b) => a.value.ord.compareTo(b.value.ord));
  for (final e in ordered) {
    db.execute('INSERT INTO books(id,ord,testament,chapters) VALUES(?,?,?,?)',
        [e.key, e.value.ord, e.value.testament, e.value.chapters]);
  }

  sdb.execute('CREATE INDEX idx_strongs_verse ON strongs(verse_id)');
  sdb.execute('VACUUM');
  final strongCount =
      sdb.select('SELECT COUNT(*) c FROM strongs').first['c'] as int;
  sdb.dispose();

  _transferWordsOfJesus(db);

  db.execute(indexes);
  db.execute('INSERT INTO verse_fts(verse_fts) VALUES(\'optimize\')');
  db.execute('VACUUM');

  _report(db);
  db.dispose();

  final mb = (outFile.lengthSync() / 1024 / 1024).toStringAsFixed(1);
  final smb = (File(strongPath).lengthSync() / 1024 / 1024).toStringAsFixed(1);
  stdout.writeln('\nbible.db   $mb МБ');
  stdout.writeln('strongs.db $smb МБ — $strongCount привязок, '
      'подключается по требованию');
}

/// Переносит слова Христа на переводы, где своей разметки нет.
///
/// В Синодальном USFM маркера `\wj` нет вовсе, в WEB он стоит 4580 раз.
/// Перенести границы буквально нельзя — другой язык, другой порядок слов, — но
/// в 94% случаев речь либо занимает стих целиком (1411 стихов), либо тянется до
/// его конца после вводных слов (534). Эти два случая переносятся, речь
/// посреди стиха — нет: лучше не покрасить, чем покрасить чужие слова.
void _transferWordsOfJesus(Database db) {
  final whole = <int>{}; // ключи стихов, где речь занимает весь стих
  final tail = <int>{}; // где речь идёт до конца стиха

  for (final row in db.select('''
      SELECT vkey, text, segments FROM verses
      WHERE translation_id = 'web' AND segments LIKE '%"wj"%'
    ''')) {
    var lo = -1, hi = -1;
    for (final seg in jsonDecode(row['segments'] as String) as List) {
      for (final r in ((seg as Map)['r'] as List? ?? const [])) {
        final marks = (r as Map)['m'];
        if (marks is List && marks.contains('wj')) {
          final a = r['a'] as int, z = r['z'] as int;
          if (lo < 0 || a < lo) lo = a;
          if (z > hi) hi = z;
        }
      }
    }
    if (lo < 0) continue;
    final text = row['text'] as String;
    // Речь заканчивается раньше стиха — переносить некуда.
    if (hi < text.length && text.substring(hi).trim().isNotEmpty) continue;
    (lo <= 1 ? whole : tail).add(row['vkey'] as int);
  }

  final update = db.prepare('UPDATE verses SET wj_from = ? WHERE id = ?');
  var full = 0, partial = 0, noAnchor = 0;
  db.execute('BEGIN');
  for (final row in db.select(
      "SELECT id, vkey, text FROM verses WHERE translation_id <> 'web'")) {
    final vkey = row['vkey'] as int;
    if (whole.contains(vkey)) {
      update.execute([0, row['id']]);
      full++;
      continue;
    }
    if (!tail.contains(vkey)) continue;

    // Прямая речь в Синодальном вводится двоеточием: «И сказал им: …».
    // Нет двоеточия — нет и надёжной границы, стих остаётся некрашеным.
    final text = row['text'] as String;
    final colon = text.indexOf(':');
    if (colon < 0) {
      noAnchor++;
      continue;
    }
    var start = colon + 1;
    while (start < text.length && text[start] == ' ') {
      start++;
    }
    update.execute([start, row['id']]);
    partial++;
  }
  db.execute('COMMIT');
  update.dispose();

  stdout.writeln('\n── слова Христа ──');
  stdout.writeln('перенесено на стих целиком: $full');
  stdout.writeln('перенесено от двоеточия:    $partial');
  stdout.writeln('пропущено без двоеточия:    $noAnchor');
}

void _requireFts5(Database db) {
  try {
    db.execute('CREATE VIRTUAL TABLE _probe USING fts5(x)');
    db.execute('DROP TABLE _probe');
  } catch (_) {
    stderr.writeln('SQLite собран без FTS5 — поиск работать не будет.');
    exit(1);
  }
}

void _report(Database db) {
  int one(String sql) => db.select(sql).first.values.first! as int;

  stdout.writeln('\n── проверки ──');
  stdout.writeln('книг:      ${one('SELECT COUNT(*) FROM books')}');
  stdout.writeln('стихов:    ${one('SELECT COUNT(*) FROM verses')}');
  stdout.writeln('заголовков:${one('SELECT COUNT(*) FROM headings')}');

  final empty = one("SELECT COUNT(*) FROM verses WHERE trim(text)=''");
  final dbl = one("SELECT COUNT(*) FROM verses WHERE text LIKE '%  %'");
  final nl = one("SELECT COUNT(*) FROM verses WHERE text LIKE '%' || char(10) || '%'");
  stdout.writeln('пустых: $empty  двойных пробелов: $dbl  переносов строк: $nl');

  // Контроль полноты: в каждом переводе должно быть 66 книг.
  for (final r in db.select(
      'SELECT translation_id, COUNT(DISTINCT book_id) n FROM verses GROUP BY 1')) {
    stdout.writeln('${r['translation_id']}: ${r['n']} книг');
  }

  // Стемминг: «любовь» и «любви» обязаны дать одну основу, иначе русский
  // поиск будет терять формы слова.
  final probe = ['любовь', 'любви', 'любовью', 'веровать', 'веровал'];
  stdout.writeln('стемминг: ${probe.map((w) => '$w→${stemRussian(w)}').join('  ')}');
}
