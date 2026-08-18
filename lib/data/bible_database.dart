/// Доступ к вшитой библейской базе.
///
/// SQLite не умеет читать файл прямо из бандла Flutter, поэтому при первом
/// запуске база копируется в каталог приложения. Дальше всё работает
/// офлайн и без сети — это принципиально: Библию читают в самолёте, в храме
/// без связи и в странах с блокировками.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'models.dart';

/// Распаковывает сжатую базу из бандла в рабочий файл.
///
/// Потоком, а не целиком в память: распакованная база — это десятки мегабайт,
/// и держать их в памяти ради одной записи на диск незачем.
Future<void> unpackAsset(String asset, File target) async {
  final data = await rootBundle.load(asset);
  final packed = File('${target.path}.gz');
  await packed.writeAsBytes(data.buffer.asUint8List(), flush: true);
  await packed.openRead().transform(gzip.decoder).pipe(target.openWrite());
  await packed.delete();
}

/// Меняется при пересборке assets/db/bible.db. Несовпадение версии
/// перезаписывает копию — иначе после обновления приложения пользователь
/// останется со старым текстом.
const bibleDbVersion = 9;

class BibleDatabase {
  BibleDatabase._(this._db);

  final Database _db;

  static Future<BibleDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'bible_v$bibleDbVersion.db'));

    if (!file.existsSync()) {
      // Старые версии убираем, чтобы копии не копились на устройстве.
      for (final f in dir.listSync()) {
        if (f is File && p.basename(f.path).startsWith('bible_v')) {
          f.deleteSync();
        }
      }
      await unpackAsset('assets/db/bible.db.gz', file);
    }

    final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    return BibleDatabase._(db);
  }

  void dispose() => _db.dispose();

  // ── Справочники ─────────────────────────────────────────────────────────

  List<Translation> translations() => [
        for (final r in _db.select(
            'SELECT id,name,abbrev,lang,copyright FROM translations ORDER BY ord'))
          Translation(
            id: r['id'] as String,
            name: r['name'] as String,
            abbrev: r['abbrev'] as String,
            language: r['lang'] as String,
            copyright: r['copyright'] as String,
          )
      ];

  /// Книги с названиями в выбранном переводе.
  List<Book> books(String translationId) => [
        for (final r in _db.select('''
          SELECT b.id, b.ord, b.testament, b.chapters,
                 n.name, n.short, n.abbrev
          FROM books b
          LEFT JOIN book_names n
            ON n.book_id = b.id AND n.translation_id = ?
          ORDER BY b.ord
        ''', [translationId]))
          Book(
            id: r['id'] as String,
            order: r['ord'] as int,
            isNewTestament: r['testament'] == 'NT',
            chapters: r['chapters'] as int,
            name: (r['name'] as String?) ?? r['id'] as String,
            shortName: (r['short'] as String?) ?? r['id'] as String,
            abbrev: (r['abbrev'] as String?) ?? r['id'] as String,
          )
      ];

  // ── Чтение ──────────────────────────────────────────────────────────────

  /// Загружает главу вместе с нажимаемыми областями.
  ///
  /// Упоминания забираются одним запросом на всю главу, а не по стиху:
  /// иначе на главу уходит под сотню обращений к базе и скролл дёргается.
  Chapter chapter(String translationId, Book book, int number) {
    final rows = _db.select('''
      SELECT id, vkey, verse, text, segments, wj_from
      FROM verses
      WHERE translation_id = ? AND book_id = ? AND chapter = ?
      ORDER BY verse
    ''', [translationId, book.id, number]);

    final ids = [for (final r in rows) r['id'] as int];
    final mentions = <int, List<Mention>>{};
    if (ids.isNotEmpty) {
      final ph = List.filled(ids.length, '?').join(',');
      for (final m in _db.select('''
          SELECT verse_id, start, finish, entity_id, confidence
          FROM mentions WHERE verse_id IN ($ph)
          ORDER BY verse_id, start
        ''', ids)) {
        (mentions[m['verse_id'] as int] ??= []).add(Mention(
          m['start'] as int,
          m['finish'] as int,
          m['entity_id'] as String,
          m['confidence'] as double,
        ));
      }
    }

    final verses = [
      for (final r in rows)
        Verse(
          id: r['id'] as int,
          translationId: translationId,
          bookId: book.id,
          chapter: number,
          number: r['verse'] as int,
          vkey: r['vkey'] as int,
          text: r['text'] as String,
          segments: Verse.parseSegments(r['segments'] as String),
          mentions: mentions[r['id'] as int] ?? const [],
          wjFrom: r['wj_from'] as int?,
        )
    ];

    final headings = [
      for (final r in _db.select('''
        SELECT chapter, before_verse, level, text FROM headings
        WHERE translation_id = ? AND book_id = ? AND chapter = ?
      ''', [translationId, book.id, number]))
        Heading(r['chapter'] as int, r['before_verse'] as int,
            r['level'] as int, r['text'] as String)
    ];

    return Chapter(
        book: book, number: number, verses: verses, headings: headings);
  }

  /// Те же стихи в другом переводе — для параллельного режима.
  /// Ключ результата — [Verse.vkey], по нему строки сопоставляются построчно.
  Map<int, Verse> versesByKeys(String translationId, List<int> vkeys) {
    if (vkeys.isEmpty) return const {};
    final ph = List.filled(vkeys.length, '?').join(',');
    final out = <int, Verse>{};
    for (final r in _db.select('''
        SELECT id, vkey, book_id, chapter, verse, text, segments
        FROM verses WHERE translation_id = ? AND vkey IN ($ph)
      ''', [translationId, ...vkeys])) {
      final k = r['vkey'] as int;
      out[k] = Verse(
        id: r['id'] as int,
        translationId: translationId,
        bookId: r['book_id'] as String,
        chapter: r['chapter'] as int,
        number: r['verse'] as int,
        vkey: k,
        text: r['text'] as String,
        segments: Verse.parseSegments(r['segments'] as String),
      );
    }
    return out;
  }

  /// Сколько стихов в главе — для сетки выбора стиха.
  int verseCount(String translationId, String bookId, int chapter) {
    final r = _db.select('''
      SELECT COUNT(*) c FROM verses
      WHERE translation_id = ? AND book_id = ? AND chapter = ?
    ''', [translationId, bookId, chapter]);
    return r.isEmpty ? 0 : r.first['c'] as int;
  }

  /// Ключ стиха по ссылке. Нужен, чтобы переход вёл к самому стиху, а не к
  /// началу главы.
  int? vkeyFor(String translationId, String bookId, int chapter, int verse) {
    final r = _db.select('''
      SELECT vkey FROM verses
      WHERE translation_id = ? AND book_id = ? AND chapter = ? AND verse = ?
    ''', [translationId, bookId, chapter, verse]);
    return r.isEmpty ? null : r.first['vkey'] as int;
  }

  /// Короткая справка по стиху — для списков упоминаний и результатов поиска.
  ({
    String reference,
    String text,
    String bookId,
    int chapter,
    int verse,
  })? verseByKey(String translationId, int vkey) {
    final r = _db.select('''
      SELECT v.text, v.book_id, v.chapter, v.verse, n.short
      FROM verses v
      LEFT JOIN book_names n
        ON n.book_id = v.book_id AND n.translation_id = v.translation_id
      WHERE v.translation_id = ? AND v.vkey = ?
    ''', [translationId, vkey]);
    if (r.isEmpty) return null;
    final row = r.first;
    return (
      reference: '${row['short'] ?? ''} ${row['chapter']}:${row['verse']}',
      text: row['text'] as String,
      bookId: row['book_id'] as String,
      chapter: row['chapter'] as int,
      verse: row['verse'] as int,
    );
  }

  /// Сколько раз сущность упоминается в каждой книге — «лента жизни» карточки.
  /// Порядок канонический, поэтому список читается как путь по Писанию.
  List<({String bookId, int count, int firstVkey})> refsByBook(
      String entityId) {
    return [
      // Книгу достаём из самого ключа стиха — он собран как
      // «номер книги * 1000000 + глава * 1000 + стих». Это избавляет от
      // присоединения таблицы стихов, которая у каждого перевода своя.
      for (final r in _db.select('''
        SELECT b.id AS book_id, COUNT(*) c, MIN(r.vkey) first_vkey
        FROM entity_refs r
        JOIN books b ON b.ord = r.vkey / 1000000
        WHERE r.entity_id = ?
        GROUP BY b.id
        ORDER BY b.ord
      ''', [entityId]))
        (
          bookId: r['book_id'] as String,
          count: r['c'] as int,
          firstVkey: r['first_vkey'] as int,
        )
    ];
  }

  Database get raw => _db;
}
