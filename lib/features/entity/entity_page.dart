/// Полная страница сущности: статья, связи, все упоминания, карточка места.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/bible_reference.dart';
import '../../core/theme/design.dart';
import '../../data/article_repository.dart';
import '../../data/bible_database.dart';
import '../../data/entity_repository.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../map/bible_map.dart';
import 'relations_graph.dart';

/// Уводит в читалку и закрывает всё, что открыто поверх неё: карточку,
/// нижнюю панель, страницу сущности.
void _goToVerse(BuildContext context, WidgetRef ref,
    {required String bookId, required int chapter, int? vkey}) {
  openInReader(ref, bookId: bookId, chapter: chapter, vkey: vkey);
  Navigator.of(context).popUntil((r) => r.isFirst);
}

class EntityPage extends ConsumerWidget {
  const EntityPage({super.key, required this.entityId});
  final String entityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = s.colors;
    final db = ref.watch(bibleDbProvider).valueOrNull;
    final e = db?.entity(entityId);

    if (db == null || e == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Связи в обе стороны: в данных записан только один конец ребра, и без
    // обратных связей у отца не видно детей.
    final relations = [...db.relations(entityId), ...db.inverseRelations(entityId)];
    final refs = db.entityRefs(entityId, limit: 1000);
    final byBook = db.refsByBook(entityId);
    final russian = db.articleForEntity(entityId);
    final translation = ref.watch(translationProvider);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(e.displayName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Insets.screen, 8, Insets.screen, 60),
        children: [
          Text(
            e.displayName,
            style: TextStyle(
                fontFamily: 'Literata',
                fontSize: 30,
                fontWeight: FontWeight.w600,
                height: 1.15,
                color: c.text),
          ),
          if (e.nameRu != null && e.nameEn.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(e.nameEn,
                  style: TextStyle(
                      fontFamily: 'Inter', fontSize: 14, color: c.faint)),
            ),
          const SizedBox(height: 8),
          Text(e.factsLine,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  height: 1.5,
                  color: c.muted)),

          if (e.original != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(e.original!,
                    style: TextStyle(
                        fontFamily: 'Literata', fontSize: 20, color: c.text)),
                const SizedBox(width: 10),
                if (e.strong != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(e.strong!,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: c.muted)),
                  ),
              ],
            ),
          ],

          if (russian != null) ...[
            const SizedBox(height: 26),
            SectionTitle('Кто это'),
            const SizedBox(height: 10),
            Text(
              russian.text,
              style: TextStyle(
                  fontFamily: s.fontFamily,
                  fontSize: s.fontSize * 0.94,
                  height: 1.65,
                  color: c.text),
            ),
            const SizedBox(height: 8),
            Text(
              'Источник: Библейская энциклопедия архимандрита Никифора '
              '(1891), из Викитеки',
              style:
                  TextStyle(fontFamily: 'Inter', fontSize: 11, color: c.faint),
            ),
          ]
          // Русской статьи нет — английскую из TIPNR не выдаём за описание, а
          // предлагаем открыть: это перевод, которого никто не переводил, и
          // посреди русской карточки он читается как поломка.
          else if (e.article != null || e.short != null) ...[
            const SizedBox(height: 26),
            _EnglishArticle(text: e.article ?? e.short!),
          ],

          if (e.hasLocation) ...[
            const SizedBox(height: 30),
            SectionTitle('Где это'),
            const SizedBox(height: 10),
            BibleMap(
              focus: e,
              onTapPlace: (place) {
                if (place.id == e.id) return;
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EntityPage(entityId: place.id)));
              },
            ),
            const SizedBox(height: 6),
            Text('Сведите пальцы, чтобы приблизить. Нажатие на точку открывает '
                'место.', style: AppText.caption(c)),
            const SizedBox(height: 10),
            _PlaceCard(entity: e),
          ],

          if (relations.isNotEmpty) ...[
            const SizedBox(height: 30),
            SectionTitle('Связи'),
            const SizedBox(height: 12),
            RelationsGraph(entity: e, relations: relations),
          ],

          if (byBook.isNotEmpty) ...[
            const SizedBox(height: 30),
            SectionTitle('Где встречается'),
            const SizedBox(height: 4),
            Text(
              'Книги идут в каноническом порядке — список читается как путь '
              'по Писанию. Нажатие открывает первое упоминание в книге.',
              style:
                  TextStyle(fontFamily: 'Inter', fontSize: 12, color: c.faint),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in byBook)
                  _BookChip(
                      bookId: r.bookId, count: r.count, firstVkey: r.firstVkey),
              ],
            ),
          ],

          if (refs.isNotEmpty) ...[
            const SizedBox(height: 30),
            SectionTitle('Все упоминания · ${e.refCount}'),
            const SizedBox(height: 10),
            _References(db: db, translationId: translation, vkeys: refs),
          ],
        ],
      ),
    );
  }
}

/// Книга, где встречается сущность, со счётчиком упоминаний.
class _BookChip extends ConsumerWidget {
  const _BookChip({
    required this.bookId,
    required this.count,
    required this.firstVkey,
  });

  final String bookId;
  final int count;
  final int firstVkey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
    final book = books.where((b) => b.id == bookId).firstOrNull;
    final db = ref.watch(bibleDbProvider).valueOrNull;

    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          final v = db?.verseByKey(ref.read(translationProvider), firstVkey);
          if (v == null) return;
          _goToVerse(context, ref,
              bookId: v.bookId, chapter: v.chapter, vkey: firstVkey);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(book == null ? bookId : bookLabel(book),
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.text)),
              const SizedBox(width: 6),
              Text('$count',
                  style: TextStyle(
                      fontFamily: 'Inter', fontSize: 12, color: c.faint)),
            ],
          ),
        ),
      ),
    );
  }
}


/// Английская справка Tyndale House — под честной подписью и по нажатию.
///
/// Русская энциклопедия покрывает 1785 сущностей из 4259; у остальных есть
/// только английский текст. Показывать его как основное описание нельзя —
/// человек читает русскую книгу, — но и выбрасывать жаль: часто это
/// единственное, что о человеке вообще известно.
class _EnglishArticle extends ConsumerStatefulWidget {
  const _EnglishArticle({required this.text});
  final String text;

  @override
  ConsumerState<_EnglishArticle> createState() => _EnglishArticleState();
}

class _EnglishArticleState extends ConsumerState<_EnglishArticle> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final c = s.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text('Справка на английском',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.muted)),
                const SizedBox(width: 4),
                Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: c.faint),
              ],
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 6),
          Text(
            widget.text,
            style: TextStyle(
                fontFamily: s.fontFamily,
                fontSize: s.fontSize * 0.9,
                height: 1.6,
                color: c.muted),
          ),
          const SizedBox(height: 8),
          Text('Источник: Tyndale House, Cambridge (CC BY 4.0)',
              style: AppText.caption(c).copyWith(fontSize: 11)),
        ],
      ],
    );
  }
}

class _PlaceCard extends ConsumerWidget {
  const _PlaceCard({required this.entity});
  final BibleEntity entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entity.modernName != null)
            _Row(label: 'Современное название', value: entity.modernName!),
          if (entity.placeType != null)
            _Row(label: 'Тип', value: _typeRu(entity.placeType!)),
          if (entity.geoArea != null)
            _Row(label: 'Область', value: _areaRu(entity.geoArea!)),
          _Row(
            label: 'Координаты',
            value: '${entity.lat!.toStringAsFixed(4)}, '
                '${entity.lon!.toStringAsFixed(4)}',
          ),
          const SizedBox(height: 4),
          Text('Данные: OpenBible.info (CC BY 4.0)',
              style:
                  TextStyle(fontFamily: 'Inter', fontSize: 11, color: c.faint)),
        ],
      ),
    );
  }

  /// Тип места из OpenBible — там их три десятка, и все по-английски.
  static String _typeRu(String t) => switch (t) {
        'settlement' => 'поселение',
        'river' => 'река',
        'mountain' => 'гора',
        'mountain range' => 'горная цепь',
        'mountain pass' => 'горный проход',
        'hill' => 'холм',
        'region' => 'область',
        'district in settlement' => 'часть города',
        'water' || 'body of water' => 'водоём',
        'island' => 'остров',
        'valley' => 'долина',
        'natural area' => 'местность',
        'people group' => 'народ',
        'campsite' => 'стоянка',
        'structure' => 'постройка',
        'road' => 'дорога',
        'canal' => 'канал',
        'gate' => 'ворота',
        'well' => 'колодец',
        'spring' => 'источник',
        'pool' => 'водоём',
        'cliff' => 'утёс',
        'rock' => 'скала',
        'field' => 'поле',
        'forest' => 'лес',
        'garden' => 'сад',
        'tree' => 'дерево',
        'hall' => 'зал',
        'room' => 'комната',
        _ => t,
      };

  /// Историческая область: у OpenBible это либо страна, либо надел колена.
  static String _areaRu(String a) {
    final tribe = RegExp(r'^Tribe of (\w+)').firstMatch(a);
    if (tribe != null) {
      return 'надел колена ${_tribes[tribe.group(1)] ?? tribe.group(1)}';
    }
    return _areas[a.replaceAll('(?)', '').trim()] ?? a;
  }

  static const _tribes = {
    'Benjamin': 'Вениаминова',
    'Judah': 'Иудина',
    'Simeon': 'Симеонова',
    'Dan': 'Данова',
    'Manasseh': 'Манассиина',
  };

  static const _areas = {
    'Edom': 'Едом',
    'Philistia': 'Филистия',
    'Assyria': 'Ассирия',
    'Judea': 'Иудея',
    'Cyprus': 'Кипр',
    'Mesopotamia': 'Месопотамия',
    'Persia': 'Персия',
    'Greece': 'Греция',
    'Arabia': 'Аравия',
    'Moab': 'Моав',
    'Asia': 'Асия',
  };
}

class _Row extends ConsumerWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, color: c.muted)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, color: c.text)),
          ),
        ],
      ),
    );
  }
}

/// Список мест Писания. Показываем частями: у Моисея их под тысячу, и
/// отрисовывать всё сразу незачем.
class _References extends ConsumerStatefulWidget {
  const _References({
    required this.db,
    required this.translationId,
    required this.vkeys,
  });

  final BibleDatabase db;
  final String translationId;
  final List<int> vkeys;

  @override
  ConsumerState<_References> createState() => _ReferencesState();
}

class _ReferencesState extends ConsumerState<_References> {
  int _shown = 20;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final c = s.colors;
    final slice = widget.vkeys.take(_shown).toList();
    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final k in slice)
          () {
            final v = widget.db.verseByKey(widget.translationId, k);
            if (v == null) return const SizedBox.shrink();
            // Ссылка ведёт в текст: список, из которого нельзя перейти к
            // стиху, — это справка, а не навигация.
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _goToVerse(context, ref,
                  bookId: v.bookId, chapter: v.chapter, vkey: k),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                            () {
                              final b = books
                                  .where((x) => x.id == v.bookId)
                                  .firstOrNull;
                              return b == null
                                  ? v.reference
                                  : '${bookLabel(b)} ${v.chapter}:${v.verse}';
                            }(),
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: c.accent)),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded,
                            size: 15, color: c.faint),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(v.text,
                        style: TextStyle(
                            fontFamily: s.fontFamily,
                            fontSize: s.fontSize * 0.88,
                            height: 1.5,
                            color: c.text)),
                  ],
                ),
              ),
            );
          }(),
        if (_shown < widget.vkeys.length)
          TextButton(
            onPressed: () => setState(() => _shown += 40),
            child: Text('Показать ещё',
                style: TextStyle(fontFamily: 'Inter', color: c.accent)),
          ),
      ],
    );
  }
}
