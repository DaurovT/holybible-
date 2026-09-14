/// Параллельные места: куда ещё ведёт этот стих.
///
/// Данные из OpenBible.info (CC BY), это производная от «Сокровищницы
/// библейских знаний». Связи выверены людьми и голосованием, поэтому их можно
/// показывать как факт, а не как догадку модели.
library;

import 'bible_database.dart';
import 'models.dart';

class CrossReference {
  /// Ключ первого стиха цели.
  final int vkey;

  /// Насколько уверенно связь подтверждена читателями.
  final int votes;

  final String bookId;
  final int chapter;
  final int verse;
  final int verseEnd;
  final String text;

  const CrossReference({
    required this.vkey,
    required this.votes,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.verseEnd,
    required this.text,
  });

  bool get isRange => verseEnd > verse;
}

extension CrossRefQueries on BibleDatabase {
  /// Параллельные места для одного или нескольких стихов сразу.
  ///
  /// Один и тот же адрес приходит от разных стихов отрывка — оставляем
  /// сильнейшую связь, иначе список наполовину состоит из повторов.
  List<CrossReference> crossRefs(
    String translationId,
    List<int> fromVkeys, {
    int limit = 30,
  }) {
    if (fromVkeys.isEmpty) return [];
    final ph = List.filled(fromVkeys.length, '?').join(',');
    final rows = raw.select('''
      SELECT to_vkey, span, MAX(votes) votes
      FROM cross_refs
      WHERE from_vkey IN ($ph)
      GROUP BY to_vkey, span
      ORDER BY votes DESC
      LIMIT ?
    ''', [...fromVkeys, limit]);
    if (rows.isEmpty) return [];

    // Ключ стиха собран как «книга * 1000000 + глава * 1000 + стих», поэтому
    // соседний стих — это +1. Диапазон через границу главы так не растянуть,
    // но таких ссылок в источнике нет: диапазоны всегда внутри главы.
    final keys = <int>[];
    for (final r in rows) {
      final start = r['to_vkey'] as int;
      final span = r['span'] as int;
      for (var i = 0; i <= span; i++) {
        keys.add(start + i);
      }
    }

    final verses = versesByKeys(translationId, keys);
    final out = <CrossReference>[];
    for (final r in rows) {
      final start = r['to_vkey'] as int;
      final span = r['span'] as int;
      final parts = <Verse>[];
      for (var i = 0; i <= span; i++) {
        final v = verses[start + i];
        if (v != null) parts.add(v);
      }
      if (parts.isEmpty) continue;
      out.add(CrossReference(
        vkey: start,
        votes: r['votes'] as int,
        bookId: parts.first.bookId,
        chapter: parts.first.chapter,
        verse: parts.first.number,
        verseEnd: parts.last.number,
        text: parts.map((v) => v.text).join(' '),
      ));
    }
    return out;
  }
}
