/// Панель действий над выделенным отрывком.
///
/// Появляется, когда выбран хотя бы один стих. Набор действий взят из
/// продуктовой задумки: объяснить, контекст, почему это важно, сравнить
/// переводы, задать вопрос.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/text/bible_reference.dart';
import '../../core/theme/design.dart';
import '../../core/theme/reading_theme.dart';
import '../../data/entity_repository.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../state/user_data.dart';
import '../ai/explain_sheet.dart';
import '../entity/entity_sheet.dart';
import '../library/note_sheet.dart';
import 'cross_refs_sheet.dart';
import 'original_words_sheet.dart';

class PassageActionsBar extends ConsumerWidget {
  const PassageActionsBar({
    super.key,
    required this.verses,
    required this.book,
    required this.onClose,
  });

  final List<Verse> verses;
  final Book? book;
  final VoidCallback onClose;

  /// Человекочитаемая ссылка: «Иоанна 3:16» или «Иоанна 3:16–18».
  /// Идущие подряд стихи схлопываются в диапазон — так пишут цитаты.
  String get reference {
    if (verses.isEmpty || book == null) return '';
    final nums = verses.map((v) => v.number).toList()..sort();
    final ch = verses.first.chapter;
    final ranges = <String>[];
    var start = nums.first, prev = nums.first;
    for (final n in nums.skip(1)) {
      if (n == prev + 1) {
        prev = n;
        continue;
      }
      ranges.add(start == prev ? '$start' : '$start–$prev');
      start = prev = n;
    }
    ranges.add(start == prev ? '$start' : '$start–$prev');
    return '${bookLabel(book!)} $ch:${ranges.join(',')}';
  }

  String get plainText => verses.map((v) => v.text).join(' ');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.divider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 4),
              child: Row(
                children: [
                  Text(
                    reference,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: c.muted),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            _PersonalRow(
                verses: verses, reference: reference, onClose: onClose),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  _Action(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Объяснить',
                    primary: true,
                    onTap: () => _explain(context, ExplainMode.explain),
                  ),
                  _Action(
                    icon: Icons.hub_outlined,
                    label: 'Параллельные места',
                    onTap: () => showCrossRefsSheet(context,
                        verses: verses, reference: reference),
                  ),
                  _Action(
                    icon: Icons.history_edu_rounded,
                    label: 'Контекст',
                    onTap: () => _explain(context, ExplainMode.context),
                  ),
                  _Action(
                    icon: Icons.lightbulb_outline_rounded,
                    label: 'Почему это важно',
                    onTap: () => _explain(context, ExplainMode.whyMatters),
                  ),
                  _Action(
                    icon: Icons.translate_rounded,
                    label: 'Слова оригинала',
                    onTap: () => showOriginalWordsSheet(context,
                        verses: verses, reference: reference),
                  ),
                  _Action(
                    icon: Icons.compare_arrows_rounded,
                    label: 'Сравнить переводы',
                    onTap: () => _compare(context, ref),
                  ),
                  _Action(
                    icon: Icons.help_outline_rounded,
                    label: 'Задать вопрос',
                    onTap: () => _explain(context, ExplainMode.ask),
                  ),
                  _Action(
                    icon: Icons.copy_rounded,
                    label: 'Копировать',
                    onTap: () {
                      Clipboard.setData(
                          ClipboardData(text: '$plainText\n\n$reference'));
                      onClose();
                    },
                  ),
                  _Action(
                    icon: Icons.ios_share_rounded,
                    label: 'Поделиться',
                    onTap: () => SharePlus.instance.share(
                        ShareParams(text: '$plainText\n\n$reference')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _explain(BuildContext context, ExplainMode mode) {
    showExplainSheet(
      context,
      mode: mode,
      reference: reference,
      text: plainText,
      verses: verses,
    );
  }

  /// Показывает тот же отрывок в остальных переводах.
  Future<void> _compare(BuildContext context, WidgetRef ref) async {
    final db = await ref.read(bibleDbProvider.future);
    final all = db.translations();
    final current = ref.read(translationProvider);
    final keys = verses.map((v) => v.vkey).toList();
    final rows = <(String, String)>[];
    for (final t in all) {
      final map = db.versesByKeys(t.id, keys);
      final text =
          keys.map((k) => map[k]?.text ?? '').where((s) => s.isNotEmpty).join(' ');
      if (text.isNotEmpty) rows.add((t.name, text));
    }
    if (!context.mounted) return;

    final c = ref.read(settingsProvider).colors;
    final s = ref.read(settingsProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 40),
          children: [
            Text(reference,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    letterSpacing: 0.4,
                    color: c.muted)),
            const SizedBox(height: 18),
            for (final (name, text) in rows) ...[
              Row(
                children: [
                  Text(name,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.accent)),
                  if (all.any((t) => t.name == name && t.id == current)) ...[
                    const SizedBox(width: 6),
                    Text('· сейчас',
                        style: TextStyle(
                            fontFamily: 'Inter', fontSize: 11, color: c.faint)),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(text,
                  style: TextStyle(
                      fontFamily: s.fontFamily,
                      fontSize: s.fontSize * 0.92,
                      height: 1.55,
                      color: c.text)),
              const SizedBox(height: 22),
            ],
          ],
        ),
      ),
    );
  }
}

/// Личные действия над отрывком: краска, закладка, заметка.
///
/// Цвета стоят прямо в панели, а не за кнопкой «выделить»: выделение — самое
/// частое действие в читалке, и прятать его за второй тап незачем.
class _PersonalRow extends ConsumerWidget {
  const _PersonalRow({
    required this.verses,
    required this.reference,
    required this.onClose,
  });

  final List<Verse> verses;
  final String reference;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final data = ref.watch(userDataProvider);
    if (verses.isEmpty) return const SizedBox.shrink();

    final current = data.tintOf(verses.first.vkey);
    final allSame =
        verses.every((v) => data.tintOf(v.vkey) == current);
    final bookmarked = data.isBookmarked(verses.first.vkey);
    final notes = data.notesFor(verses.first.vkey);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 12, 10),
      child: Row(
        children: [
          for (final tint in HighlightTint.values)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () =>
                    ref.read(userDataProvider.notifier).setHighlight(verses, tint),
                child: Container(
                  width: 27,
                  height: 27,
                  decoration: BoxDecoration(
                    color: tint.swatch(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: allSame && current == tint ? c.text : c.divider,
                      width: allSame && current == tint ? 2 : 1,
                    ),
                  ),
                ),
              ),
            ),
          if (current != null)
            IconButton(
              tooltip: 'Убрать выделение',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.format_color_reset_rounded,
                  size: 19, color: c.muted),
              onPressed: () {
                final notifier = ref.read(userDataProvider.notifier);
                for (final v in verses) {
                  notifier.removeHighlight(v.vkey);
                }
              },
            ),
          const Spacer(),
          IconButton(
            tooltip: bookmarked ? 'Убрать закладку' : 'В закладки',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              bookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              size: 21,
              color: bookmarked ? c.accent : c.muted,
            ),
            onPressed: () => ref
                .read(userDataProvider.notifier)
                .toggleBookmark(verses.first),
          ),
          IconButton(
            tooltip: notes.isEmpty ? 'Заметка' : 'Открыть заметку',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              notes.isEmpty
                  ? Icons.edit_note_rounded
                  : Icons.sticky_note_2_rounded,
              size: 22,
              color: notes.isEmpty ? c.muted : c.accent,
            ),
            onPressed: () {
              showNoteSheet(
                context,
                verses: verses,
                reference: reference,
                existing: notes.isEmpty ? null : notes.first,
              );
              onClose();
            },
          ),
        ],
      ),
    );
  }
}

class _Action extends ConsumerWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: primary ? c.accent.withValues(alpha: 0.12) : c.background,
        borderRadius: BorderRadius.circular(Radii.chip),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.chip),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 17, color: primary ? c.accent : c.muted),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
                    color: primary ? c.accent : c.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Сущности, встреченные в отрывке. Используется и панелью действий, и
/// разбором «о ком тут речь».
Future<List<BibleEntity>> entitiesInVerses(
    WidgetRef ref, List<Verse> verses) async {
  final db = await ref.read(bibleDbProvider.future);
  final ids = <String>{
    for (final v in verses)
      for (final m in v.mentions)
        if (m.confidence >= 0.2) m.entityId
  };
  final list = db.entities(ids.toList());
  list.sort((a, b) => b.refCount.compareTo(a.refCount));
  return list;
}

/// Открывает карточку сущности из любого места приложения.
void openEntity(BuildContext context, String id) => showEntitySheet(context, id);
