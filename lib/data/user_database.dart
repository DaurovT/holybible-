/// Личные данные пользователя: закладки, выделения, заметки.
///
/// Живут в отдельном файле `user.db`, а не в bible.db: та вшита в бандл,
/// открыта только для чтения и перезаписывается при каждом обновлении
/// приложения. Смешать их значило бы терять заметки с каждым релизом.
///
/// Схема сразу готова к синхронизации, хотя аккаунтов ещё нет: у каждой записи
/// есть `uuid`, `updated_at` и мягкое удаление. Добавить их потом — значит
/// мигрировать базу у всех, кто уже что-то записал.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/theme/reading_theme.dart';

/// Закладка на стих — «вернуться сюда».
class Bookmark {
  final int id;
  final int vkey;
  final String bookId;
  final int chapter;
  final int verse;
  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.vkey,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.createdAt,
  });
}

/// Цветное выделение стиха.
class Highlight {
  final int id;
  final int vkey;
  final String bookId;
  final int chapter;
  final int verse;
  final HighlightTint tint;
  final DateTime createdAt;

  const Highlight({
    required this.id,
    required this.vkey,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.tint,
    required this.createdAt,
  });
}

/// Заметка к отрывку. Привязана к первому стиху, но помнит и последний,
/// чтобы показать «Иоанна 3:16–18».
class Note {
  final int id;
  final int vkey;
  final int vkeyEnd;
  final String bookId;
  final int chapter;
  final int verse;
  final int verseEnd;
  final String body;
  final DateTime updatedAt;

  const Note({
    required this.id,
    required this.vkey,
    required this.vkeyEnd,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.verseEnd,
    required this.body,
    required this.updatedAt,
  });
}

const userDbSchema = '''
CREATE TABLE IF NOT EXISTS bookmarks (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid       TEXT NOT NULL UNIQUE,
  vkey       INTEGER NOT NULL,
  book_id    TEXT NOT NULL,
  chapter    INTEGER NOT NULL,
  verse      INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted    INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS bookmarks_vkey ON bookmarks(vkey);

CREATE TABLE IF NOT EXISTS highlights (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid       TEXT NOT NULL UNIQUE,
  vkey       INTEGER NOT NULL,
  book_id    TEXT NOT NULL,
  chapter    INTEGER NOT NULL,
  verse      INTEGER NOT NULL,
  tint       TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted    INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS highlights_vkey ON highlights(vkey);

CREATE TABLE IF NOT EXISTS notes (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid       TEXT NOT NULL UNIQUE,
  vkey       INTEGER NOT NULL,
  vkey_end   INTEGER NOT NULL,
  book_id    TEXT NOT NULL,
  chapter    INTEGER NOT NULL,
  verse      INTEGER NOT NULL,
  verse_end  INTEGER NOT NULL,
  body       TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS notes_vkey ON notes(vkey);
''';

class UserDatabase {
  UserDatabase._(this._db);

  final Database _db;
  static final _random = Random.secure();

  static Future<UserDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    return openAt(p.join(dir.path, 'user.db'));
  }

  /// Открытие по явному пути. Нужно тестам: path_provider вне приложения не
  /// работает, а логика закладок и заметок проверяема сама по себе.
  static UserDatabase openAt(String path) {
    final db = sqlite3.open(path);
    db.execute(userDbSchema);
    return UserDatabase._(db);
  }

  void dispose() => _db.dispose();

  /// Сырой запрос — только для тестов: мягкое удаление иначе не проверить,
  /// обычные методы удалённые строки не показывают.
  @visibleForTesting
  ResultSet debugSelect(String sql) => _db.select(sql);

  /// Идентификатор, который не столкнётся с чужим при будущей синхронизации.
  static String newUuid() {
    final bytes = List.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  // ── Закладки ────────────────────────────────────────────────────────────

  List<Bookmark> bookmarks() => [
        for (final r in _db.select('''
          SELECT id, vkey, book_id, chapter, verse, created_at
          FROM bookmarks WHERE deleted = 0
          -- id как второй ключ: две отметки в одну миллисекунду иначе
          -- меняются местами от запроса к запросу.
          ORDER BY created_at DESC, id DESC
        '''))
          Bookmark(
            id: r['id'] as int,
            vkey: r['vkey'] as int,
            bookId: r['book_id'] as String,
            chapter: r['chapter'] as int,
            verse: r['verse'] as int,
            createdAt:
                DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
          )
      ];

  /// Ставит или снимает закладку. Возвращает новое состояние.
  ///
  /// Снятая закладка помечается удалённой, а не стирается: иначе после
  /// подключения синхронизации она вернётся с другого устройства.
  bool toggleBookmark({
    required int vkey,
    required String bookId,
    required int chapter,
    required int verse,
  }) {
    final existing = _db.select(
        'SELECT id, deleted FROM bookmarks WHERE vkey = ?', [vkey]);
    if (existing.isEmpty) {
      _db.execute('''
        INSERT INTO bookmarks
          (uuid, vkey, book_id, chapter, verse, created_at, updated_at, deleted)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0)
      ''', [newUuid(), vkey, bookId, chapter, verse, _now, _now]);
      return true;
    }
    final wasDeleted = existing.first['deleted'] == 1;
    _db.execute(
        'UPDATE bookmarks SET deleted = ?, created_at = ?, updated_at = ? WHERE vkey = ?',
        [wasDeleted ? 0 : 1, _now, _now, vkey]);
    return wasDeleted;
  }

  void removeBookmark(int vkey) => _db.execute(
      'UPDATE bookmarks SET deleted = 1, updated_at = ? WHERE vkey = ?',
      [_now, vkey]);

  // ── Выделения ───────────────────────────────────────────────────────────

  List<Highlight> highlights() => [
        for (final r in _db.select('''
          SELECT id, vkey, book_id, chapter, verse, tint, created_at
          FROM highlights WHERE deleted = 0 ORDER BY created_at DESC, id DESC
        '''))
          Highlight(
            id: r['id'] as int,
            vkey: r['vkey'] as int,
            bookId: r['book_id'] as String,
            chapter: r['chapter'] as int,
            verse: r['verse'] as int,
            tint: HighlightTint.parse(r['tint'] as String),
            createdAt:
                DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
          )
      ];

  void setHighlight({
    required int vkey,
    required String bookId,
    required int chapter,
    required int verse,
    required HighlightTint tint,
  }) {
    _db.execute('''
      INSERT INTO highlights
        (uuid, vkey, book_id, chapter, verse, tint, created_at, updated_at, deleted)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
      ON CONFLICT(vkey) DO UPDATE SET
        tint = excluded.tint, updated_at = excluded.updated_at, deleted = 0
    ''', [newUuid(), vkey, bookId, chapter, verse, tint.name, _now, _now]);
  }

  void removeHighlight(int vkey) => _db.execute(
      'UPDATE highlights SET deleted = 1, updated_at = ? WHERE vkey = ?',
      [_now, vkey]);

  // ── Заметки ─────────────────────────────────────────────────────────────

  List<Note> notes() => [
        for (final r in _db.select('''
          SELECT id, vkey, vkey_end, book_id, chapter, verse, verse_end, body,
                 updated_at
          FROM notes WHERE deleted = 0 ORDER BY updated_at DESC, id DESC
        '''))
          Note(
            id: r['id'] as int,
            vkey: r['vkey'] as int,
            vkeyEnd: r['vkey_end'] as int,
            bookId: r['book_id'] as String,
            chapter: r['chapter'] as int,
            verse: r['verse'] as int,
            verseEnd: r['verse_end'] as int,
            body: r['body'] as String,
            updatedAt:
                DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
          )
      ];

  void updateNote(int id, String body) => _db.execute(
      'UPDATE notes SET body = ?, updated_at = ? WHERE id = ?',
      [body, _now, id]);

  void insertNote({
    required int vkey,
    required int vkeyEnd,
    required String bookId,
    required int chapter,
    required int verse,
    required int verseEnd,
    required String body,
  }) {
    _db.execute('''
      INSERT INTO notes
        (uuid, vkey, vkey_end, book_id, chapter, verse, verse_end, body,
         created_at, updated_at, deleted)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
    ''', [
      newUuid(),
      vkey,
      vkeyEnd,
      bookId,
      chapter,
      verse,
      verseEnd,
      body,
      _now,
      _now,
    ]);
  }

  void removeNote(int id) => _db.execute(
      'UPDATE notes SET deleted = 1, updated_at = ? WHERE id = ?', [_now, id]);
}
