/// Карточка сущности: короткая — по тапу в тексте, полная — по «Подробнее».
///
/// Тап по имени не должен уводить из чтения. Поэтому первым уровнем идёт
/// низкая шторка, которую можно смахнуть и продолжить читать, и лишь по
/// явному запросу открывается полная страница.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entity_repository.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import 'entity_page.dart';

void showEntitySheet(BuildContext context, String entityId) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _EntitySheet(entityId: entityId),
  );
}

class _EntitySheet extends ConsumerWidget {
  const _EntitySheet({required this.entityId});
  final String entityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final db = ref.watch(bibleDbProvider).valueOrNull;
    final e = db?.entity(entityId);

    if (e == null) {
      return const SizedBox(height: 180, child: Center(child: Text('—')));
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                      color: c.divider,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KindBadge(kind: e.kind),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.displayName,
                          style: TextStyle(
                            fontFamily: 'Literata',
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: c.text,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            e.factsLine,
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                color: c.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Только русский текст: описание из TIPNR английское, и в
              // панели, которая выскакивает прямо из русского стиха, оно
              // читается как сбой. Где статьи нет, панель остаётся короткой —
              // имя, факты и переход в карточку.
              if (e.ruLead != null) ...[
                const SizedBox(height: 16),
                Text(
                  e.ruLead!,
                  style: TextStyle(
                      fontFamily: 'Literata',
                      fontSize: 16,
                      height: 1.55,
                      color: c.text),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  if (e.refCount > 0)
                    _Stat(
                        label: 'упоминаний',
                        value: '${e.refCount}'),
                  if (e.modernName != null)
                    _Stat(label: 'сегодня', value: e.modernName!),
                  if (e.tribe != null)
                    _Stat(label: 'колено', value: _tribeRu(e.tribe!)),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent.withValues(alpha: 0.12),
                    foregroundColor: c.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => EntityPage(entityId: entityId)));
                  },
                  child: const Text('Узнать подробнее',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _tribeRu(String s) =>
    s.replaceFirst('Tribe of ', '').trim();

class _KindBadge extends ConsumerWidget {
  const _KindBadge({required this.kind});
  final EntityKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final (icon, _) = switch (kind) {
      EntityKind.person => (Icons.person_outline_rounded, 'человек'),
      EntityKind.place => (Icons.place_outlined, 'место'),
      EntityKind.other => (Icons.category_outlined, 'понятие'),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 21, color: c.accent),
    );
  }
}

class _Stat extends ConsumerWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.text)),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: 11, color: c.faint)),
        ],
      ),
    );
  }
}
