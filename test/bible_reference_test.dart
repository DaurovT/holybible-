/// Разбор ссылок: «Ин 3:16» должен приводить туда же, куда два экрана выбора.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:holy_bible/core/text/bible_reference.dart';
import 'package:holy_bible/data/models.dart';

Book book(String id, int order, String name, int chapters,
        {bool nt = false}) =>
    Book(
      id: id,
      order: order,
      isNewTestament: nt,
      chapters: chapters,
      name: name,
      // В Синодальном USFM короткого имени нет: и short, и abbrev равны
      // полному названию. Тест повторяет это положение дел.
      shortName: name,
      abbrev: name,
    );

final books = [
  book('GEN', 1, 'Бытие', 50),
  book('PSA', 19, 'Псалтырь', 150),
  book('MAT', 40, 'Евангелие от Матфея', 28, nt: true),
  book('JHN', 43, 'Евангелие от Иоанна', 21, nt: true),
  book('1CO', 46, 'Первое послание к Коринфянам', 16, nt: true),
  book('1JN', 62, 'Первое послание Иоанна', 5, nt: true),
  book('REV', 66, 'Откровение Иоанна Богослова', 22, nt: true),
];

void main() {
  group('короткое имя книги', () {
    test('русское берётся из таблицы, если в базе его нет', () {
      expect(bookLabel(books[4]), '1Кор');
      expect(bookLabel(books[3]), 'Ин');
    });

    test('короткое русское из базы всё равно приводится к привычной форме', () {
      // В базе у Матфея abbrev = «Матфея», но в ссылках пишут «Мф».
      final matthew = Book(
        id: 'MAT',
        order: 40,
        isNewTestament: true,
        chapters: 28,
        name: 'Евангелие от Матфея',
        shortName: 'Евангелие от Матфея',
        abbrev: 'Матфея',
      );
      expect(bookLabel(matthew), 'Мф');
    });

    test('английское берётся из самой базы', () {
      final john = Book(
        id: 'JHN',
        order: 43,
        isNewTestament: true,
        chapters: 21,
        name: 'John',
        shortName: 'John',
        abbrev: 'Jhn',
      );
      expect(bookLabel(john), 'Jhn');
    });
  });

  group('разбор ссылки', () {
    ReferenceMatch first(String input) => parseReference(input, books).first;

    test('сокращение с главой и стихом', () {
      final m = first('Ин 3:16');
      expect(m.book.id, 'JHN');
      expect(m.chapter, 3);
      expect(m.verse, 16);
    });

    test('без пробелов и в нижнем регистре', () {
      final m = first('ин3:16');
      expect(m.book.id, 'JHN');
      expect(m.chapter, 3);
      expect(m.verse, 16);
    });

    test('точка вместо двоеточия', () {
      final m = first('Пс 22.1');
      expect(m.book.id, 'PSA');
      expect(m.chapter, 22);
      expect(m.verse, 1);
    });

    test('книга с числом в названии', () {
      final m = first('1 Кор 13');
      expect(m.book.id, '1CO');
      expect(m.chapter, 13);
      expect(m.verse, isNull);
    });

    test('полное название без номеров', () {
      final m = first('Бытие');
      expect(m.book.id, 'GEN');
      expect(m.chapter, isNull);
    });

    test('глава больше, чем есть в книге, прижимается к последней', () {
      expect(first('Ин 99').chapter, 21);
    });

    test('неоднозначное «Иоанна» даёт все варианты, Евангелие первым', () {
      final all = parseReference('Иоанна', books);
      expect(all.first.book.id, 'JHN');
      expect(all.map((m) => m.book.id), containsAll(['JHN', '1JN', 'REV']));
    });

    test('мусор не находит ничего', () {
      expect(parseReference('щщщ', books), isEmpty);
      expect(parseReference('', books), isEmpty);
    });
  });
}
