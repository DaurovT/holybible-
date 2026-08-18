/// Параллельные места к выбранному отрывку.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design.dart';

import '../../core/text/bible_reference.dart';
import '../../data/cross_ref_repository.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

Future<void> showCrossRefsSheet(
  BuildContext context, {
  required List<Verse> verses,
  required String reference,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CrossRefsSheet(verses: verses, reference: reference),
  );
}

class _CrossRefsSheet extends ConsumerWidget {
  const _CrossRefsSheet({required this.verses, required this.reference});

  final List<Verse> verses;
  final String reference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = s.colors;
    final db = ref.watch(bibleDbProvider).valueOrNull;
    final translation = ref.watch(translationProvider);
    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];

    final refs = db == null
        ? const <CrossReference>[]
        : db.crossRefs(translation, [for (final v in verses) v.vkey]);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.94,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(
            Insets.screen, 18, Insets.screen, 40),
        children: [
          Text(reference,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  letterSpacing: 0.4,
                  color: c.muted)),
          const SizedBox(height: 6),
          Text('Параллельные места',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.text)),
          const SizedBox(height: 14),
          if (refs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Text(
                'Для этого отрывка параллельных мест не отмечено.',
                style: TextStyle(
                    fontFamily: 'Inter', fontSize: 14, color: c.faint),
              ),
            ),
          for (final r in refs)
            () {
              final book = books.where((b) => b.id == r.bookId).firstOrNull;
              final label = book == null ? r.bookId : bookLabel(book);
              final where = r.isRange
                  ? '$label ${r.chapter}:${r.verse}–${r.verseEnd}'
                  : '$label ${r.chapter}:${r.verse}';

              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  openInReader(ref,
                      bookId: r.bookId, chapter: r.chapter, vkey: r.vkey);
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(where,
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
                      Text(r.text,
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
          if (refs.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Связи: OpenBible.info (CC BY), по «Сокровищнице библейских '
              'знаний». Порядок — по тому, насколько связь подтверждена '
              'читателями.',
              style:
                  TextStyle(fontFamily: 'Inter', fontSize: 11, color: c.faint),
            ),
          ],
        ],
      ),
    );
  }
}
