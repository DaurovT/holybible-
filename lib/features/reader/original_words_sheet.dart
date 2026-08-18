/// Слова оригинала для выбранного отрывка.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design.dart';

import '../../data/models.dart';
import '../../data/strongs_database.dart';
import '../../state/providers.dart';

Future<void> showOriginalWordsSheet(
  BuildContext context, {
  required List<Verse> verses,
  required String reference,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _OriginalWordsSheet(verses: verses, reference: reference),
  );
}

/// Слово оригинала и все места, где оно всплыло в английском стихе.
typedef _Entry = ({StrongWord word, List<String> surfaces});

/// Английский стих с разметкой Стронга и его слова.
typedef _Row = ({Verse verse, List<_Entry> words});

class _OriginalWordsSheet extends ConsumerWidget {
  const _OriginalWordsSheet({required this.verses, required this.reference});

  final List<Verse> verses;
  final String reference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = s.colors;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ref.watch(_wordsProvider(verses)).when(
            loading: () => const Center(
                child: Padding(
              padding: EdgeInsets.all(60),
              child: CircularProgressIndicator(strokeWidth: 2),
            )),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text('Словарь не открылся: $e',
                    style:
                        TextStyle(fontFamily: 'Inter', color: c.muted)),
              ),
            ),
            data: (rows) => ListView(
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
                Text('Слова оригинала',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
                const SizedBox(height: 6),
                Text(
                  'Номера при словах размечены только в английских переводах — '
                  'в Синодальном такой разметки нет. Ниже слова из World '
                  'English Bible и статьи словаря Стронга.',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      height: 1.45,
                      color: c.faint),
                ),
                const SizedBox(height: 18),
                if (rows.isEmpty)
                  Text('Для этого отрывка разметки нет.',
                      style: TextStyle(
                          fontFamily: 'Inter', fontSize: 14, color: c.faint)),
                for (final row in rows) ...[
                  Text(row.verse.text,
                      style: TextStyle(
                          fontFamily: s.fontFamily,
                          fontSize: s.fontSize * 0.88,
                          height: 1.5,
                          color: c.muted)),
                  const SizedBox(height: 14),
                  for (final w in row.words) _WordCard(entry: w),
                  const SizedBox(height: 18),
                ],
                Text(
                  'Словарь: Strong’s Concordance (1890/1894), оцифровка '
                  'openscriptures, CC BY-SA.',
                  style: TextStyle(
                      fontFamily: 'Inter', fontSize: 11, color: c.faint),
                ),
              ],
            ),
          ),
    );
  }
}

/// Слова оригинала для отрывка. Английские стихи берём по единому ключу, а
/// словарь открываем лениво — до первого обращения его файл не трогается.
final _wordsProvider =
    FutureProvider.family<List<_Row>, List<Verse>>((ref, verses) async {
  if (verses.isEmpty) return const [];
  final bible = await ref.watch(bibleDbProvider.future);
  final english =
      bible.versesByKeys('web', [for (final v in verses) v.vkey]);
  if (english.isEmpty) return const [];

  final strongs = await ref.watch(strongsDbProvider.future);
  final out = <_Row>[];
  for (final v in verses) {
    final e = english[v.vkey];
    if (e == null) continue;
    final words = strongs.wordsFor(e.id);
    if (words.isEmpty) continue;

    // Разметка WEB бывает грубой: одно слово оригинала вешают и на предлог, и
    // на артикль («In» и «the» — оба ἐν). Три одинаковые карточки подряд
    // читать невозможно, поэтому собираем их в одну.
    final grouped = <String, _Entry>{};
    for (final w in words) {
      final surface = w.start < w.end && w.end <= e.text.length
          ? e.text.substring(w.start, w.end)
          : '';
      final entry =
          grouped.putIfAbsent(w.code, () => (word: w, surfaces: <String>[]));
      if (surface.isNotEmpty && !entry.surfaces.contains(surface)) {
        entry.surfaces.add(surface);
      }
    }
    out.add((verse: e, words: grouped.values.toList()));
  }
  return out;
});

class _WordCard extends ConsumerWidget {
  const _WordCard({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final word = entry.word;
    final surface = entry.surfaces.join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (word.lemma != null)
                Flexible(
                  child: Text(word.lemma!,
                      style: TextStyle(
                          fontFamily: 'Literata',
                          fontSize: 20,
                          height: 1.3,
                          color: c.text)),
                ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: c.background,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(word.code,
                    style: TextStyle(
                        fontFamily: 'Inter', fontSize: 11, color: c.muted)),
              ),
            ],
          ),
          if (word.translit != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                word.pron == null
                    ? word.translit!
                    : '${word.translit!} · ${word.pron!}',
                style: TextStyle(
                    fontFamily: 'Inter', fontSize: 12, color: c.faint),
              ),
            ),
          if (surface.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('в тексте: «$surface»',
                style: TextStyle(
                    fontFamily: 'Inter', fontSize: 12, color: c.muted)),
          ],
          if (word.definition != null) ...[
            const SizedBox(height: 6),
            Text(word.definition!,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    height: 1.45,
                    color: c.text)),
          ],
        ],
      ),
    );
  }
}
