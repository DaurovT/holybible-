/// Добавляет в bible.db слой перекрёстных ссылок — «параллельные места».
///
/// Источник: OpenBible.info (CC BY), производная от «Сокровищницы библейских
/// знаний». Это ровно тот пункт задания — «связь с другими местами Библии», —
/// который выглядел задачей для ИИ, хотя данные лежат в открытом доступе и
/// работают офлайн.
///
/// Запуск: dart run tool/build_cross_refs.dart
/// Порядок сборки: build_bible_db → build_entities → build_cross_refs.
/// Пересборка bible.db стирает этот слой, его надо повторить.
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'canon.dart';

/// Сокращения OSIS из выгрузки OpenBible → коды USFM.
const _osisToUsfm = <String, String>{
  'Gen': 'GEN', 'Exod': 'EXO', 'Lev': 'LEV', 'Num': 'NUM', 'Deut': 'DEU',
  'Josh': 'JOS', 'Judg': 'JDG', 'Ruth': 'RUT', '1Sam': '1SA', '2Sam': '2SA',
  '1Kgs': '1KI', '2Kgs': '2KI', '1Chr': '1CH', '2Chr': '2CH', 'Ezra': 'EZR',
  'Neh': 'NEH', 'Esth': 'EST', 'Job': 'JOB', 'Ps': 'PSA', 'Prov': 'PRO',
  'Eccl': 'ECC', 'Song': 'SNG', 'Isa': 'ISA', 'Jer': 'JER', 'Lam': 'LAM',
  'Ezek': 'EZK', 'Dan': 'DAN', 'Hos': 'HOS', 'Joel': 'JOL', 'Amos': 'AMO',
  'Obad': 'OBA', 'Jonah': 'JON', 'Mic': 'MIC', 'Nah': 'NAM', 'Hab': 'HAB',
  'Zeph': 'ZEP', 'Hag': 'HAG', 'Zech': 'ZEC', 'Mal': 'MAL',
  'Matt': 'MAT', 'Mark': 'MRK', 'Luke': 'LUK', 'John': 'JHN', 'Acts': 'ACT',
  'Rom': 'ROM', '1Cor': '1CO', '2Cor': '2CO', 'Gal': 'GAL', 'Eph': 'EPH',
  'Phil': 'PHP', 'Col': 'COL', '1Thess': '1TH', '2Thess': '2TH',
  '1Tim': '1TI', '2Tim': '2TI', 'Titus': 'TIT', 'Phlm': 'PHM', 'Heb': 'HEB',
  'Jas': 'JAS', '1Pet': '1PE', '2Pet': '2PE', '1John': '1JN', '2John': '2JN',
  '3John': '3JN', 'Jude': 'JUD', 'Rev': 'REV',
};

const schema = '''
DROP TABLE IF EXISTS cross_refs;
CREATE TABLE cross_refs (
  from_vkey INTEGER NOT NULL,
  to_vkey   INTEGER NOT NULL,
  span      INTEGER NOT NULL,  -- сколько стихов ещё захватывает ссылка
  votes     INTEGER NOT NULL
);
''';

/// «Gen.1.1» → ключ стиха. null, если книга неизвестна или формат сбит.
int? _parse(String ref) {
  final parts = ref.split('.');
  if (parts.length != 3) return null;
  final book = _osisToUsfm[parts[0]];
  final chapter = int.tryParse(parts[1]);
  final verse = int.tryParse(parts[2]);
  if (book == null || chapter == null || verse == null) return null;
  return verseKey(book, chapter, verse);
}

void main() {
  final root = Directory.current.path;
  final source = File('$root/data/raw/cross_refs/cross_references.txt');
  if (!source.existsSync()) {
    stderr.writeln('нет ${source.path}\n'
        'скачать: https://a.openbible.info/data/cross-references.zip');
    exit(1);
  }

  final db = sqlite3.open('$root/assets/db/bible.db');
  db.execute('PRAGMA journal_mode = OFF');
  db.execute(schema);

  final insert = db.prepare(
      'INSERT INTO cross_refs(from_vkey,to_vkey,span,votes) VALUES(?,?,?,?)');

  var total = 0, skippedVotes = 0, skippedRefs = 0, ranges = 0;
  db.execute('BEGIN');

  for (final line in source.readAsLinesSync().skip(1)) {
    if (line.trim().isEmpty) continue;
    final cols = line.split('\t');
    if (cols.length < 3) continue;

    // Отрицательные голоса — связи, которые читатели отклонили.
    final votes = int.tryParse(cols[2]) ?? 0;
    if (votes <= 0) {
      skippedVotes++;
      continue;
    }

    final from = _parse(cols[0]);
    if (from == null) {
      skippedRefs++;
      continue;
    }

    // Цель бывает диапазоном: «Rom.1.19-Rom.1.20».
    final target = cols[1].split('-');
    final start = _parse(target.first);
    if (start == null) {
      skippedRefs++;
      continue;
    }
    var span = 0;
    if (target.length > 1) {
      final end = _parse(target.last);
      if (end != null && end > start && end - start < 200) {
        span = end - start;
        ranges++;
      }
    }

    insert.execute([from, start, span, votes]);
    total++;
  }

  db.execute('COMMIT');
  insert.dispose();

  // Индекс только по источнику: спрашивают всегда «что параллельно этому стиху».
  db.execute('CREATE INDEX idx_cross_from ON cross_refs(from_vkey, votes DESC)');

  final verses =
      db.select('SELECT COUNT(DISTINCT from_vkey) c FROM cross_refs').first['c'];
  final sample = db.select('''
    SELECT to_vkey, span, votes FROM cross_refs
    WHERE from_vkey = ? ORDER BY votes DESC LIMIT 3
  ''', [verseKey('JHN', 3, 16)]);

  stdout.writeln('── перекрёстные ссылки ──');
  stdout.writeln('связей:        $total');
  stdout.writeln('из них диапазонов: $ranges');
  stdout.writeln('стихов со ссылками: $verses');
  stdout.writeln('отклонённых голосованием: $skippedVotes');
  stdout.writeln('нераспознанных ссылок:    $skippedRefs');
  stdout.writeln('\nИн 3:16 — самые сильные связи:');
  for (final r in sample) {
    stdout.writeln('  ключ ${r['to_vkey']} (+${r['span']}), голосов ${r['votes']}');
  }

  db.execute('VACUUM');
  db.dispose();

  final mb = (File('$root/assets/db/bible.db').lengthSync() / 1024 / 1024)
      .toStringAsFixed(1);
  stdout.writeln('\nbible.db — $mb МБ');
}
