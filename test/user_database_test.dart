/// Проверка личных данных: закладок, выделений, заметок.
///
/// База открывается в памяти, поэтому тест не зависит ни от устройства, ни от
/// path_provider.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:holy_bible/core/theme/reading_theme.dart';
import 'package:holy_bible/data/user_database.dart';

void main() {
  late UserDatabase db;

  setUp(() => db = UserDatabase.openAt(':memory:'));
  tearDown(() => db.dispose());

  group('закладки', () {
    test('ставятся, снимаются и ставятся заново', () {
      expect(db.bookmarks(), isEmpty);

      expect(
          db.toggleBookmark(vkey: 1001, bookId: 'JHN', chapter: 3, verse: 16),
          isTrue);
      expect(db.bookmarks(), hasLength(1));
      expect(db.bookmarks().first.vkey, 1001);

      expect(
          db.toggleBookmark(vkey: 1001, bookId: 'JHN', chapter: 3, verse: 16),
          isFalse);
      expect(db.bookmarks(), isEmpty);

      expect(
          db.toggleBookmark(vkey: 1001, bookId: 'JHN', chapter: 3, verse: 16),
          isTrue);
      expect(db.bookmarks(), hasLength(1));
    });

    test('снятая закладка остаётся в базе помеченной удалённой', () {
      db.toggleBookmark(vkey: 7, bookId: 'GEN', chapter: 1, verse: 1);
      db.removeBookmark(7);

      expect(db.bookmarks(), isEmpty);
      // Мягкое удаление: строка нужна, чтобы синхронизация не вернула
      // закладку с другого устройства.
      final raw = db.debugSelect('SELECT deleted FROM bookmarks WHERE vkey = 7');
      expect(raw, hasLength(1));
      expect(raw.first['deleted'], 1);
    });

    test('новые закладки идут первыми', () {
      db.toggleBookmark(vkey: 1, bookId: 'GEN', chapter: 1, verse: 1);
      db.toggleBookmark(vkey: 2, bookId: 'EXO', chapter: 2, verse: 2);
      expect(db.bookmarks().map((b) => b.vkey), [2, 1]);
    });
  });

  group('выделения', () {
    test('цвет заменяется, а не дублируется', () {
      db.setHighlight(
          vkey: 5,
          bookId: 'PSA',
          chapter: 23,
          verse: 1,
          tint: HighlightTint.yellow);
      db.setHighlight(
          vkey: 5,
          bookId: 'PSA',
          chapter: 23,
          verse: 1,
          tint: HighlightTint.blue);

      expect(db.highlights(), hasLength(1));
      expect(db.highlights().first.tint, HighlightTint.blue);
    });

    test('снятое выделение возвращается тем же стихом', () {
      db.setHighlight(
          vkey: 5,
          bookId: 'PSA',
          chapter: 23,
          verse: 1,
          tint: HighlightTint.green);
      db.removeHighlight(5);
      expect(db.highlights(), isEmpty);

      db.setHighlight(
          vkey: 5,
          bookId: 'PSA',
          chapter: 23,
          verse: 1,
          tint: HighlightTint.rose);
      expect(db.highlights(), hasLength(1));
      expect(db.highlights().first.tint, HighlightTint.rose);
    });

    test('неизвестный цвет из базы не роняет приложение', () {
      expect(HighlightTint.parse('вишнёвый'), HighlightTint.yellow);
    });
  });

  group('заметки', () {
    test('пишутся, правятся и удаляются', () {
      db.insertNote(
        vkey: 100,
        vkeyEnd: 102,
        bookId: 'MAT',
        chapter: 5,
        verse: 3,
        verseEnd: 5,
        body: 'Почему именно «нищие»?',
      );

      var notes = db.notes();
      expect(notes, hasLength(1));
      expect(notes.first.body, 'Почему именно «нищие»?');
      expect(notes.first.verseEnd, 5);

      db.updateNote(notes.first.id, 'Речь о нищете духа, не о бедности');
      notes = db.notes();
      expect(notes.first.body, 'Речь о нищете духа, не о бедности');

      db.removeNote(notes.first.id);
      expect(db.notes(), isEmpty);
    });

    test('к одному стиху можно написать несколько заметок', () {
      for (final body in ['первая', 'вторая']) {
        db.insertNote(
          vkey: 200,
          vkeyEnd: 200,
          bookId: 'JHN',
          chapter: 1,
          verse: 1,
          verseEnd: 1,
          body: body,
        );
      }
      expect(db.notes(), hasLength(2));
      expect(db.notes().every((n) => n.vkey == 200), isTrue);
    });
  });

  test('идентификаторы для синхронизации не повторяются', () {
    final ids = {for (var i = 0; i < 500; i++) UserDatabase.newUuid()};
    expect(ids, hasLength(500));
    expect(ids.every((id) => id.length == 32), isTrue);
  });
}
