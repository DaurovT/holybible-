// Дымовой тест парсера USFM. Запуск: dart run tool/test_parse.dart
import 'dart:io';
import 'usfm_parser.dart';

void main() {
  final cases = [
    ('data/raw/russyn', 'PSA', 23, 'Синодальный, поэзия'),
    ('data/raw/engwebp', 'JHN', 3, 'WEB, слова Христа + сноски'),
    ('data/raw/russyn', 'GEN', 1, 'Синодальный, проза'),
    ('data/raw/engwebp', 'PSA', 119, 'WEB, акростих'),
  ];

  for (final (dir, code, ch, label) in cases) {
    final d = Directory(dir);
    final f = d
        .listSync()
        .whereType<File>()
        .firstWhere((e) => e.path.contains(code) && e.path.endsWith('.usfm'));
    final book = parseUsfm(f.readAsStringSync());

    final vs = book.verses.where((v) => v.chapter == ch).toList();
    print('══ $label — ${book.name} ($code) ${book.chapterCount} гл, '
        '${book.verses.length} стихов, ${book.headings.length} заголовков');

    for (final v in vs.take(4)) {
      print('  ${v.chapter}:${v.verse}');
      for (final s in v.segments) {
        final marks = s.runs
            .expand((r) => r.marks)
            .toSet()
            .join(',');
        final notes = s.runs.where((r) => r.noteKind != null).length;
        final txt = s.runs
            .where((r) => r.noteKind == null)
            .map((r) => r.text)
            .join()
            .trim();
        print('    [${s.style}${s.brk ? " ⏎" : ""}]'
            '${marks.isNotEmpty ? " {$marks}" : ""}'
            '${notes > 0 ? " ($notes сносок)" : ""} '
            '${txt.length > 78 ? "${txt.substring(0, 78)}…" : txt}');
      }
    }
    print('  plain: ${vs.isEmpty ? "—" : vs.first.plainText}');
    if (vs.isNotEmpty && vs.first.strongs.isNotEmpty) {
      final v = vs.first;
      final sample = v.strongs.take(5).map((s) =>
          '"${v.plainText.substring(s.start, s.end)}"→${s.strong}');
      print('  strongs(${v.strongs.length}): ${sample.join(' ')}');
    }
    print('');
  }
}
