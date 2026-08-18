/// Раздел «Моё»: закладки, выделения, заметки.
///
/// Всё, что человек отметил сам. Списки строятся из user.db, а текст стихов
/// подтягивается одним запросом на раздел — в текущем переводе, а не в том, в
/// котором отметку поставили: перечитывать хочется то, что читаешь сейчас.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/bible_reference.dart';
import '../../core/theme/design.dart';
import '../../core/theme/reading_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../state/user_data.dart';
import 'note_sheet.dart';

enum _Section {
  bookmarks('Закладки'),
  highlights('Выделения'),
  notes('Заметки');

  const _Section(this.title);
  final String title;
}

final _sectionProvider = StateProvider<_Section>((ref) => _Section.bookmarks);

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final section = ref.watch(_sectionProvider);
    final data = ref.watch(userDataProvider);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Моё')),
      body: Column(
        children: [
          // Лента прокручивается: счётчики растут, и три кнопки со временем
          // перестают помещаться в строку.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
                Insets.screen, 2, Insets.screen, 14),
            child: Row(
              children: [
                for (final s in _Section.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppChip(
                      label: s.title,
                      count: switch (s) {
                        _Section.bookmarks => data.bookmarks.length,
                        _Section.highlights => data.highlights.length,
                        _Section.notes => data.notes.length,
                      },
                      selected: s == section,
                      onTap: () =>
                          ref.read(_sectionProvider.notifier).state = s,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: !data.ready
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : switch (section) {
                    _Section.bookmarks => _BookmarkList(data: data),
                    _Section.highlights => _HighlightList(data: data),
                    _Section.notes => _NoteList(data: data),
                  },
          ),
        ],
      ),
    );
  }
}

/// Тексты стихов по их ключам в текущем переводе.
Map<int, Verse> _versesFor(WidgetRef ref, List<int> vkeys) {
  final db = ref.watch(bibleDbProvider).valueOrNull;
  if (db == null || vkeys.isEmpty) return const {};
  return db.versesByKeys(ref.watch(translationProvider), vkeys);
}

/// Ссылка вида «Иоанна 3:16» в названиях книг текущего перевода.
String _reference(WidgetRef ref, String bookId, int chapter, int verse,
    [int? verseEnd]) {
  final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
  final name = books
      .where((b) => b.id == bookId)
      .map(bookLabel)
      .followedBy([bookId]).first;
  final tail =
      (verseEnd != null && verseEnd != verse) ? '$verse–$verseEnd' : '$verse';
  return '$name $chapter:$tail';
}

class _BookmarkList extends ConsumerWidget {
  const _BookmarkList({required this.data});
  final UserData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.bookmarks.isEmpty) {
      return const _Empty(
        icon: Icons.bookmark_border_rounded,
        text: 'Закладок пока нет.\nВыберите стих в тексте и нажмите закладку — '
            'сюда попадут места, к которым хочется вернуться.',
      );
    }
    final texts =
        _versesFor(ref, [for (final b in data.bookmarks) b.vkey]);

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: data.bookmarks.length,
      separatorBuilder: (_, _) => const AppDivider(),
      itemBuilder: (ctx, i) {
        final b = data.bookmarks[i];
        return _Row(
          reference: _reference(ref, b.bookId, b.chapter, b.verse),
          text: texts[b.vkey]?.text ?? '',
          onTap: () => openInReader(ref,
              bookId: b.bookId, chapter: b.chapter, vkey: b.vkey),
          onDelete: () =>
              ref.read(userDataProvider.notifier).removeBookmark(b.vkey),
          dismissKey: 'bookmark-${b.id}',
        );
      },
    );
  }
}

class _HighlightList extends ConsumerWidget {
  const _HighlightList({required this.data});
  final UserData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.highlights.isEmpty) {
      return const _Empty(
        icon: Icons.brush_outlined,
        text: 'Выделений пока нет.\nВыберите стих и коснитесь цвета — '
            'все раскрашенные места соберутся здесь.',
      );
    }
    final c = ref.watch(settingsProvider).colors;
    final texts =
        _versesFor(ref, [for (final h in data.highlights) h.vkey]);

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: data.highlights.length,
      separatorBuilder: (_, _) => const AppDivider(),
      itemBuilder: (ctx, i) {
        final h = data.highlights[i];
        return _Row(
          reference: _reference(ref, h.bookId, h.chapter, h.verse),
          text: texts[h.vkey]?.text ?? '',
          textBackground: h.tint.on(c),
          onTap: () => openInReader(ref,
              bookId: h.bookId, chapter: h.chapter, vkey: h.vkey),
          onDelete: () =>
              ref.read(userDataProvider.notifier).removeHighlight(h.vkey),
          dismissKey: 'highlight-${h.id}',
        );
      },
    );
  }
}

class _NoteList extends ConsumerWidget {
  const _NoteList({required this.data});
  final UserData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.notes.isEmpty) {
      return const _Empty(
        icon: Icons.edit_note_rounded,
        text: 'Заметок пока нет.\nВыберите отрывок и напишите, что вы о нём '
            'думаете — заметка останется у стиха и будет видна при чтении.',
      );
    }
    final c = ref.watch(settingsProvider).colors;
    final s = ref.watch(settingsProvider);
    final texts = _versesFor(ref, [for (final n in data.notes) n.vkey]);

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: data.notes.length,
      separatorBuilder: (_, _) => const AppDivider(),
      itemBuilder: (ctx, i) {
        final n = data.notes[i];
        final quote = texts[n.vkey]?.text ?? '';
        final reference =
            _reference(ref, n.bookId, n.chapter, n.verse, n.verseEnd);

        return Dismissible(
          key: ValueKey('note-${n.id}'),
          direction: DismissDirection.endToStart,
          background: _DeleteBackground(colors: c),
          onDismissed: (_) =>
              ref.read(userDataProvider.notifier).removeNote(n.id),
          child: InkWell(
            onTap: () => showNoteSheet(
              context,
              verses: [
                if (texts[n.vkey] != null) texts[n.vkey]!,
              ],
              reference: reference,
              existing: n,
            ),
            onLongPress: () => openInReader(ref,
                bookId: n.bookId, chapter: n.chapter, vkey: n.vkey),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  Insets.screen, 14, Insets.screen, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reference,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.accent)),
                  const SizedBox(height: 6),
                  Text(n.body,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          height: 1.5,
                          color: c.text)),
                  if (quote.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(quote,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: s.fontFamily,
                            fontSize: 13,
                            height: 1.5,
                            fontStyle: FontStyle.italic,
                            color: c.faint)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({
    required this.reference,
    required this.text,
    required this.onTap,
    required this.onDelete,
    required this.dismissKey,
    this.textBackground,
  });

  final String reference;
  final String text;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final String dismissKey;
  final Color? textBackground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = s.colors;

    return Dismissible(
      key: ValueKey(dismissKey),
      direction: DismissDirection.endToStart,
      background: _DeleteBackground(colors: c),
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              Insets.screen, 14, Insets.screen, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reference,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.accent)),
              if (text.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: s.fontFamily,
                      fontSize: 15,
                      height: 1.5,
                      color: c.text,
                      backgroundColor: textBackground,
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground({required this.colors});
  final ReadingColors colors;

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        color: colors.wordsOfJesus.withValues(alpha: 0.14),
        child: Icon(Icons.delete_outline_rounded,
            size: 22, color: colors.wordsOfJesus),
      );
}


/// Пустой раздел: объясняет, как здесь что-то появится.
class _Empty extends ConsumerWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 0, 40, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: c.faint),
            const SizedBox(height: 14),
            Text(text, textAlign: TextAlign.center, style: AppText.body(c)),
          ],
        ),
      ),
    );
  }
}
