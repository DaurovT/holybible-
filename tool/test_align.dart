// Проверка качества привязки русских имён.
// Запуск: dart run tool/test_align.dart
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

import 'align_names.dart';
import 'tipnr_parser.dart';

/// Контрольные пары. Проверяем префиксный ключ, а не словоформу — имя в
/// тексте стоит в любом падеже.
const expected = {
  'Aaron': 'Аарон',
  'Moses': 'Моисей',
  'David': 'Давид',
  'Nicodemus': 'Никодим',
  'Jerusalem': 'Иерусалим',
  'Capernaum': 'Капернаум',
  'Abraham': 'Авраам',
  'Solomon': 'Соломон',
  'Peter': 'Пётр',
  'Paul': 'Павел',
  'Pilate': 'Пилат',
  'Elijah': 'Илия',
  'Isaiah': 'Исаия',
  'Samson': 'Самсон',
  'Egypt': 'Египет',
  'Babylon': 'Вавилон',
  'Joseph': 'Иосиф',
  'Mary': 'Мария',
  'Bethlehem': 'Вифлеем',
  'Galilee': 'Галилея',
};

void main() {
  final db = sqlite3.open('assets/db/bible.db');

  final verses = <int, String>{};
  for (final r
      in db.select("SELECT vkey, text FROM verses WHERE translation_id='syn'")) {
    verses[r['vkey'] as int] = r['text'] as String;
  }
  final df = buildKeyFrequency(verses.values);
  stdout.writeln('стихов ${verses.length}, различных префиксов ${df.length}\n');

  final entities = parseTipnr(File('data/raw/tipnr.txt').readAsStringSync());

  var ok = 0, bad = 0;
  for (final want in expected.entries) {
    // Из тёзок берём самого упоминаемого — именно его ждёт читатель,
    // набирая имя. Раньше тест брал первого по алфавиту и ловил
    // второстепенного однофамильца.
    final same =
        entities.where((x) => x.id.startsWith('${want.key}@')).toList();
    if (same.isEmpty) {
      stdout.writeln('${want.key}: сущность не найдена');
      continue;
    }
    same.sort((a, b) => b.allRefs.length.compareTo(a.allRefs.length));
    final e = same.first;

    final mine = {
      for (final k in e.allRefs)
        if (verses.containsKey(k)) k: verses[k]!
    };
    final cands =
        findNames(verses: mine, df: df, englishName: e.englishName);
    final wantKey = nameKey(want.value);
    final hit = cands.isNotEmpty && cands.first.key == wantKey;
    hit ? ok++ : bad++;
    stdout.writeln('${hit ? "✓" : "✗"} ${want.key.padRight(11)} '
        'ждём «${want.value}» [$wantKey]  ${e.id}, стихов ${mine.length}'
        '${same.length > 1 ? " (тёзок ${same.length})" : ""}');
    stdout.writeln('    ${cands.join('  ')}');
    if (cands.isNotEmpty) {
      stdout.writeln('    формы: ${cands.first.forms.take(8).join(', ')}'
          '   спанов: ${cands.first.occurrences.length}');
    }
  }
  stdout.writeln('\nточность на контрольной выборке: $ok из ${ok + bad}');
  db.dispose();
}
