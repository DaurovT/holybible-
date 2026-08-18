/// Церковный календарь: даты, которые ни у кого нельзя спросить в офлайне.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:holy_bible/core/calendar/church_calendar.dart';

void main() {
  group('Пасха', () {
    test('западная считается верно', () {
      expect(gregorianEaster(2024), DateTime(2024, 3, 31));
      expect(gregorianEaster(2025), DateTime(2025, 4, 20));
      expect(gregorianEaster(2026), DateTime(2026, 4, 5));
      expect(gregorianEaster(2027), DateTime(2027, 3, 28));
    });

    test('православная считается верно', () {
      expect(orthodoxEaster(2024), DateTime(2024, 5, 5));
      expect(orthodoxEaster(2025), DateTime(2025, 4, 20));
      expect(orthodoxEaster(2026), DateTime(2026, 4, 12));
      expect(orthodoxEaster(2027), DateTime(2027, 5, 2));
    });

    test('в 2025 году обе Пасхи совпали', () {
      expect(orthodoxEaster(2025), gregorianEaster(2025));
    });
  });

  group('подвижные праздники', () {
    test('отсчитываются от своей Пасхи', () {
      final easter = orthodoxEaster(2026);
      expect(
        feastsOn(easter.subtract(const Duration(days: 7)),
                ChurchTradition.orthodox)
            .first
            .name,
        contains('Вход Господень'),
      );
      expect(
        feastsOn(easter.add(const Duration(days: 49)),
                ChurchTradition.orthodox)
            .first
            .name,
        contains('Пятидесятница'),
      );
    });

    test('у западных традиций та же Пятидесятница, но своя дата', () {
      final west = gregorianEaster(2026).add(const Duration(days: 49));
      final east = orthodoxEaster(2026).add(const Duration(days: 49));
      expect(feastsOn(west, ChurchTradition.catholic), isNotEmpty);
      expect(feastsOn(west, ChurchTradition.orthodox), isEmpty);
      expect(east, isNot(west));
    });
  });

  group('неподвижные праздники', () {
    test('Рождество: 7 января у православных, 25 декабря у западных', () {
      expect(feastsOn(DateTime(2026, 1, 7), ChurchTradition.orthodox).first.name,
          'Рождество Христово');
      expect(feastsOn(DateTime(2026, 1, 7), ChurchTradition.catholic), isEmpty);
      expect(
          feastsOn(DateTime(2026, 12, 25), ChurchTradition.protestant)
              .first
              .name,
          'Рождество Христово');
    });

    test('Успение: 28 августа против 15-го', () {
      expect(feastsOn(DateTime(2026, 8, 28), ChurchTradition.orthodox).first.name,
          contains('Успение'));
      expect(feastsOn(DateTime(2026, 8, 15), ChurchTradition.catholic).first.name,
          contains('Успение'));
    });

    test('День Реформации — только у протестантов', () {
      expect(feastsOn(DateTime(2026, 10, 31), ChurchTradition.protestant),
          isNotEmpty);
      expect(
          feastsOn(DateTime(2026, 10, 31), ChurchTradition.orthodox), isEmpty);
    });
  });

  group('честность источника', () {
    test('события из Писания ведут на отрывок', () {
      final christmas =
          feastsOn(DateTime(2026, 1, 7), ChurchTradition.orthodox).first;
      expect(christmas.inScripture, isTrue);
      expect(christmas.bookId, 'LUK');
      expect(christmas.reference, '2:1–20');
    });

    test('праздники предания отрывка не имеют и говорят об этом', () {
      final dormition =
          feastsOn(DateTime(2026, 8, 28), ChurchTradition.orthodox).first;
      expect(dormition.inScripture, isFalse);
      expect(dormition.summary, contains('не описано'));
    });
  });

  group('поиск ближайшего', () {
    test('находит следующий праздник и его дату', () {
      final next = nextFeast(DateTime(2026, 8, 16), ChurchTradition.orthodox);
      expect(next, isNotNull);
      expect(next!.date, DateTime(2026, 8, 19));
      expect(next.feast.name, contains('Преображение'));
    });

    test('дни месяца с праздниками собираются для сетки', () {
      final days = feastDaysOfMonth(2026, 8, ChurchTradition.orthodox);
      expect(days, containsAll([19, 28]));
      expect(days, isNot(contains(17)));
    });
  });
}
