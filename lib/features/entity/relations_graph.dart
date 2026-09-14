/// Связи персонажа: родители, супруги, братья, дети.
///
/// Здесь был свободный граф с перетаскиванием и масштабом. На бумаге идея
/// хорошая, на телефоне — нет: у Давида 41 связь, узлы разъезжались далеко за
/// рамку, и в окне оставалось пустое поле с одним именем в углу. Родословие
/// читается лучше группами: сразу видно, кто родители, а кто дети, и ничего не
/// нужно двигать пальцем.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import 'entity_sheet.dart';

class RelationsGraph extends ConsumerWidget {
  const RelationsGraph({
    super.key,
    required this.entity,
    required this.relations,
  });

  final BibleEntity entity;
  final List<EntityRelation> relations;

  static const _groups = <String, (String, IconData)>{
    'parent': ('Родители', Icons.north_rounded),
    'partner': ('Супруги', Icons.favorite_border_rounded),
    'sibling': ('Братья и сёстры', Icons.people_alt_outlined),
    'child': ('Дети', Icons.south_rounded),
    'founder': ('Основал', Icons.foundation_outlined),
    'inhabitant': ('Жители', Icons.groups_outlined),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;

    // Один и тот же человек попадает в связи дважды — из прямой записи и из
    // обратной. Плюс в первоисточнике встречаются тёзки с одинаковым именем и
    // записи без имени вовсе. В списке имён два одинаковых чипа неразличимы,
    // поэтому оставляем по одному на имя, а безымянные пропускаем. Пропускаем
    // и тех, у кого нет русского имени: английское «Nahash» среди русских
    // чипов у Давида читалось как поломка — так же, как в списках «Исследовать».
    final byRel = <String, List<EntityRelation>>{};
    final seen = <String>{};
    for (final r in relations) {
      final name = (r.otherName ?? '').trim();
      if (name.isEmpty || !RegExp('[А-Яа-яЁё]').hasMatch(name)) continue;
      if (!seen.add('${r.rel}:${name.toLowerCase()}')) continue;
      (byRel[r.rel] ??= []).add(r);
    }

    final order = _groups.keys.where(byRel.containsKey).toList();
    if (order.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final rel in order) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(_groups[rel]!.$2, size: 15, color: c.faint),
                const SizedBox(width: 6),
                Text(
                  _groups[rel]!.$1,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
                const SizedBox(width: 6),
                Text('${byRel[rel]!.length}',
                    style: AppText.caption(c).copyWith(fontSize: 12)),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in byRel[rel]!) _PersonChip(relation: r),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _PersonChip extends ConsumerWidget {
  const _PersonChip({required this.relation});

  final EntityRelation relation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final name = relation.otherName ?? relation.otherId;

    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(Radii.chip),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.chip),
        onTap: () => showEntitySheet(context, relation.otherId),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.chip),
            border: Border.all(color: c.divider),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            child: Text(
              name,
              style: TextStyle(
                fontFamily: 'Literata',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
