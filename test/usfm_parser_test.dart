/// Проверка разбора USFM: где строка обязана разрываться, а где нет.
///
/// Тест написан после реального провала: Синодальный USFM помечает маркером \m
/// каждую печатную строку бумажного издания, парсер считал их абзацами, и
/// родословие Матфея читалось обрывками — «Авраам» / «родил Исаака;».
library;

import 'package:flutter_test/flutter_test.dart';

import '../tool/usfm_parser.dart';

/// Собирает книгу из строк USFM, добавляя обязательную шапку.
ParsedBook parse(List<String> lines) => parseUsfm([
      '\\id MAT',
      '\\h Тест',
      '\\c 1',
      ...lines,
    ].join('\n'));

void main() {
  group('\\m внутри стиха', () {
    test('не разрывает строку и не плодит сегменты', () {
      final book = parse([
        '\\p',
        '\\v 1 Авраам  ',
        '\\m родил Исаака;  ',
        '\\m Исаак родил Иакова;  ',
      ]);

      final verse = book.verses.single;
      expect(verse.plainText, 'Авраам родил Исаака; Исаак родил Иакова;');
      expect(verse.segments, hasLength(1),
          reason: 'продолжения склеиваются в один сегмент');
      expect(verse.segments.single.style, 'p',
          reason: 'стиль остаётся от \\p, иначе рендер разорвёт строку');
    });

    test('слова не склеиваются, даже если в исходнике нет пробела в конце', () {
      final book = parse([
        '\\p',
        '\\v 1 Симон',
        '\\m Петр,',
        '\\m раб',
      ]);
      expect(book.verses.single.plainText, 'Симон Петр, раб');
    });

    test('пустой \\m перед следующим стихом начинает новый абзац', () {
      final book = parse([
        '\\p',
        '\\v 1 Первый.',
        '\\m',
        '\\v 2 Второй.',
      ]);
      expect(book.verses[1].segments.first.brk, isTrue);
    });
  });

  group('поэзия', () {
    test('\\q1 остаётся разрывом строки', () {
      final book = parse([
        '\\q1',
        '\\v 1 Господь - Пастырь мой;',
        '\\q1 я ни в чем не буду нуждаться:',
      ]);

      final verse = book.verses.single;
      expect(verse.segments, hasLength(2));
      expect(verse.segments.every((s) => s.style == 'q1'), isTrue);
      expect(verse.segments[1].brk, isTrue,
          reason: 'иначе Псалтирь превращается в простыню');
    });

    test('смена стиля абзаца тоже разрывает строку', () {
      final book = parse([
        '\\q1',
        '\\v 1 Строка стиха,',
        '\\p проза следом.',
      ]);
      expect(book.verses.single.segments.map((s) => s.style), ['q1', 'p']);
      expect(book.verses.single.segments[1].brk, isTrue);
    });
  });

  group('смещения', () {
    test('границы run\'ов ложатся точно на слова итогового текста', () {
      final book = parse([
        '\\p',
        '\\v 1 Иисус сказал: \\wj Я есмь путь\\wj* — и умолк.',
      ]);

      final verse = book.verses.single;
      final wj = verse.segments
          .expand((s) => s.runs)
          .firstWhere((r) => r.marks.contains('wj'));
      expect(verse.plainText.substring(wj.start, wj.end).trim(), 'Я есмь путь');
    });

    test('заголовок раздела не попадает в текст стиха', () {
      final book = parse([
        '\\s1 Родословие',
        '\\p',
        '\\v 1 Родословие Иисуса Христа.',
      ]);
      expect(book.verses.single.plainText, 'Родословие Иисуса Христа.');
      expect(book.headings.single.text, 'Родословие');
      expect(book.headings.single.beforeVerse, 1);
    });
  });
}
