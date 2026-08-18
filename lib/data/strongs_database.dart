/// Слова оригинала: номера Стронга при словах и статьи словаря.
///
/// Живёт отдельным файлом и открывается лениво — только когда о нём
/// спрашивают. В базе 1 032 755 привязок, копировать 36 МБ при каждом запуске
/// ради функции, которую откроют не все, незачем.
///
/// Разметка есть только у английских переводов (KJV и WEB): в Синодальном
/// USFM её нет, так устроен исходник. Поэтому слово оригинала показывается
/// через параллельный английский стих — и в интерфейсе это сказано прямо.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'bible_database.dart' show unpackAsset;

/// Поднимать при пересборке assets/db/strongs.db.
const strongsDbVersion = 2;

/// Слово английского стиха с номером Стронга и статьёй словаря.
class StrongWord {
  /// Границы слова в тексте английского стиха.
  final int start;
  final int end;

  final String code;
  final String? lemma;
  final String? translit;
  final String? pron;
  final String? definition;
  final String? derivation;

  const StrongWord({
    required this.start,
    required this.end,
    required this.code,
    this.lemma,
    this.translit,
    this.pron,
    this.definition,
    this.derivation,
  });

  bool get isHebrew => code.startsWith('H');
}

class StrongsDatabase {
  StrongsDatabase._(this._db);

  final Database _db;

  static Future<StrongsDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'strongs_v$strongsDbVersion.db'));

    if (!file.existsSync()) {
      for (final f in dir.listSync()) {
        if (f is File && p.basename(f.path).startsWith('strongs_v')) {
          f.deleteSync();
        }
      }
      await unpackAsset('assets/db/strongs.db.gz', file);
    }

    return StrongsDatabase._(sqlite3.open(file.path, mode: OpenMode.readOnly));
  }

  void dispose() => _db.dispose();

  /// Слова стиха по внутреннему идентификатору стиха из bible.db.
  List<StrongWord> wordsFor(int verseId) => [
        for (final r in _db.select('''
          SELECT s.start, s.finish, s.strong,
                 l.lemma, l.translit, l.pron, l.definition, l.derivation
          FROM strongs s
          LEFT JOIN strongs_lex l ON l.code = s.strong
          WHERE s.verse_id = ?
          ORDER BY s.start
        ''', [verseId]))
          StrongWord(
            start: r['start'] as int,
            end: r['finish'] as int,
            code: r['strong'] as String,
            lemma: r['lemma'] as String?,
            translit: r['translit'] as String?,
            pron: r['pron'] as String?,
            definition: r['definition'] as String?,
            derivation: r['derivation'] as String?,
          )
      ];

  /// Статья по номеру — для карточки сущности, где номер уже известен.
  StrongWord? entry(String code) {
    final r = _db.select(
        'SELECT lemma, translit, pron, definition, derivation '
        'FROM strongs_lex WHERE code = ?',
        [code]);
    if (r.isEmpty) return null;
    final row = r.first;
    return StrongWord(
      start: 0,
      end: 0,
      code: code,
      lemma: row['lemma'] as String?,
      translit: row['translit'] as String?,
      pron: row['pron'] as String?,
      definition: row['definition'] as String?,
      derivation: row['derivation'] as String?,
    );
  }
}
