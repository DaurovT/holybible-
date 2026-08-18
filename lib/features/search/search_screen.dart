/// Поиск по тексту Писания с учётом русской морфологии.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/bible_reference.dart';
import '../../core/theme/design.dart';
import '../../data/models.dart';
import '../../data/search_repository.dart';
import '../../state/providers.dart';
import '../reader/book_picker.dart';

final _queryProvider = StateProvider<String>((ref) => '');

/// Книга, которой ограничен поиск. null — искать по всему Писанию.
final _bookFilterProvider = StateProvider<String?>((ref) => null);

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final c = s.colors;
    final db = ref.watch(bibleDbProvider).valueOrNull;
    final query = ref.watch(_queryProvider);
    final translation = ref.watch(translationProvider);

    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
    final bookFilter = ref.watch(_bookFilterProvider);
    final result = (db == null || query.trim().length < 2)
        ? null
        : db.search(query,
            translationId: translation, bookId: bookFilter, limit: 80);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: TextStyle(fontFamily: 'Inter', fontSize: 16, color: c.text),
          decoration: InputDecoration(
            hintText: 'Найти в Библии',
            hintStyle: TextStyle(color: c.faint, fontFamily: 'Inter'),
            border: InputBorder.none,
          ),
          onChanged: (v) => ref.read(_queryProvider.notifier).state = v,
        ),
        actions: [
          if (query.isNotEmpty)
            IconButton(
              icon: Icon(Icons.close_rounded, size: 20, color: c.muted),
              onPressed: () {
                _controller.clear();
                ref.read(_queryProvider.notifier).state = '';
              },
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ScopeBar(),
          Expanded(
            child: result == null
          ? _Hint(colors: c)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Insets.screen, 6, Insets.screen, 10),
                  child: Text(
                    _plural(result.total),
                    style: TextStyle(
                        fontFamily: 'Inter', fontSize: 13, color: c.muted),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: result.hits.length,
                    itemBuilder: (ctx, i) {
                      final h = result.hits[i];
                      final book =
                          books.where((b) => b.id == h.bookId).firstOrNull;
                      final reference = book == null
                          ? h.reference
                          : '${bookLabel(book)} ${h.chapter}:${h.verse}';
                      return InkWell(
                        onTap: () {
                          // Просьба о переходе, а не просто запись позиции:
                          // лента чтения уже собрана вокруг своей опоры и от
                          // смены позиции никуда не поедет.
                          openInReader(ref,
                              bookId: h.bookId,
                              chapter: h.chapter,
                              vkey: h.vkey);
                          Navigator.pop(context);
                        },
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(
                                  Insets.screen, 12, Insets.screen, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(reference,
                                  style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: c.accent)),
                              const SizedBox(height: 4),
                              Text.rich(
                                _highlighted(h.text, h.highlights, s),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Подсвечивает найденные слова прямо в стихе.
  TextSpan _highlighted(String text, List<(int, int)> spans, dynamic s) {
    final c = ref.read(settingsProvider).colors;
    final base = TextStyle(
        fontFamily: s.fontFamily,
        fontSize: s.fontSize * 0.9,
        height: 1.5,
        color: c.text);
    if (spans.isEmpty) return TextSpan(text: text, style: base);

    final children = <TextSpan>[];
    var cursor = 0;
    for (final (a, b) in spans) {
      if (a < cursor) continue;
      if (a > cursor) {
        children.add(TextSpan(text: text.substring(cursor, a)));
      }
      children.add(TextSpan(
        text: text.substring(a, b),
        style: TextStyle(
            backgroundColor: c.highlight, fontWeight: FontWeight.w600),
      ));
      cursor = b;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }
    return TextSpan(style: base, children: children);
  }

  static String _plural(int n) {
    final mod10 = n % 10, mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return '$n совпадение';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return '$n совпадения';
    }
    return '$n совпадений';
  }
}

/// Где искать: по всему Писанию или внутри одной книги.
///
/// Поиск по книге умел искать с самого начала — в запросе есть фильтр, — но
/// попросить об этом было нечем.
class _ScopeBar extends ConsumerWidget {
  const _ScopeBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(_bookFilterProvider);
    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
    final book =
        filter == null ? null : books.where((b) => b.id == filter).firstOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.screen, 8, Insets.screen, 2),
      child: Row(
        children: [
          AppChip(
            label: 'Везде',
            selected: filter == null,
            onTap: () => ref.read(_bookFilterProvider.notifier).state = null,
          ),
          const SizedBox(width: 8),
          AppChip(
            label: book == null ? 'В книге…' : 'Только ${bookLabel(book)}',
            selected: filter != null,
            icon: Icons.expand_more_rounded,
            onTap: () async {
              final picked =
                  await showBookPicker(context, ref, booksOnly: true);
              if (picked != null) {
                ref.read(_bookFilterProvider.notifier).state = picked.bookId;
              }
            },
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.colors});
  final dynamic colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          'Поиск понимает словоформы: «любовь» найдёт и «любви», '
          '«день» — и «дня».',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              height: 1.5,
              color: colors.faint),
        ),
      ),
    );
  }
}
