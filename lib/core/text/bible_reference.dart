/// Короткие имена книг и разбор ссылок вида «Ин 3:16».
///
/// В Синодальном USFM нет сокращений: и `short`, и `abbrev` там равны полному
/// названию («Первое послание к Коринфянам»). Поэтому таблица сокращений живёт
/// в приложении и ключуется кодом книги, общим для всех переводов.
library;

import '../../data/models.dart';

/// Общепринятые русские сокращения книг.
const russianAbbrev = <String, String>{
  'GEN': 'Быт', 'EXO': 'Исх', 'LEV': 'Лев', 'NUM': 'Числ', 'DEU': 'Втор',
  'JOS': 'Нав', 'JDG': 'Суд', 'RUT': 'Руф', '1SA': '1Цар', '2SA': '2Цар',
  '1KI': '3Цар', '2KI': '4Цар', '1CH': '1Пар', '2CH': '2Пар', 'EZR': 'Езд',
  'NEH': 'Неем', 'EST': 'Есф', 'JOB': 'Иов', 'PSA': 'Пс', 'PRO': 'Притч',
  'ECC': 'Еккл', 'SNG': 'Песн', 'ISA': 'Ис', 'JER': 'Иер', 'LAM': 'Плач',
  'EZK': 'Иез', 'DAN': 'Дан', 'HOS': 'Ос', 'JOL': 'Иоил', 'AMO': 'Ам',
  'OBA': 'Авд', 'JON': 'Иона', 'MIC': 'Мих', 'NAM': 'Наум', 'HAB': 'Авв',
  'ZEP': 'Соф', 'HAG': 'Агг', 'ZEC': 'Зах', 'MAL': 'Мал',
  'MAT': 'Мф', 'MRK': 'Мк', 'LUK': 'Лк', 'JHN': 'Ин', 'ACT': 'Деян',
  'ROM': 'Рим', '1CO': '1Кор', '2CO': '2Кор', 'GAL': 'Гал', 'EPH': 'Еф',
  'PHP': 'Флп', 'COL': 'Кол', '1TH': '1Фес', '2TH': '2Фес', '1TI': '1Тим',
  '2TI': '2Тим', 'TIT': 'Тит', 'PHM': 'Флм', 'HEB': 'Евр', 'JAS': 'Иак',
  '1PE': '1Пет', '2PE': '2Пет', '1JN': '1Ин', '2JN': '2Ин', '3JN': '3Ин',
  'JUD': 'Иуд', 'REV': 'Откр',
};

final _cyrillic = RegExp('[а-яА-ЯёЁ]');

/// Короткая подпись книги для заголовков и ссылок.
///
/// У английских переводов сокращение лежит в самой базе («Jhn»). В русском
/// его нет: там `abbrev` — это либо полное название, либо «Матфея», тогда как
/// привычная форма ссылки «Мф». Поэтому для кириллицы всегда берём таблицу —
/// иначе в одной сетке соседствуют «Матфея» и «1Кор».
String bookLabel(Book book) {
  if (_cyrillic.hasMatch(book.abbrev)) {
    return russianAbbrev[book.id] ?? book.abbrev;
  }
  return book.abbrev;
}

/// Приводит название к виду, по которому сравниваются варианты написания:
/// «1 Кор.» и «1кор» должны совпасть.
String normalizeName(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().replaceAll('ё', 'е').split('')) {
    if (RegExp(r'[a-zа-я0-9]').hasMatch(ch)) b.write(ch);
  }
  return b.toString();
}

/// Найденная ссылка. [chapter] и [verse] могут отсутствовать: «Ин» — это
/// просто книга, «Ин 3» — глава.
class ReferenceMatch {
  final Book book;
  final int? chapter;
  final int? verse;

  const ReferenceMatch(this.book, this.chapter, this.verse);
}

class _Candidate {
  final Book book;
  final int rank;
  const _Candidate(this.book, this.rank);
}

/// Разбирает пользовательский ввод: «Ин 3:16», «1 Кор 13», «пс22», «Бытие».
///
/// Возвращает подходящие книги в порядке убывания уверенности — вместо того
/// чтобы угадывать одну: «Иоанна» это и Евангелие, и три послания, и
/// Откровение.
List<ReferenceMatch> parseReference(String input, List<Book> books) {
  final raw = input.trim();
  if (raw.isEmpty) return const [];

  // Ввод режем на «название» и «числа»: цифра в начале — часть названия
  // («1 Кор»), цифра после букв — уже глава.
  final m = RegExp(
    r'^\s*([1-4]\s*)?([^\d]+?)\s*(\d+)?\s*(?:[:.,]\s*(\d+))?\s*$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (m == null) return const [];

  final name = normalizeName('${m.group(1) ?? ''}${m.group(2) ?? ''}');
  if (name.isEmpty) return const [];
  final chapter = int.tryParse(m.group(3) ?? '');
  final verse = int.tryParse(m.group(4) ?? '');

  final found = <_Candidate>[];
  for (final b in books) {
    final variants = <String>{
      normalizeName(russianAbbrev[b.id] ?? ''),
      normalizeName(b.abbrev),
      normalizeName(b.shortName),
      normalizeName(b.name),
      b.id.toLowerCase(),
    }..removeWhere((v) => v.isEmpty);

    int? rank;
    for (final v in variants) {
      if (v == name) {
        rank = 0;
      } else if (v.startsWith(name)) {
        rank = (rank == null || rank > 1) ? 1 : rank;
      } else if (v.contains(name)) {
        rank = (rank == null || rank > 2) ? 2 : rank;
      }
    }
    if (rank != null) found.add(_Candidate(b, rank));
  }

  found.sort((a, b) {
    final byRank = a.rank.compareTo(b.rank);
    if (byRank != 0) return byRank;
    final byLength = a.book.name.length.compareTo(b.book.name.length);
    return byLength != 0 ? byLength : a.book.order.compareTo(b.book.order);
  });

  return [
    for (final c in found)
      ReferenceMatch(c.book, chapter?.clamp(1, c.book.chapters), verse)
  ];
}
