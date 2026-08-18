/// Состояние личных данных: закладки, выделения, заметки.
///
/// Всё держится в памяти целиком и перечитывается из базы после каждой правки.
/// Данных здесь единицы килобайт, зато рендер стиха узнаёт цвет выделения
/// синхронно: асинхронный запрос на каждый абзац дёргал бы скролл.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/reading_theme.dart';
import '../data/models.dart';
import '../data/user_database.dart';

@immutable
class UserData {
  UserData({
    this.bookmarks = const [],
    this.highlights = const [],
    this.notes = const [],
    this.ready = false,
  })  : bookmarkedKeys = {for (final b in bookmarks) b.vkey},
        tints = {for (final h in highlights) h.vkey: h.tint},
        notesByKey = _group(notes);

  final List<Bookmark> bookmarks;
  final List<Highlight> highlights;
  final List<Note> notes;

  /// false, пока база ещё открывается. Нужно, чтобы не рисовать пустой
  /// раздел «Моё» как «здесь ничего нет».
  final bool ready;

  final Set<int> bookmarkedKeys;
  final Map<int, HighlightTint> tints;
  final Map<int, List<Note>> notesByKey;

  static Map<int, List<Note>> _group(List<Note> notes) {
    final out = <int, List<Note>>{};
    for (final n in notes) {
      (out[n.vkey] ??= []).add(n);
    }
    return out;
  }

  bool get isEmpty =>
      bookmarks.isEmpty && highlights.isEmpty && notes.isEmpty;

  bool isBookmarked(int vkey) => bookmarkedKeys.contains(vkey);
  HighlightTint? tintOf(int vkey) => tints[vkey];
  List<Note> notesFor(int vkey) => notesByKey[vkey] ?? const [];
}

class UserDataNotifier extends StateNotifier<UserData> {
  UserDataNotifier() : super(UserData()) {
    _load();
  }

  /// Одно открытие на весь жизненный цикл: повторный await того же future
  /// не открывает файл заново.
  late final Future<UserDatabase> _open = UserDatabase.open();

  Future<void> _load() async {
    final db = await _open;
    if (!mounted) return;
    _refresh(db);
  }

  void _refresh(UserDatabase db) {
    state = UserData(
      bookmarks: db.bookmarks(),
      highlights: db.highlights(),
      notes: db.notes(),
      ready: true,
    );
  }

  // ── Закладки ────────────────────────────────────────────────────────────

  /// Возвращает true, если закладка поставлена, и false, если снята.
  Future<bool> toggleBookmark(Verse verse) async {
    final db = await _open;
    final on = db.toggleBookmark(
      vkey: verse.vkey,
      bookId: verse.bookId,
      chapter: verse.chapter,
      verse: verse.number,
    );
    if (mounted) _refresh(db);
    return on;
  }

  Future<void> removeBookmark(int vkey) async {
    final db = await _open;
    db.removeBookmark(vkey);
    if (mounted) _refresh(db);
  }

  // ── Выделения ───────────────────────────────────────────────────────────

  /// Красит все переданные стихи. Повторный тот же цвет снимает выделение —
  /// так убрать краску можно тем же жестом, которым её поставили.
  Future<void> setHighlight(List<Verse> verses, HighlightTint tint) async {
    final db = await _open;
    final allSame = verses.isNotEmpty &&
        verses.every((v) => state.tintOf(v.vkey) == tint);
    for (final v in verses) {
      if (allSame) {
        db.removeHighlight(v.vkey);
      } else {
        db.setHighlight(
          vkey: v.vkey,
          bookId: v.bookId,
          chapter: v.chapter,
          verse: v.number,
          tint: tint,
        );
      }
    }
    if (mounted) _refresh(db);
  }

  Future<void> removeHighlight(int vkey) async {
    final db = await _open;
    db.removeHighlight(vkey);
    if (mounted) _refresh(db);
  }

  // ── Заметки ─────────────────────────────────────────────────────────────

  /// Правка существующей заметки идёт по её id: список стихов для этого не
  /// нужен, и заметку можно открыть из «Моё», где стих под рукой не всегда.
  Future<void> saveNote({
    int? id,
    required List<Verse> verses,
    required String body,
  }) async {
    final db = await _open;
    if (id != null) {
      db.updateNote(id, body.trim());
      if (mounted) _refresh(db);
      return;
    }
    if (verses.isEmpty) return;
    final sorted = [...verses]..sort((a, b) => a.vkey.compareTo(b.vkey));
    db.insertNote(
      vkey: sorted.first.vkey,
      vkeyEnd: sorted.last.vkey,
      bookId: sorted.first.bookId,
      chapter: sorted.first.chapter,
      verse: sorted.first.number,
      verseEnd: sorted.last.number,
      body: body.trim(),
    );
    if (mounted) _refresh(db);
  }

  Future<void> removeNote(int id) async {
    final db = await _open;
    db.removeNote(id);
    if (mounted) _refresh(db);
  }

  @override
  void dispose() {
    _open.then((db) => db.dispose());
    super.dispose();
  }
}

final userDataProvider =
    StateNotifierProvider<UserDataNotifier, UserData>((ref) => UserDataNotifier());
