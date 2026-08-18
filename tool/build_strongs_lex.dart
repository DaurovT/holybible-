/// Добавляет в strongs.db словарь значений — сами статьи Стронга.
///
/// До сих пор в базе лежали только номера при словах (1 032 755 привязок), а
/// что эти номера значат, приложение не знало. Источник — оцифровка
/// openscriptures: текст Стронга 1890/1894 годов в общественном достоянии,
/// сама оцифровка под CC BY-SA, поэтому в карточке слова стоит ссылка на неё.
///
/// Запуск: dart run tool/build_strongs_lex.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const schema = '''
DROP TABLE IF EXISTS strongs_lex;
CREATE TABLE strongs_lex (
  code       TEXT PRIMARY KEY,
  lemma      TEXT,
  translit   TEXT,
  pron       TEXT,
  definition TEXT,
  derivation TEXT,
  kjv_def    TEXT
);
''';

/// Файлы словарей — это JavaScript с одним объектом внутри. Вырезаем сам
/// объект: тянуть ради этого движок JS незачем.
Map<String, dynamic> _load(File file) {
  final src = file.readAsStringSync();
  final start = src.indexOf('{', src.indexOf('='));
  final end = src.lastIndexOf('}');
  return jsonDecode(src.substring(start, end + 1)) as Map<String, dynamic>;
}

/// «H430» → «H0430»: форма, в которой номера записаны в разметке текста.
String? _padded(String code) {
  final m = RegExp(r'^([GH])(\d+)$').firstMatch(code);
  if (m == null) return null;
  return '${m.group(1)}${m.group(2)!.padLeft(4, '0')}';
}

String? _text(Map<String, dynamic> e, String key) {
  final v = e[key];
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

void main() {
  final root = Directory.current.path;
  final greek = File('$root/data/raw/strongs/greek.js');
  final hebrew = File('$root/data/raw/strongs/hebrew.js');
  if (!greek.existsSync() || !hebrew.existsSync()) {
    stderr.writeln('нет словарей в data/raw/strongs/\n'
        'скачать: https://github.com/openscriptures/strongs');
    exit(1);
  }

  final db = sqlite3.open('$root/assets/db/strongs.db');
  db.execute('PRAGMA journal_mode = OFF');
  db.execute(schema);

  final insert = db.prepare('''
    INSERT OR REPLACE INTO strongs_lex
      (code,lemma,translit,pron,definition,derivation,kjv_def)
    VALUES(?,?,?,?,?,?,?)
  ''');

  var total = 0, aliases = 0;
  db.execute('BEGIN');
  for (final file in [greek, hebrew]) {
    for (final entry in _load(file).entries) {
      final e = entry.value as Map<String, dynamic>;
      final row = [
        _text(e, 'lemma'),
        // У греческого поле называется translit, у еврейского — xlit.
        _text(e, 'translit') ?? _text(e, 'xlit'),
        _text(e, 'pron'),
        _text(e, 'strongs_def'),
        _text(e, 'derivation'),
        _text(e, 'kjv_def'),
      ];
      insert.execute([entry.key, ...row]);
      total++;

      // В разметке текста номера записаны с ведущими нулями («H0430»), а в
      // словаре — без них («H430»). Кладём оба написания, иначе у 56 323 слов
      // статья не находится.
      final padded = _padded(entry.key);
      if (padded != null && padded != entry.key) {
        insert.execute([padded, ...row]);
        aliases++;
      }
    }
  }
  db.execute('COMMIT');
  insert.dispose();

  final linked = db.select('''
    SELECT COUNT(DISTINCT s.strong) c FROM strongs s
    JOIN strongs_lex l ON l.code = s.strong
  ''').first['c'];
  final orphans = db.select('''
    SELECT COUNT(DISTINCT s.strong) c FROM strongs s
    LEFT JOIN strongs_lex l ON l.code = s.strong
    WHERE l.code IS NULL
  ''').first['c'];

  stdout.writeln('── словарь Стронга ──');
  stdout.writeln('статей:               $total '
      '(плюс $aliases написаний с ведущими нулями)');
  stdout.writeln('номеров из текста, у которых есть статья: $linked');
  stdout.writeln('номеров без статьи:   $orphans');

  for (final code in ['G26', 'H157', 'G3056']) {
    final r = db.select(
        'SELECT lemma, translit, definition FROM strongs_lex WHERE code = ?',
        [code]);
    if (r.isNotEmpty) {
      stdout.writeln('  $code  ${r.first['lemma']} '
          '(${r.first['translit']}) — ${r.first['definition']}');
    }
  }

  db.execute('VACUUM');
  db.dispose();

  final mb = (File('$root/assets/db/strongs.db').lengthSync() / 1024 / 1024)
      .toStringAsFixed(1);
  stdout.writeln('\nstrongs.db — $mb МБ');
}
