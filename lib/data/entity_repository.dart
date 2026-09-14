/// Запросы к слою сущностей: карточки людей, мест и понятий, граф связей,
/// списки упоминаний.
library;

import 'bible_database.dart';
import 'models.dart';

BibleEntity _entityFrom(Map<String, dynamic> r) => BibleEntity(
      id: r['id'] as String,
      kind: EntityKind.parse(r['kind'] as String),
      nameRu: r['name_ru'] as String?,
      nameEn: (r['name_en'] as String?) ?? '',
      gender: r['gender'] as String?,
      tribe: r['tribe'] as String?,
      geoArea: r['geo_area'] as String?,
      lat: r['lat'] as double?,
      lon: r['lon'] as double?,
      modernName: r['modern'] as String?,
      placeType: r['place_type'] as String?,
      imageUrl: r['image_url'] as String?,
      strong: r['strong'] as String?,
      original: r['original'] as String?,
      description: r['descr'] as String?,
      briefest: r['briefest'] as String?,
      brief: r['brief'] as String?,
      short: r['short'] as String?,
      article: r['article'] as String?,
      refCount: (r['ref_count'] as int?) ?? 0,
      firstVkey: r['first_vkey'] as int?,
      ruLead: r.containsKey('ru_lead') ? r['ru_lead'] as String? : null,
    );

/// Первые строки русской статьи — подзапросом, чтобы список рисовался одним
/// обращением к базе, а не одним на строку.
const _ruLead = "(SELECT substr(a.text, 1, 200) FROM articles_ru a "
    "WHERE a.entity_id = e.id LIMIT 1) AS ru_lead";

extension EntityQueries on BibleDatabase {
  BibleEntity? entity(String id) {
    final r = raw.select(
        'SELECT e.*, $_ruLead FROM entities e WHERE id = ?', [id]);
    return r.isEmpty ? null : _entityFrom(r.first);
  }

  /// Несколько сущностей разом — для панели под стихом, где нажимаемых слов
  /// может быть несколько.
  List<BibleEntity> entities(List<String> ids) {
    // Пустой ответ тоже изменяемый: списки сущностей вызывающие сортируют, а
    // `const []` на этом падает — «Cannot modify an unmodifiable list». Стих
    // без единой распознанной сущности встречается сплошь и рядом.
    if (ids.isEmpty) return [];
    final ph = List.filled(ids.length, '?').join(',');
    return [
      for (final r in raw
          .select('SELECT e.*, $_ruLead FROM entities e '
              'WHERE id IN ($ph)', ids))
        _entityFrom(r)
    ];
  }

  /// Связи сущности вместе с именами соседей — граф рисуется без доп. запросов.
  List<EntityRelation> relations(String id) => [
        for (final r in raw.select('''
          SELECT rl.rel, rl.other_id, e.name_ru, e.name_en, e.briefest, e.kind
          FROM entity_rel rl
          LEFT JOIN entities e ON e.id = rl.other_id
          WHERE rl.entity_id = ?
        ''', [id]))
          EntityRelation(
            rel: r['rel'] as String,
            otherId: r['other_id'] as String,
            otherName: (r['name_ru'] as String?) ?? (r['name_en'] as String?),
            otherBrief: r['briefest'] as String?,
            otherKind: r['kind'] == null
                ? null
                : EntityKind.parse(r['kind'] as String),
          )
      ];

  /// Обратные связи: у кого эта сущность указана родителем, супругом и т. д.
  /// Без них граф однобокий — у ребёнка виден отец, а у отца ребёнок нет.
  List<EntityRelation> inverseRelations(String id) => [
        for (final r in raw.select('''
          SELECT rl.rel, rl.entity_id AS other_id, e.name_ru, e.name_en,
                 e.briefest, e.kind
          FROM entity_rel rl
          LEFT JOIN entities e ON e.id = rl.entity_id
          WHERE rl.other_id = ?
        ''', [id]))
          EntityRelation(
            rel: switch (r['rel'] as String) {
              'parent' => 'child',
              'child' => 'parent',
              _ => r['rel'] as String,
            },
            otherId: r['other_id'] as String,
            otherName: (r['name_ru'] as String?) ?? (r['name_en'] as String?),
            otherBrief: r['briefest'] as String?,
            otherKind: r['kind'] == null
                ? null
                : EntityKind.parse(r['kind'] as String),
          )
      ];

  /// Все места Писания, где сущность упоминается.
  List<int> entityRefs(String id, {int limit = 2000}) => [
        for (final r in raw.select(
            'SELECT vkey FROM entity_refs WHERE entity_id = ? '
            'ORDER BY vkey LIMIT ?',
            [id, limit]))
          r['vkey'] as int
      ];

  /// Человек дня. Выбор жёстко привязан к дате: в один и тот же день у всех
  /// один и тот же человек, и он не меняется при каждом открытии экрана.
  ///
  /// Берём только тех, у кого есть русское имя, статья и хотя бы два десятка
  /// упоминаний. Иначе на главный экран выпадает Азаил, сирийский царь из
  /// второй книги Царств: формально он в базе есть, но человеком дня ему быть
  /// не за что.
  BibleEntity? personOfTheDay(DateTime date, {int pool = 150}) {
    final rows = raw.select('''
      SELECT * FROM entities
      WHERE kind = 'person' AND article IS NOT NULL
        AND name_ru IS NOT NULL AND ref_count >= 20
      ORDER BY ref_count DESC, id LIMIT ?
    ''', [pool]);
    if (rows.isEmpty) return null;
    final days = DateTime.utc(date.year, date.month, date.day)
        .difference(DateTime.utc(2000))
        .inDays;
    return _entityFrom(rows[days.abs() % rows.length]);
  }

  /// Каталог для раздела «Исследовать»: самые упоминаемые впереди.
  List<BibleEntity> browse({
    EntityKind? kind,
    String? testament,
    int limit = 100,
    int offset = 0,
  }) {
    final where = <String>[];
    final args = <Object?>[];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind.name);
    }
    if (testament == 'NT') {
      where.add('first_vkey >= 40000000');
    } else if (testament == 'OT') {
      where.add('first_vkey < 40000000');
    }
    // Сущности без единого упоминания в карточке показывать нечем.
    where.add('ref_count > 0');
    final sql = 'SELECT e.*, $_ruLead FROM entities e '
        'WHERE ${where.join(' AND ')} '
        'ORDER BY ref_count DESC, id LIMIT ? OFFSET ?';
    return [
      for (final r in raw.select(sql, [...args, limit, offset])) _entityFrom(r)
    ];
  }

  /// Поиск сущности по имени — для строки поиска в «Исследовать».
  List<BibleEntity> searchEntities(String query, {int limit = 40}) {
    final q = query.trim();
    if (q.length < 2) return [];
    // Префиксный запрос: пользователь набирает имя по буквам.
    final match = '"${q.replaceAll('"', '')}"*';
    return [
      for (final r in raw.select('''
        SELECT e.*, $_ruLead FROM entity_fts f
        JOIN entities e ON e.rowid = f.rowid
        WHERE entity_fts MATCH ?
        ORDER BY e.ref_count DESC LIMIT ?
      ''', [match, limit]))
        _entityFrom(r)
    ];
  }

  /// Места с координатами — для карты.
  List<BibleEntity> placesWithLocation({int limit = 1200}) => [
        for (final r in raw.select(
            "SELECT * FROM entities WHERE kind='place' AND lat IS NOT NULL "
            'ORDER BY ref_count DESC LIMIT ?',
            [limit]))
          _entityFrom(r)
      ];
}
