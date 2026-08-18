/// Канонический порядок книг и служебные ключи.
library;

/// 66 книг протестантского канона в USFM-кодировке, в каноническом порядке.
/// Порядок берём отсюда, а не из имён файлов: нумерация в разных изданиях
/// eBible расходится, а порядок книг — нет.
const canonicalBooks = <String>[
  // Ветхий Завет
  'GEN', 'EXO', 'LEV', 'NUM', 'DEU', 'JOS', 'JDG', 'RUT', '1SA', '2SA',
  '1KI', '2KI', '1CH', '2CH', 'EZR', 'NEH', 'EST', 'JOB', 'PSA', 'PRO',
  'ECC', 'SNG', 'ISA', 'JER', 'LAM', 'EZK', 'DAN', 'HOS', 'JOL', 'AMO',
  'OBA', 'JON', 'MIC', 'NAM', 'HAB', 'ZEP', 'HAG', 'ZEC', 'MAL',
  // Новый Завет
  'MAT', 'MRK', 'LUK', 'JHN', 'ACT', 'ROM', '1CO', '2CO', 'GAL', 'EPH',
  'PHP', 'COL', '1TH', '2TH', '1TI', '2TI', 'TIT', 'PHM', 'HEB', 'JAS',
  '1PE', '2PE', '1JN', '2JN', '3JN', 'JUD', 'REV',
];

/// Индекс книги в каноне, начиная с 1. `null` для неканонических файлов
/// (второканонические книги в некоторых изданиях eBible).
int? bookOrder(String id) {
  final i = canonicalBooks.indexOf(id.toUpperCase());
  return i < 0 ? null : i + 1;
}

bool isNewTestament(String id) => (bookOrder(id) ?? 0) >= 40;

/// Единый числовой ключ стиха, общий для всех переводов.
///
/// Нужен для параллельного режима и для привязки сущностей: сравнивать тройки
/// (книга, глава, стих) в каждом запросе дороже и провоцирует ошибки.
int verseKey(String bookId, int chapter, int verse) {
  final ord = bookOrder(bookId) ?? 0;
  return ord * 1000000 + chapter * 1000 + verse;
}

/// Сокращения TIPNR (Exo, 1Ch, Mat…) → коды USFM.
const tipnrToUsfm = <String, String>{
  'Gen': 'GEN', 'Exo': 'EXO', 'Lev': 'LEV', 'Num': 'NUM', 'Deu': 'DEU',
  'Jos': 'JOS', 'Jdg': 'JDG', 'Rut': 'RUT', '1Sa': '1SA', '2Sa': '2SA',
  '1Ki': '1KI', '2Ki': '2KI', '1Ch': '1CH', '2Ch': '2CH', 'Ezr': 'EZR',
  'Neh': 'NEH', 'Est': 'EST', 'Job': 'JOB', 'Psa': 'PSA', 'Pro': 'PRO',
  'Ecc': 'ECC', 'Sng': 'SNG', 'Sos': 'SNG', 'Isa': 'ISA', 'Jer': 'JER',
  'Lam': 'LAM', 'Ezk': 'EZK', 'Eze': 'EZK', 'Dan': 'DAN', 'Hos': 'HOS',
  'Jol': 'JOL', 'Joe': 'JOL', 'Amo': 'AMO', 'Oba': 'OBA', 'Jon': 'JON',
  'Mic': 'MIC', 'Nam': 'NAM', 'Nah': 'NAM', 'Hab': 'HAB', 'Zep': 'ZEP',
  'Hag': 'HAG', 'Zec': 'ZEC', 'Mal': 'MAL',
  'Mat': 'MAT', 'Mrk': 'MRK', 'Mar': 'MRK', 'Luk': 'LUK', 'Jhn': 'JHN',
  'Joh': 'JHN', 'Act': 'ACT', 'Rom': 'ROM', '1Co': '1CO', '2Co': '2CO',
  'Gal': 'GAL', 'Eph': 'EPH', 'Php': 'PHP', 'Phi': 'PHP', 'Col': 'COL',
  '1Th': '1TH', '2Th': '2TH', '1Ti': '1TI', '2Ti': '2TI', 'Tit': 'TIT',
  'Phm': 'PHM', 'Heb': 'HEB', 'Jas': 'JAS', 'Jam': 'JAS', '1Pe': '1PE',
  '2Pe': '2PE', '1Jn': '1JN', '2Jn': '2JN', '3Jn': '3JN', 'Jud': 'JUD',
  'Jde': 'JUD', 'Rev': 'REV',
};
