/// Переход к книге, главе и стиху.
///
/// Прежний вариант был плоским списком из 66 книг, где главы раскрывались
/// гармошкой прямо в нём: список ехал под пальцем, сетка Псалтири на 150 глав
/// выталкивала всё остальное, а до стиха дойти было нельзя вовсе. Здесь три
/// раздельных шага, недавние места и разбор ссылок вида «Ин 3:16» — тот, кто
/// знает ссылку, набирает её и не листает ничего.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/bible_reference.dart';
import '../../core/theme/design.dart';
import '../../core/theme/reading_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import 'book_icons.dart';

typedef PickedPlace = ({String bookId, int chapter, int? verse});

/// [booksOnly] — вернуть книгу и не спрашивать главу. Нужно поиску: там
/// выбирают область поиска, а не место в тексте.
Future<PickedPlace?> showBookPicker(BuildContext context, WidgetRef ref,
    {bool booksOnly = false}) {
  return showModalBottomSheet<PickedPlace>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ref.read(settingsProvider).colors.surface,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _BookPicker(booksOnly: booksOnly),
    ),
  );
}

enum _Pane { books, chapters, verses }

class _BookPicker extends ConsumerStatefulWidget {
  const _BookPicker({this.booksOnly = false});

  final bool booksOnly;

  @override
  ConsumerState<_BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends ConsumerState<_BookPicker> {
  final _controller = TextEditingController();

  _Pane _pane = _Pane.books;
  Book? _book;
  int _chapter = 1;
  bool _newTestament = false;
  bool _alphabetical = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Открываемся на том завете, где человек сейчас читает.
    final pos = ref.read(positionProvider);
    final books = ref.read(booksProvider).valueOrNull ?? const <Book>[];
    for (final b in books) {
      if (b.id == pos.bookId) _newTestament = b.isNewTestament;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pick(String bookId, int chapter, [int? verse]) =>
      Navigator.pop(context, (bookId: bookId, chapter: chapter, verse: verse));

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(settingsProvider).colors;

    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
              color: c.divider, borderRadius: BorderRadius.circular(2)),
        ),
        Expanded(
          child: switch (_pane) {
            _Pane.books => _booksPane(c),
            _Pane.chapters => _chaptersPane(c),
            _Pane.verses => _versesPane(c),
          },
        ),
      ],
    );
  }

  // ── Книги ───────────────────────────────────────────────────────────────

  Widget _booksPane(ReadingColors c) {
    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
    final matches = _query.trim().isEmpty
        ? const <ReferenceMatch>[]
        : parseReference(_query, books);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: TextField(
            controller: _controller,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.go,
            onSubmitted: (_) {
              if (matches.isNotEmpty) _open(matches.first);
            },
            style: TextStyle(fontFamily: 'Inter', fontSize: 15, color: c.text),
            decoration: InputDecoration(
              hintText: 'Книга или ссылка: Ин 3:16',
              hintStyle: TextStyle(color: c.faint, fontFamily: 'Inter'),
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: c.faint),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close_rounded, size: 18, color: c.faint),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: c.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ),
        if (_query.trim().isNotEmpty)
          Expanded(child: _matchList(matches, c))
        else
          Expanded(child: _browse(books, c)),
      ],
    );
  }

  /// Что нашлось по набранной ссылке.
  Widget _matchList(List<ReferenceMatch> matches, ReadingColors c) {
    if (matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'Ничего не нашлось.\nМожно набрать «Ин 3:16», «1 Кор 13» или '
            'просто «Бытие».',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Inter', fontSize: 14, height: 1.5, color: c.faint),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: matches.length > 12 ? 12 : matches.length,
      itemBuilder: (ctx, i) {
        final m = matches[i];
        final where = m.chapter == null
            ? null
            : m.verse == null
                ? 'глава ${m.chapter}'
                : 'глава ${m.chapter}, стих ${m.verse}';
        return ListTile(
          title: Text(m.book.name,
              style:
                  TextStyle(fontFamily: 'Inter', fontSize: 15, color: c.text)),
          subtitle: where == null
              ? null
              : Text(where,
                  style: TextStyle(
                      fontFamily: 'Inter', fontSize: 12, color: c.muted)),
          trailing: Text(bookLabel(m.book),
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.accent)),
          onTap: () => _open(m),
        );
      },
    );
  }

  /// Ссылка без главы открывает выбор главы, с главой — сразу текст.
  void _open(ReferenceMatch m) {
    if (widget.booksOnly) {
      _pick(m.book.id, m.chapter ?? 1);
      return;
    }
    if (m.chapter == null) {
      setState(() {
        _book = m.book;
        _pane = _Pane.chapters;
      });
      return;
    }
    _pick(m.book.id, m.chapter!, m.verse);
  }

  Widget _browse(List<Book> books, ReadingColors c) {
    final recent = ref.watch(recentPlacesProvider);
    final byId = {for (final b in books) b.id: b};
    final shown =
        books.where((b) => b.isNewTestament == _newTestament).toList();
    if (_alphabetical) {
      shown.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    return CustomScrollView(
      slivers: [
        if (recent.isNotEmpty) ...[
          _label('Недавние', c),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: recent.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final p = recent[i];
                  final b = byId[p.bookId];
                  if (b == null) return const SizedBox.shrink();
                  return _Tap(
                    onTap: () => _pick(p.bookId, p.chapter),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      child: Center(
                        child: Text('${bookLabel(b)} ${p.chapter}',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: c.text)),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: c.background,
                      borderRadius: BorderRadius.circular(Radii.card),
                    ),
                    child: Row(
                      children: [
                        for (final nt in [false, true])
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _newTestament = nt),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  color: _newTestament == nt
                                      ? c.accent
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(Radii.chip),
                                ),
                                child: Center(
                                  child: Text(
                                    nt ? 'Новый Завет' : 'Ветхий Завет',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _newTestament == nt
                                          ? Colors.white
                                          : c.muted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Канонический порядок привычен тем, кто знает Библию, а
                // алфавитный выручает, когда ищешь книгу по названию.
                _RoundButton(
                  icon: _alphabetical
                      ? Icons.sort_by_alpha_rounded
                      : Icons.filter_list_rounded,
                  tooltip: _alphabetical
                      ? 'По алфавиту'
                      : 'В каноническом порядке',
                  onTap: () => setState(() => _alphabetical = !_alphabetical),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 30),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.4,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final b = shown[i];
                final current = ref.watch(positionProvider).bookId == b.id;
                return _Tap(
                  selected: current,
                  onTap: () {
                    if (widget.booksOnly) {
                      _pick(b.id, 1);
                      return;
                    }
                    setState(() {
                      _book = b;
                      _pane = _Pane.chapters;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(9, 10, 6, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(bookIcon(b.id), size: 20, color: c.accent),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bookLabel(b),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                  color: current ? c.accent : c.text,
                                ),
                              ),
                              const SizedBox(height: 3),
                              // Название режем двумя строками: третья не
                              // помещается в плитку и ломает вёрстку при
                              // крупном системном шрифте.
                              Flexible(
                                child: Text(
                                b.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 9.5,
                                  height: 1.25,
                                  color: c.faint,
                                ),
                              ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: shown.length,
            ),
          ),
        ),
      ],
    );
  }

  // ── Главы и стихи ───────────────────────────────────────────────────────

  Widget _chaptersPane(ReadingColors c) {
    final book = _book;
    if (book == null) return const SizedBox.shrink();
    final pos = ref.watch(positionProvider);

    return Column(
      children: [
        _header(book.name, c, onBack: () => setState(() => _pane = _Pane.books)),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Text(
            'Долгое нажатие на главу — выбрать стих',
            style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: c.faint),
          ),
        ),
        Expanded(
          child: _numberGrid(
            count: book.chapters,
            current: pos.bookId == book.id ? pos.chapter : null,
            colors: c,
            onTap: (n) => _pick(book.id, n),
            onLongPress: (n) => setState(() {
              _chapter = n;
              _pane = _Pane.verses;
            }),
          ),
        ),
      ],
    );
  }

  Widget _versesPane(ReadingColors c) {
    final book = _book;
    if (book == null) return const SizedBox.shrink();
    final db = ref.watch(bibleDbProvider).valueOrNull;
    final count =
        db?.verseCount(ref.watch(translationProvider), book.id, _chapter) ?? 0;

    return Column(
      children: [
        _header('${bookLabel(book)} $_chapter', c,
            onBack: () => setState(() => _pane = _Pane.chapters)),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Row(
            children: [
              _Tap(
                onTap: () => _pick(book.id, _chapter),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                    child: Text('Вся глава',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.text)),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _numberGrid(
            count: count,
            current: null,
            colors: c,
            onTap: (n) => _pick(book.id, _chapter, n),
          ),
        ),
      ],
    );
  }

  Widget _numberGrid({
    required int count,
    required int? current,
    required ReadingColors colors,
    required void Function(int) onTap,
    void Function(int)? onLongPress,
  }) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: count,
      itemBuilder: (ctx, i) {
        final n = i + 1;
        return _Tap(
          selected: n == current,
          onTap: () => onTap(n),
          onLongPress: onLongPress == null ? null : () => onLongPress(n),
          child: Center(
            child: Text('$n',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: n == current ? FontWeight.w700 : FontWeight.w500,
                  color: n == current ? colors.accent : colors.text,
                )),
          ),
        );
      },
    );
  }

  Widget _header(String title, ReadingColors c, {required VoidCallback onBack}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 18, 6),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, size: 20, color: c.muted),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, ReadingColors c) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.9,
              color: c.faint,
            ),
          ),
        ),
      );
}

/// Круглая кнопка рядом с переключателем заветов.
class _RoundButton extends ConsumerWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.background,
        borderRadius: BorderRadius.circular(Radii.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20, color: c.accent),
          ),
        ),
      ),
    );
  }
}

/// Плитка с одинаковым поведением во всех трёх шагах.
class _Tap extends ConsumerWidget {
  const _Tap({
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return Material(
      color: selected ? c.accent.withValues(alpha: 0.13) : c.background,
      borderRadius: BorderRadius.circular(Radii.chip),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.chip),
        onTap: onTap,
        onLongPress: onLongPress,
        child: child,
      ),
    );
  }
}
