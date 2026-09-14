/// Церковный календарь: даты праздников считаются на устройстве.
///
/// Никакого сервера здесь не нужно. Пасха выводится формулой, от неё пляшут все
/// подвижные праздники, а неподвижные — просто числа. Разница традиций тоже
/// вычислима: православные держатся юлианского счёта, и в XX–XXI веках его
/// числа отстоят от гражданского календаря ровно на 13 дней.
///
/// Праздники, которых нет в Писании, помечены явно: приложение обещало
/// разделять «Библия говорит» и «церковное предание», и календарь — первое
/// место, где это видно.
library;

enum ChurchTradition {
  orthodox('Православие'),
  catholic('Католичество'),
  protestant('Протестантизм'),
  none('Без привязки');

  const ChurchTradition(this.title);
  final String title;

  static ChurchTradition parse(String? s) => values.firstWhere(
        (t) => t.name == s,
        orElse: () => ChurchTradition.orthodox,
      );
}

class Feast {
  final String name;

  /// Что произошло — две-три фразы без толкований.
  final String summary;

  /// Отрывок, где событие описано. Пусто — значит, события в Писании нет.
  final String? bookId;
  final int? chapter;
  final int? verse;
  final int? verseEnd;

  const Feast({
    required this.name,
    required this.summary,
    this.bookId,
    this.chapter,
    this.verse,
    this.verseEnd,
  });

  bool get inScripture => bookId != null;

  String? get reference {
    if (bookId == null) return null;
    final tail = verseEnd == null ? '$verse' : '$verse–$verseEnd';
    return verse == null ? '$chapter' : '$chapter:$tail';
  }
}

/// Праздник, привязанный к дате: либо к числу месяца, либо к смещению от Пасхи.
class _Rule {
  final Feast feast;
  final Set<ChurchTradition> traditions;
  final int? month;
  final int? day;
  final int? fromEaster;

  const _Rule({
    required this.feast,
    required this.traditions,
    this.month,
    this.day,
    this.fromEaster,
  });
}

const _west = {
  ChurchTradition.catholic,
  ChurchTradition.protestant,
  ChurchTradition.none,
};
const _all = {
  ChurchTradition.orthodox,
  ChurchTradition.catholic,
  ChurchTradition.protestant,
  ChurchTradition.none,
};

const _easter = Feast(
  name: 'Пасха. Воскресение Христово',
  summary: 'Женщины пришли ко гробу на рассвете первого дня недели и нашли '
      'его пустым; ангел сказал им, что Христос воскрес.',
  bookId: 'MAT',
  chapter: 28,
  verse: 1,
  verseEnd: 10,
);

const _palm = Feast(
  name: 'Вход Господень в Иерусалим',
  summary: 'Иисус въехал в Иерусалим на молодом осле, и народ встречал Его '
      'пальмовыми ветвями.',
  bookId: 'MAT',
  chapter: 21,
  verse: 1,
  verseEnd: 11,
);

const _goodFriday = Feast(
  name: 'Страстная пятница',
  summary: 'День распятия и погребения Христа.',
  bookId: 'JHN',
  chapter: 19,
  verse: 16,
  verseEnd: 42,
);

const _ascension = Feast(
  name: 'Вознесение Господне',
  summary: 'На сороковой день после воскресения Христос вознёсся на глазах у '
      'учеников.',
  bookId: 'ACT',
  chapter: 1,
  verse: 1,
  verseEnd: 11,
);

const _pentecost = Feast(
  name: 'Пятидесятница. Троица',
  summary: 'На пятидесятый день на апостолов сошёл Святой Дух, и они начали '
      'говорить на разных языках. С этого дня отсчитывают начало Церкви.',
  bookId: 'ACT',
  chapter: 2,
  verse: 1,
  verseEnd: 13,
);

const _nativity = Feast(
  name: 'Рождество Христово',
  summary: 'Рождение Иисуса в Вифлееме; первыми о нём узнали пастухи.',
  bookId: 'LUK',
  chapter: 2,
  verse: 1,
  verseEnd: 20,
);

const _theophany = Feast(
  name: 'Крещение Господне. Богоявление',
  summary: 'Иоанн крестил Иисуса в Иордане, и был голос с неба: «Сей есть Сын '
      'Мой возлюбленный».',
  bookId: 'MAT',
  chapter: 3,
  verse: 13,
  verseEnd: 17,
);

const _meeting = Feast(
  name: 'Сретение Господне',
  summary: 'Младенца принесли в храм, где встретили Его Симеон и пророчица '
      'Анна.',
  bookId: 'LUK',
  chapter: 2,
  verse: 22,
  verseEnd: 38,
);

const _annunciation = Feast(
  name: 'Благовещение',
  summary: 'Ангел возвестил Марии, что у неё родится Сын.',
  bookId: 'LUK',
  chapter: 1,
  verse: 26,
  verseEnd: 38,
);

const _transfiguration = Feast(
  name: 'Преображение Господне',
  summary: 'На горе Иисус преобразился перед тремя учениками, и явились '
      'Моисей и Илия.',
  bookId: 'MAT',
  chapter: 17,
  verse: 1,
  verseEnd: 9,
);

const _dormition = Feast(
  name: 'Успение Богородицы',
  summary: 'Кончина Девы Марии. В Библии это событие не описано — праздник '
      'опирается на церковное предание.',
);

const _nativityOfMary = Feast(
  name: 'Рождество Богородицы',
  summary: 'Рождение Девы Марии. В Библии не описано — предание.',
);

const _crossExaltation = Feast(
  name: 'Воздвижение Креста Господня',
  summary: 'Обретение Креста в Иерусалиме в IV веке. Событие церковной '
      'истории, а не библейское.',
);

const _presentationOfMary = Feast(
  name: 'Введение во храм Богородицы',
  summary: 'Праздник по преданию о детстве Девы Марии. В Библии не описан.',
);

const _protection = Feast(
  name: 'Покров Богородицы',
  summary: 'Праздник по видению во Влахернском храме. В Библии не описан.',
);

const _allSaints = Feast(
  name: 'День всех святых',
  summary: 'Общая память всех святых.',
);

const _reformation = Feast(
  name: 'День Реформации',
  summary: '31 октября 1517 года Мартин Лютер обнародовал 95 тезисов — с этого '
      'дня отсчитывают начало Реформации.',
);

const _immaculate = Feast(
  name: 'Непорочное зачатие Девы Марии',
  summary: 'Католический догмат, принятый в 1854 году. В Библии не описан.',
);

const _johnBaptist = Feast(
  name: 'Рождество Иоанна Предтечи',
  summary: 'Рождение Иоанна, предшественника Христа.',
  bookId: 'LUK',
  chapter: 1,
  verse: 57,
  verseEnd: 66,
);

const _peterPaul = Feast(
  name: 'Апостолов Петра и Павла',
  summary: 'Память двух главных апостолов; по преданию оба приняли смерть в '
      'Риме.',
);

/// Календарь целиком. Православные даты даны по гражданскому счёту: это
/// юлианские числа плюс 13 дней — так они и печатаются в русских календарях.
const _rules = <_Rule>[
  // ── Подвижные: считаются от Пасхи ──
  _Rule(feast: _easter, traditions: _all, fromEaster: 0),
  _Rule(feast: _palm, traditions: _all, fromEaster: -7),
  _Rule(feast: _goodFriday, traditions: _all, fromEaster: -2),
  _Rule(feast: _ascension, traditions: _all, fromEaster: 39),
  _Rule(feast: _pentecost, traditions: _all, fromEaster: 49),

  // ── Неподвижные, православные ──
  _Rule(
      feast: _nativity,
      traditions: {ChurchTradition.orthodox},
      month: 1,
      day: 7),
  _Rule(
      feast: _theophany,
      traditions: {ChurchTradition.orthodox},
      month: 1,
      day: 19),
  _Rule(
      feast: _meeting,
      traditions: {ChurchTradition.orthodox},
      month: 2,
      day: 15),
  _Rule(
      feast: _annunciation,
      traditions: {ChurchTradition.orthodox},
      month: 4,
      day: 7),
  _Rule(
      feast: _johnBaptist,
      traditions: {ChurchTradition.orthodox},
      month: 7,
      day: 7),
  _Rule(
      feast: _peterPaul,
      traditions: {ChurchTradition.orthodox},
      month: 7,
      day: 12),
  _Rule(
      feast: _transfiguration,
      traditions: {ChurchTradition.orthodox},
      month: 8,
      day: 19),
  _Rule(
      feast: _dormition,
      traditions: {ChurchTradition.orthodox},
      month: 8,
      day: 28),
  _Rule(
      feast: _nativityOfMary,
      traditions: {ChurchTradition.orthodox},
      month: 9,
      day: 21),
  _Rule(
      feast: _crossExaltation,
      traditions: {ChurchTradition.orthodox},
      month: 9,
      day: 27),
  _Rule(
      feast: _protection,
      traditions: {ChurchTradition.orthodox},
      month: 10,
      day: 14),
  _Rule(
      feast: _presentationOfMary,
      traditions: {ChurchTradition.orthodox},
      month: 12,
      day: 4),

  // ── Неподвижные, западные ──
  _Rule(feast: _nativity, traditions: _west, month: 12, day: 25),
  _Rule(feast: _theophany, traditions: _west, month: 1, day: 6),
  _Rule(
      feast: _meeting,
      traditions: {ChurchTradition.catholic},
      month: 2,
      day: 2),
  _Rule(
      feast: _annunciation,
      traditions: {ChurchTradition.catholic},
      month: 3,
      day: 25),
  _Rule(feast: _johnBaptist, traditions: _west, month: 6, day: 24),
  _Rule(
      feast: _peterPaul,
      traditions: {ChurchTradition.catholic},
      month: 6,
      day: 29),
  _Rule(
      feast: _transfiguration,
      traditions: {ChurchTradition.catholic},
      month: 8,
      day: 6),
  _Rule(
      feast: _dormition,
      traditions: {ChurchTradition.catholic},
      month: 8,
      day: 15),
  _Rule(
      feast: _allSaints,
      traditions: {ChurchTradition.catholic},
      month: 11,
      day: 1),
  _Rule(
      feast: _immaculate,
      traditions: {ChurchTradition.catholic},
      month: 12,
      day: 8),
  _Rule(
      feast: _reformation,
      traditions: {ChurchTradition.protestant},
      month: 10,
      day: 31),
];

/// Пасха по григорианскому счёту — алгоритм Бутчера.
DateTime gregorianEaster(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(year, month, day);
}

/// Православная Пасха: считается по юлианскому счёту и переводится в
/// гражданский календарь. Сдвиг в 13 дней верен для 1900–2099 годов.
DateTime orthodoxEaster(int year) {
  final a = year % 4;
  final b = year % 7;
  final c = year % 19;
  final d = (19 * c + 15) % 30;
  final e = (2 * a + 4 * b - d + 34) % 7;
  final month = (d + e + 114) ~/ 31;
  final day = ((d + e + 114) % 31) + 1;
  // Дата получилась юлианская — переносим в григорианский календарь.
  // Дни прибавляются к числу, а не длительностью: сутки перехода на летнее
  // время короче 24 часов, и Duration сдвинула бы дату на день назад.
  return DateTime(year, month, day + 13);
}

DateTime easterFor(int year, ChurchTradition tradition) =>
    tradition == ChurchTradition.orthodox
        ? orthodoxEaster(year)
        : gregorianEaster(year);

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Праздники этого дня.
List<Feast> feastsOn(DateTime date, ChurchTradition tradition) {
  final day = _dayOnly(date);
  final easter = easterFor(day.year, tradition);
  final out = <Feast>[];

  for (final rule in _rules) {
    if (!rule.traditions.contains(tradition)) continue;
    if (rule.fromEaster != null) {
      final date =
          DateTime(easter.year, easter.month, easter.day + rule.fromEaster!);
      if (date == day) {
        out.add(rule.feast);
      }
    } else if (rule.month == day.month && rule.day == day.day) {
      out.add(rule.feast);
    }
  }
  return out;
}

/// Ближайший праздник после этого дня.
({Feast feast, DateTime date})? nextFeast(
    DateTime from, ChurchTradition tradition) {
  final start = _dayOnly(from);
  for (var i = 1; i <= 400; i++) {
    final day = DateTime(start.year, start.month, start.day + i);
    final found = feastsOn(day, tradition);
    if (found.isNotEmpty) return (feast: found.first, date: day);
  }
  return null;
}

/// Числа месяца, на которые приходятся праздники, — для сетки календаря.
Set<int> feastDaysOfMonth(int year, int month, ChurchTradition tradition) {
  final days = <int>{};
  final last = DateTime(year, month + 1, 0).day;
  for (var d = 1; d <= last; d++) {
    if (feastsOn(DateTime(year, month, d), tradition).isNotEmpty) days.add(d);
  }
  return days;
}

// ── Русские названия дат ──────────────────────────────────────────────────
//
// Своими руками, без пакета intl: тринадцать строк не стоят зависимости с
// загрузкой локали при старте.

const _monthsGenitive = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

const _monthsNominative = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
];

const _weekdays = [
  'Понедельник', 'Вторник', 'Среда', 'Четверг',
  'Пятница', 'Суббота', 'Воскресенье',
];

const weekdayLetters = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

/// «Суббота, 16 августа»
String formatDayTitle(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_monthsGenitive[d.month - 1]}';

/// «16 августа»
String formatDayShort(DateTime d) =>
    '${d.day} ${_monthsGenitive[d.month - 1]}';

String monthName(int month) => _monthsNominative[month - 1];
