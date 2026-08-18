/// Сжимает базы для бандла: assets/db/*.db → assets/db/*.db.gz.
///
/// В приложение попадают только сжатые файлы, а распаковываются они при первом
/// запуске. Иначе база лежит на устройстве дважды — в бандле и в рабочей копии,
/// которую делает SQLite: читать прямо из бандла он не умеет.
///
/// Запуск последним шагом сборки: dart run tool/pack_db.dart
library;

import 'dart:io';

void main() {
  final dir = Directory('${Directory.current.path}/assets/db');
  final sources = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.db'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (sources.isEmpty) {
    stderr.writeln('в assets/db нет ни одной базы — сначала соберите их');
    exit(1);
  }

  var before = 0, after = 0;
  for (final file in sources) {
    final bytes = file.readAsBytesSync();
    // Максимальное сжатие: распаковка от уровня не зависит, а файл меньше.
    final packed = GZipCodec(level: 9).encode(bytes);
    File('${file.path}.gz').writeAsBytesSync(packed, flush: true);

    before += bytes.length;
    after += packed.length;
    stdout.writeln('${file.uri.pathSegments.last}: '
        '${(bytes.length / 1048576).toStringAsFixed(1)} МБ → '
        '${(packed.length / 1048576).toStringAsFixed(1)} МБ');
  }

  stdout.writeln('\nв бандл поедет ${(after / 1048576).toStringAsFixed(1)} МБ '
      'вместо ${(before / 1048576).toStringAsFixed(1)} МБ');
}
