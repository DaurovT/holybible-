/// Раздел «Исследовать»: люди, места, понятия.
///
/// Заходить сюда необязательно — всё то же открывается тапом прямо в тексте.
/// Раздел нужен тем, кто пришёл с вопросом «а кто такой Никодим», а не с
/// закладкой на главе.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design.dart';

import '../../data/article_repository.dart';
import '../../data/entity_repository.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../entity/article_page.dart';
import '../entity/entity_page.dart';

final _filterProvider = StateProvider<EntityKind?>((ref) => EntityKind.person);
final _testamentProvider = StateProvider<String?>((ref) => null);
final _queryProvider = StateProvider<String>((ref) => '');

/// Показывать глоссарий вместо людей, мест и понятий.
final _glossaryProvider = StateProvider<bool>((ref) => false);

class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final db = ref.watch(bibleDbProvider).valueOrNull;
    final kind = ref.watch(_filterProvider);
    final testament = ref.watch(_testamentProvider);
    final query = ref.watch(_queryProvider);

    final glossary = ref.watch(_glossaryProvider);
    final articles = (db == null || !glossary)
        ? const <RussianArticle>[]
        : db.browseGlossary(query: query.trim(), limit: 200);
    final items = db == null || glossary
        ? const <BibleEntity>[]
        : query.trim().length >= 2
            ? db.searchEntities(query)
            : db.browse(kind: kind, testament: testament, limit: 300);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Исследовать')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
            child: TextField(
              onChanged: (v) => ref.read(_queryProvider.notifier).state = v,
              style:
                  TextStyle(fontFamily: 'Inter', fontSize: 15, color: c.text),
              decoration: InputDecoration(
                hintText: 'Имя, место или понятие',
                hintStyle: TextStyle(color: c.faint, fontFamily: 'Inter'),
                prefixIcon:
                    Icon(Icons.search_rounded, size: 20, color: c.faint),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
          if (query.trim().length < 2) ...[
            // Два ряда, а не один: тип и завет — разные вопросы, и в общей
            // ленте завет уезжал за правый край, где его никто не искал.
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  AppChipSpaced(
                    label: 'Люди',
                    selected: kind == EntityKind.person && !glossary,
                    onTap: () {
                      ref.read(_glossaryProvider.notifier).state = false;
                      ref.read(_filterProvider.notifier).state =
                          EntityKind.person;
                    },
                  ),
                  AppChipSpaced(
                    label: 'Места',
                    selected: kind == EntityKind.place && !glossary,
                    onTap: () {
                      ref.read(_glossaryProvider.notifier).state = false;
                      ref.read(_filterProvider.notifier).state =
                          EntityKind.place;
                    },
                  ),
                  AppChipSpaced(
                    label: 'Понятия',
                    selected: kind == EntityKind.other && !glossary,
                    onTap: () {
                      ref.read(_glossaryProvider.notifier).state = false;
                      ref.read(_filterProvider.notifier).state =
                          EntityKind.other;
                    },
                  ),
                  AppChipSpaced(
                    label: 'Словарь',
                    selected: glossary,
                    onTap: () =>
                        ref.read(_glossaryProvider.notifier).state = true,
                  ),
                ],
              ),
            ),
            // К словарю завет неприменим: статьи энциклопедии не привязаны к
            // месту в Писании.
            if (!glossary)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 2),
                child: Row(
                  children: [
                    for (final (value, label) in const [
                      (null, 'Весь текст'),
                      ('OT', 'Ветхий Завет'),
                      ('NT', 'Новый Завет'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _TestamentTab(
                          label: label,
                          selected: testament == value,
                          onTap: () => ref
                              .read(_testamentProvider.notifier)
                              .state = value,
                        ),
                      ),
                  ],
                ),
              ),
          ],
          if (glossary)
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
                itemCount: articles.length,
                separatorBuilder: (_, _) => const AppDivider(),
                itemBuilder: (ctx, i) {
                  final a = articles[i];
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                    title: Text(a.title,
                        style: TextStyle(
                            fontFamily: 'Literata',
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: c.text)),
                    subtitle: Text(a.lead,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: c.muted)),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ArticlePage(articleId: a.id))),
                  );
                },
              ),
            )
          else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
              itemCount: items.length,
              separatorBuilder: (_, _) => const AppDivider(),
              itemBuilder: (ctx, i) {
                final e = items[i];
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                  title: Text(e.displayName,
                      style: TextStyle(
                          fontFamily: 'Literata',
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: c.text)),
                  // Подпись только по-русски: у половины сущностей описание
                  // из TIPNR так и осталось английским, и список выходил
                  // наполовину на чужом языке. Где русской статьи нет, стоят
                  // факты из наших же данных.
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      e.ruLead ?? e.factsLine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          height: 1.4,
                          color: e.ruLead == null ? c.faint : c.muted),
                    ),
                  ),
                  trailing: Text('${e.refCount}',
                      style: TextStyle(
                          fontFamily: 'Inter', fontSize: 12, color: c.faint)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => EntityPage(entityId: e.id))),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Завет — фильтр второго уровня, поэтому он набирается текстом, а не чипом:
/// два ряда одинаковых кнопок читались бы как один список из шести.
class _TestamentTab extends ConsumerWidget {
  const _TestamentTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? c.accent : c.faint,
          ),
        ),
      ),
    );
  }
}

/// Фильтр в горизонтальной ленте: общая кнопка-переключатель с отбивкой.
class AppChipSpaced extends StatelessWidget {
  const AppChipSpaced({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: AppChip(label: label, selected: selected, onTap: onTap),
      );
}
