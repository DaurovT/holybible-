// Проверка морфологического поиска на собранной БД.
// Запуск: dart run tool/test_search.dart
import 'package:sqlite3/sqlite3.dart';
import 'package:holy_bible/core/text/russian_stemmer.dart';

/// Строит запрос FTS5: каждое слово ищется и по точной основе, и по
/// огрублённой форме. Колонка stems весит в 20 раз больше — точные совпадения
/// всегда оказываются выше приблизительных.
String buildQuery(String input) {
  final stems = tokenizeAndStem(input);
  if (stems.isEmpty) return '';
  return stems.map((s) {
    final r = reduceFleeting(s);
    final esc = '"$s"';
    return r == s ? '(stems:$esc OR red:$esc)' : '(stems:$esc OR red:"$r")';
  }).join(' AND ');
}

void main() {
  final db = sqlite3.open('assets/db/bible.db');

  print('── пары словоформ (должны давать общую основу) ──');
  for (final p in [
    ['любовь', 'любви'],
    ['день', 'дня'],
    ['отец', 'отца'],
    ['царь', 'царя'],
    ['вера', 'верою'],
  ]) {
    final a = reduceFleeting(stemRussian(p[0]));
    final b = reduceFleeting(stemRussian(p[1]));
    print('  ${p[0]}/${p[1]} → $a / $b  ${a == b ? "✓" : "✗ расходятся"}');
  }

  print('\n── поиск по Синодальному ──');
  for (final q in ['любовь', 'любви', 'вера', 'день', 'нищие духом']) {
    final sw = Stopwatch()..start();
    final rows = db.select('''
      SELECT v.book_id, v.chapter, v.verse, v.text,
             bm25(verse_fts, 20.0, 1.0) AS rank
      FROM verse_fts
      JOIN verses v ON v.id = verse_fts.rowid
      WHERE verse_fts MATCH ? AND v.translation_id = 'syn'
      ORDER BY rank LIMIT 3
    ''', [buildQuery(q)]);
    final total = db.select('''
      SELECT COUNT(*) c FROM verse_fts JOIN verses v ON v.id = verse_fts.rowid
      WHERE verse_fts MATCH ? AND v.translation_id = 'syn'
    ''', [buildQuery(q)]).first['c'];
    sw.stop();
    print('\n«$q» — $total совпадений, ${sw.elapsedMilliseconds} мс');
    for (final r in rows) {
      final t = r['text'] as String;
      print('  ${r['book_id']} ${r['chapter']}:${r['verse']}  '
          '${t.length > 88 ? "${t.substring(0, 88)}…" : t}');
    }
  }

  print('\n── сегменты как смещения ──');
  final v = db.select('''
    SELECT text, segments FROM verses
    WHERE translation_id='web' AND book_id='JHN' AND chapter=3 AND verse=16
  ''').first;
  print('текст: ${v['text']}');
  print('сегменты: ${v['segments']}');

  db.dispose();
}
