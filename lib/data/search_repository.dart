/// Полнотекстовый поиск по Писанию с учётом русской морфологии.
library;

import '../core/text/russian_stemmer.dart';
import 'bible_database.dart';

class SearchHit {
  final int verseId;
  final int vkey;
  final String bookId;
  final String bookName;
  final int chapter;
  final int verse;
  final String text;

  /// Диапазоны найденных слов в [text] — для подсветки.
  final List<(int, int)> highlights;

  const SearchHit({
    required this.verseId,
    required this.vkey,
    required this.bookId,
    required this.bookName,
    required this.chapter,
    required this.verse,
    required this.text,
    required this.highlights,
  });

  String get reference => '$bookName $chapter:$verse';
}

extension SearchQueries on BibleDatabase {
  /// Строит запрос FTS5.
  ///
  /// Каждое слово ищется и по точной основе, и по огрублённой форме без
  /// беглой гласной. Колонка точных основ весит в 20 раз больше, поэтому
  /// «любовь» находит и «любви», но буквальные совпадения всегда сверху.
  String _buildMatch(String input) {
    final stems = tokenizeAndStem(input);
    if (stems.isEmpty) return '';
    return stems.map((s) {
      final safe = s.replaceAll('"', '');
      final r = reduceFleeting(safe);
      return r == safe
          ? '(stems:"$safe" OR red:"$safe")'
          : '(stems:"$safe" OR red:"$r")';
    }).join(' AND ');
  }

  ({List<SearchHit> hits, int total}) search(
    String query, {
    required String translationId,
    String? bookId,
    int limit = 50,
    int offset = 0,
  }) {
    final match = _buildMatch(query);
    if (match.isEmpty) return (hits: const <SearchHit>[], total: 0);

    final filter = bookId == null ? '' : 'AND v.book_id = ?';
    final args = <Object?>[match, translationId, ?bookId];

    final total = raw.select('''
      SELECT COUNT(*) c FROM verse_fts f
      JOIN verses v ON v.id = f.rowid
      WHERE verse_fts MATCH ? AND v.translation_id = ? $filter
    ''', args).first['c'] as int;

    final rows = raw.select('''
      SELECT v.id, v.vkey, v.book_id, v.chapter, v.verse, v.text, n.short,
             bm25(verse_fts, 20.0, 1.0) AS rank
      FROM verse_fts f
      JOIN verses v ON v.id = f.rowid
      LEFT JOIN book_names n
        ON n.book_id = v.book_id AND n.translation_id = v.translation_id
      WHERE verse_fts MATCH ? AND v.translation_id = ? $filter
      ORDER BY rank, v.vkey
      LIMIT ? OFFSET ?
    ''', [...args, limit, offset]);

    // Подсветку считаем на стороне приложения: у FTS индексированы основы, а
    // показать надо исходные слова из текста стиха.
    final wanted = tokenizeAndStem(query).toSet();
    final wantedReduced = wanted.map(reduceFleeting).toSet();

    return (
      total: total,
      hits: [
        for (final r in rows)
          () {
            final text = r['text'] as String;
            final spans = <(int, int)>[];
            for (final t in tokenizeWithOffsets(text)) {
              if (wanted.contains(t.stem) ||
                  wantedReduced.contains(reduceFleeting(t.stem))) {
                spans.add((t.start, t.end));
              }
            }
            return SearchHit(
              verseId: r['id'] as int,
              vkey: r['vkey'] as int,
              bookId: r['book_id'] as String,
              bookName: (r['short'] as String?) ?? r['book_id'] as String,
              chapter: r['chapter'] as int,
              verse: r['verse'] as int,
              text: text,
              highlights: spans,
            );
          }()
      ],
    );
  }
}
