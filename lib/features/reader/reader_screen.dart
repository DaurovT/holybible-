/// Экран чтения.
///
/// Лента непрерывна: главы идут одна за другой без перелистывания и без
/// кнопок «дальше». Это главное отличие от типовых читалок, где каждая глава
/// живёт отдельным экраном и чтение постоянно спотыкается о навигацию.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/bible_reference.dart';
import '../../core/theme/reading_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../state/user_data.dart';
import '../entity/entity_sheet.dart';
import '../library/note_sheet.dart';
import '../search/search_screen.dart';
import 'book_picker.dart';
import 'passage_actions.dart';
import 'reader_settings_sheet.dart';
import 'verse_renderer.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _controller = ScrollController();
  final _centerKey = GlobalKey();

  /// Индекс главы, вокруг которой построена лента. Всё, что выше, живёт в
  /// «обратном» сливере, всё ниже — в прямом.
  int _anchor = 0;
  bool _anchorReady = false;

  /// Что сейчас на экране — для заголовка.
  Book? _visibleBook;
  int _visibleChapter = 0;

  final _chapterKeys = <int, GlobalKey>{};

  /// Выделенные стихи текущей главы: ключ стиха → сам стих.
  final _selected = <int, Verse>{};

  /// Откуда пришли. Прыжок из поиска, закладки или карточки уносит далеко, и
  /// без этой стопки дорогу назад приходится искать руками.
  final _history = <ReadingPosition>[];

  /// Стих, к которому только что перешли: его надо подвести под глаз и
  /// ненадолго подсветить, иначе человек оказывается в начале главы и сам
  /// ищет, куда он, собственно, шёл.
  final _focusKey = GlobalKey();
  int? _focusVkey;
  bool _focusScrolled = false;
  Timer? _focusTimer;

  @override
  void dispose() {
    _focusTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _setAnchorFromPosition(List<(Book, int)> index) {
    if (_anchorReady) return;
    final pos = ref.read(positionProvider);
    final i = index.indexWhere(
        (e) => e.$1.id == pos.bookId && e.$2 == pos.chapter);
    _anchor = i < 0 ? 0 : i;
    _anchorReady = true;
    _visibleBook = index[_anchor].$1;
    _visibleChapter = index[_anchor].$2;
  }

  /// Определяет главу под верхней кромкой экрана и обновляет заголовок.
  void _updateVisible(List<(Book, int)> index) {
    final scrollBox = context.findRenderObject();
    if (scrollBox is! RenderBox) return;
    for (final entry in _chapterKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero, ancestor: scrollBox).dy;
      final bottom = top + box.size.height;
      if (top <= 120 && bottom > 120) {
        if (entry.key < 0 || entry.key >= index.length) return;
        final (book, ch) = index[entry.key];
        if (book.id != _visibleBook?.id || ch != _visibleChapter) {
          setState(() {
            _visibleBook = book;
            _visibleChapter = ch;
          });
          ref.read(positionProvider.notifier).set(book.id, ch);
        }
        return;
      }
    }
  }

  /// [record] — запомнить, откуда прыгнули. Сам возврат по истории ничего не
  /// записывает, иначе «назад» ходило бы по кругу между двумя местами.
  Future<void> _jumpTo(String bookId, int chapter,
      {int? vkey, bool record = true}) async {
    final index = await ref.read(chapterIndexProvider.future);
    final i =
        index.indexWhere((e) => e.$1.id == bookId && e.$2 == chapter);
    if (i < 0) return;
    _focusTimer?.cancel();
    setState(() {
      if (record &&
          _visibleBook != null &&
          (_visibleBook!.id != bookId || _visibleChapter != chapter)) {
        _history.add(ReadingPosition(_visibleBook!.id, _visibleChapter));
        if (_history.length > 20) _history.removeAt(0);
      }
      _anchor = i;
      _selected.clear();
      _chapterKeys.clear();
      _visibleBook = index[i].$1;
      _visibleChapter = index[i].$2;
      _focusVkey = vkey;
      _focusScrolled = false;
    });
    ref.read(positionProvider.notifier).set(bookId, chapter);
    ref.read(recentPlacesProvider.notifier).remember(bookId, chapter);
    // Лента перестраивается вокруг новой опоры, поэтому прокрутку сбрасываем.
    if (_controller.hasClients) _controller.jumpTo(0);

    if (vkey != null) {
      _focusTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _focusVkey = null);
      });
    }
  }

  /// Подводит найденный стих под верх экрана. Вызывается из построенной главы:
  /// раньше её просто нет на экране, и прокручивать некуда.
  void _ensureFocusVisible() {
    if (_focusScrolled || _focusVkey == null) return;
    final ctx = _focusKey.currentContext;
    if (ctx == null) return;
    _focusScrolled = true;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.18,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  Future<void> _back() async {
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    await _jumpTo(prev.bookId, prev.chapter, record: false);
  }

  void _openNote(Verse verse) {
    final existing = ref.read(userDataProvider).notesFor(verse.vkey);
    showNoteSheet(
      context,
      verses: [verse],
      reference: '${_visibleBook == null ? '' : bookLabel(_visibleBook!)} '
          '${verse.chapter}:${verse.number}',
      existing: existing.isEmpty ? null : existing.first,
    );
  }

  void _toggleVerse(Verse v) {
    setState(() {
      if (_selected.containsKey(v.vkey)) {
        _selected.remove(v.vkey);
      } else {
        _selected[v.vkey] = v;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final c = settings.colors;
    final indexAsync = ref.watch(chapterIndexProvider);
    final userData = ref.watch(userDataProvider);

    // Просьбу о переходе гасим сразу: иначе, вернувшись на вкладку чтения,
    // экран прыгнет туда же ещё раз.
    ref.listen<JumpTarget?>(jumpRequestProvider, (_, next) {
      if (next == null) return;
      ref.read(jumpRequestProvider.notifier).state = null;
      _jumpTo(next.bookId, next.chapter, vkey: next.vkey);
    });

    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
    String placeLabel(ReadingPosition p) {
      final b = books.where((x) => x.id == p.bookId).firstOrNull;
      return b == null ? '${p.bookId} ${p.chapter}' : '${bookLabel(b)} ${p.chapter}';
    }

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        leadingWidth: 46,
        leading: _history.isEmpty
            ? null
            : IconButton(
                tooltip: 'Назад к ${placeLabel(_history.last)}',
                icon: Icon(Icons.arrow_back_rounded, size: 20, color: c.muted),
                onPressed: _back,
              ),
        // Заголовок — кнопка перехода. Раньше это был обычный текст, и то,
        // что по нему можно нажать, приходилось угадывать.
        title: Material(
          color: c.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _openBookPicker(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 7, 10, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _visibleBook == null
                          ? 'Выбрать книгу'
                          : '${bookLabel(_visibleBook!)} $_visibleChapter',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.expand_more_rounded, size: 18, color: c.muted),
                ],
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Поиск',
            icon: const Icon(Icons.search_rounded, size: 21),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          IconButton(
            tooltip: 'Оформление',
            icon: const Icon(Icons.text_fields_rounded, size: 20),
            onPressed: () => showReaderSettings(context, ref),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: indexAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Не удалось открыть текст: $e')),
        data: (index) {
          _setAnchorFromPosition(index);
          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollUpdateNotification) _updateVisible(index);
              return false;
            },
            child: Stack(
              children: [
                CustomScrollView(
                  controller: _controller,
                  center: _centerKey,
                  slivers: [
                    // Главы выше опоры. Обратный сливер позволяет листать
                    // назад бесконечно, не перестраивая список.
                    SliverList.builder(
                      itemCount: _anchor,
                      itemBuilder: (ctx, i) =>
                          _chapterAt(index, _anchor - 1 - i, settings, userData),
                    ),
                    SliverToBoxAdapter(key: _centerKey),
                    SliverList.builder(
                      itemCount: index.length - _anchor,
                      itemBuilder: (ctx, i) =>
                          _chapterAt(index, _anchor + i, settings, userData),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 160)),
                  ],
                ),
                if (_selected.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: PassageActionsBar(
                      verses: _selected.values.toList()
                        ..sort((a, b) => a.vkey.compareTo(b.vkey)),
                      book: _visibleBook,
                      onClose: () => setState(_selected.clear),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _chapterAt(List<(Book, int)> index, int i, ReadingSettings settings,
      UserData userData) {
    if (i < 0 || i >= index.length) return const SizedBox.shrink();
    final (book, chapter) = index[i];
    final key = _chapterKeys.putIfAbsent(i, () => GlobalKey());
    return _ChapterView(
      key: ValueKey('$i-${book.id}-$chapter'),
      measureKey: key,
      book: book,
      chapter: chapter,
      settings: settings,
      selected: _selected,
      userData: userData,
      focusVkey: _focusVkey,
      focusKey: _focusKey,
      onFocusBuilt: _ensureFocusVisible,
      onToggleVerse: _toggleVerse,
      onTapNote: _openNote,
    );
  }

  Future<void> _openBookPicker(BuildContext context) async {
    final place = await showBookPicker(context, ref);
    if (place == null) return;

    // Ссылку со стихом превращаем в ключ стиха: по нему лента подведёт именно
    // к нему, а не к началу главы.
    int? vkey;
    if (place.verse != null) {
      final db = await ref.read(bibleDbProvider.future);
      vkey = db.vkeyFor(ref.read(translationProvider), place.bookId,
          place.chapter, place.verse!);
    }
    await _jumpTo(place.bookId, place.chapter, vkey: vkey);
  }
}

class _ChapterView extends ConsumerWidget {
  const _ChapterView({
    super.key,
    required this.measureKey,
    required this.book,
    required this.chapter,
    required this.settings,
    required this.selected,
    required this.userData,
    required this.focusKey,
    required this.focusVkey,
    required this.onFocusBuilt,
    required this.onToggleVerse,
    required this.onTapNote,
  });

  final GlobalKey measureKey;
  final Book book;
  final int chapter;
  final ReadingSettings settings;
  final Map<int, Verse> selected;
  final UserData userData;
  final GlobalKey focusKey;
  final int? focusVkey;
  final VoidCallback onFocusBuilt;
  final void Function(Verse) onToggleVerse;
  final void Function(Verse) onTapNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translation = ref.watch(translationProvider);
    final key = (
      translationId: translation,
      bookId: book.id,
      chapter: chapter,
    );
    final async = ref.watch(chapterProvider(key));
    final parallel = ref.watch(parallelChapterProvider(key)).valueOrNull;
    final c = settings.colors;

    return Container(
      key: measureKey,
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: settings.maxLineWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Ошибка: $e', style: TextStyle(color: c.muted)),
            ),
            data: (ch) {
              if (ch == null) return const SizedBox.shrink();
              final selectedNumbers = {
                for (final v in selected.values)
                  if (v.bookId == book.id && v.chapter == chapter) v.number
              };
              final noted = userData.notesByKey.keys.toSet();

              if (parallel != null && parallel.isNotEmpty) {
                return _parallel(
                    context, ref, ch, parallel, selectedNumbers, noted);
              }

              final blocks =
                  buildBlocks(ch, paragraphMode: settings.paragraphMode);

              // Ключ для прокрутки вешаем на тот абзац, где лежит нужный стих.
              final paragraphs = <Widget>[];
              var focusAttached = false;
              for (final b in blocks) {
                Widget w = ReaderParagraph(
                  block: b,
                  settings: settings,
                  selectedVerses: selectedNumbers,
                  highlights: userData.tints,
                  notedVerses: noted,
                  focusedVerses: focusVkey == null ? const {} : {focusVkey!},
                  onTapEntity: (id) => showEntitySheet(context, id),
                  onTapVerse: onToggleVerse,
                  onLongPressVerse: onToggleVerse,
                  onTapFootnote: (note) => _showFootnote(context, note, c),
                  onTapNote: onTapNote,
                );
                if (!focusAttached &&
                    focusVkey != null &&
                    b.pieces.any((p) => p.verse.vkey == focusVkey)) {
                  focusAttached = true;
                  w = KeyedSubtree(key: focusKey, child: w);
                }
                paragraphs.add(w);
              }
              if (focusAttached) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => onFocusBuilt());
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ChapterHeader(
                      book: book, chapter: chapter, settings: settings),
                  ...paragraphs,
                  const SizedBox(height: 26),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Параллельный режим: абзацы уступают место парам «стих — стих».
  ///
  /// Иначе два перевода не выровнять: в прозе они текут разными абзацами, и
  /// «тот же стих рядом» превращается в угадайку. На узком экране пары идут
  /// друг под другом — две колонки по 25 знаков в строке читать невозможно.
  Widget _parallel(
    BuildContext context,
    WidgetRef ref,
    Chapter ch,
    Map<int, Verse> other,
    Set<int> selectedNumbers,
    Set<int> noted,
  ) {
    final c = settings.colors;
    final translations =
        ref.watch(translationsProvider).valueOrNull ?? const <Translation>[];
    String abbrev(String id) => translations
        .where((t) => t.id == id)
        .map((t) => t.abbrev)
        .followedBy([id]).first;
    final otherId = ref.watch(parallelTranslationProvider);
    final label = otherId == null
        ? null
        : '${abbrev(ref.watch(translationProvider))}  ·  ${abbrev(otherId)}';

    return LayoutBuilder(
      builder: (ctx, box) {
        final twoColumns = box.maxWidth >= 560;
        final rows = <Widget>[];
        var focusAttached = false;

        for (final v in ch.verses) {
          Widget primary = ReaderParagraph(
            block: ReaderBlock(
              style: v.segments.first.style,
              pieces: [
                for (var i = 0; i < v.segments.length; i++)
                  BlockPiece(v, v.segments[i], i == 0)
              ],
            ),
            settings: settings,
            selectedVerses: selectedNumbers,
            highlights: userData.tints,
            notedVerses: noted,
            focusedVerses: focusVkey == null ? const {} : {focusVkey!},
            onTapEntity: (id) => showEntitySheet(context, id),
            onTapVerse: onToggleVerse,
            onLongPressVerse: onToggleVerse,
            onTapFootnote: (note) => _showFootnote(context, note, c),
            onTapNote: onTapNote,
          );
          if (!focusAttached && v.vkey == focusVkey) {
            focusAttached = true;
            primary = KeyedSubtree(key: focusKey, child: primary);
          }

          final mirror = other[v.vkey]?.text ?? '';
          final secondary = Text(
            mirror,
            style: TextStyle(
              fontFamily: settings.fontFamily,
              fontSize: settings.fontSize * 0.94,
              height: settings.lineHeight,
              color: c.muted,
            ),
          );

          rows.add(Padding(
            padding: EdgeInsets.only(bottom: twoColumns ? 12 : 16),
            child: twoColumns
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: primary),
                      const SizedBox(width: 22),
                      Expanded(
                          child: mirror.isEmpty
                              ? const SizedBox.shrink()
                              : secondary),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      primary,
                      if (mirror.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5, left: 2),
                          child: Container(
                            padding: const EdgeInsets.only(left: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                  left: BorderSide(color: c.divider, width: 2)),
                            ),
                            child: secondary,
                          ),
                        ),
                    ],
                  ),
          ));
        }

        if (focusAttached) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onFocusBuilt());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChapterHeader(
                book: book,
                chapter: chapter,
                settings: settings,
                parallelLabel: label),
            ...rows,
            const SizedBox(height: 26),
          ],
        );
      },
    );
  }

  void _showFootnote(BuildContext context, String note, ReadingColors c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Примечание',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    letterSpacing: 0.6,
                    color: c.muted)),
            const SizedBox(height: 10),
            Text(note,
                style: TextStyle(
                    fontFamily: 'Literata',
                    fontSize: 15,
                    height: 1.5,
                    color: c.text)),
          ],
        ),
      ),
    );
  }
}

class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({
    required this.book,
    required this.chapter,
    required this.settings,
    this.parallelLabel,
  });

  final Book book;
  final int chapter;
  final ReadingSettings settings;

  /// «СИН · KJV» — какие переводы сейчас рядом. Показывается один раз на главу,
  /// а не у каждого стиха.
  final String? parallelLabel;

  @override
  Widget build(BuildContext context) {
    final c = settings.colors;
    // Название книги показываем только в её первой главе — дальше достаточно
    // крупной цифры, как в печатном издании.
    final showBookName = chapter == 1;
    return Padding(
      padding: EdgeInsets.only(top: showBookName ? 40 : 30, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBookName) ...[
            Text(
              book.name,
              style: TextStyle(
                fontFamily: 'Literata',
                fontSize: settings.fontSize * 1.5,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: c.text,
              ),
            ),
            const SizedBox(height: 18),
          ],
          Text(
            '$chapter',
            style: TextStyle(
              fontFamily: 'Literata',
              fontSize: settings.fontSize * 2.1,
              fontWeight: FontWeight.w500,
              height: 1.0,
              color: c.faint,
            ),
          ),
          if (parallelLabel != null) ...[
            const SizedBox(height: 10),
            Text(
              parallelLabel!,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.9,
                color: c.faint,
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
