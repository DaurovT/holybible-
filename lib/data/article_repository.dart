/// Русские статьи из энциклопедии Никифора (1891) и глоссарий.
///
/// Статьи, которые удалось привязать к человеку или месту, показываются в его
/// карточке вместо английского текста. Остальные 3511 — это статьи о предметах,
/// понятиях и обычаях (скиния, ефод, ковчег), которых в слое сущностей нет
/// вовсе; из них и собран глоссарий.
library;

import 'bible_database.dart';

class RussianArticle {
  final int id;
  final String title;
  final String text;
  final String? entityId;

  const RussianArticle({
    required this.id,
    required this.title,
    required this.text,
    this.entityId,
  });

  /// Первая фраза — для списка.
  String get lead {
    final cut = text.indexOf('\n');
    final line = cut < 0 ? text : text.substring(0, cut);
    return line.length <= 140 ? line : '${line.substring(0, 140)}…';
  }
}

RussianArticle _from(Map<String, dynamic> r) => RussianArticle(
      id: r['id'] as int,
      title: r['title'] as String,
      text: r['text'] as String,
      entityId: r['entity_id'] as String?,
    );

extension ArticleQueries on BibleDatabase {
  /// Русская статья о человеке или месте, если она есть.
  RussianArticle? articleForEntity(String entityId) {
    final r = raw.select(
        'SELECT * FROM articles_ru WHERE entity_id = ? LIMIT 1', [entityId]);
    return r.isEmpty ? null : _from(r.first);
  }

  RussianArticle? articleById(int id) {
    final r = raw.select('SELECT * FROM articles_ru WHERE id = ?', [id]);
    return r.isEmpty ? null : _from(r.first);
  }

  /// Статьи энциклопедии, за которыми не стоит наша сущность: предметы,
  /// обычаи, понятия, а также имена из неканонических книг.
  ///
  /// Без запроса показываем самые подробные: алфавит начинается с междометия
  /// «А!» и десятка имён из книг Маккавейских, и как первое впечатление это
  /// никуда не годится. Поиск идёт по началу названия — набрав «ски», человек
  /// ждёт скинию, а не все статьи, где она упомянута.
  List<RussianArticle> browseGlossary({
    String query = '',
    int limit = 60,
    int offset = 0,
  }) {
    final q = query.trim();
    if (q.isEmpty) {
      return [
        for (final r in raw.select('''
          SELECT * FROM articles_ru WHERE entity_id IS NULL
          ORDER BY length(text) DESC LIMIT ? OFFSET ?
        ''', [limit, offset]))
          _from(r)
      ];
    }
    return [
      for (final r in raw.select('''
        SELECT * FROM articles_ru
        WHERE entity_id IS NULL AND title LIKE ? || '%'
        ORDER BY length(title), title LIMIT ?
      ''', [q, limit]))
        _from(r)
    ];
  }

  int glossaryCount() =>
      raw.select('SELECT COUNT(*) c FROM articles_ru WHERE entity_id IS NULL')
          .first['c'] as int;
}
