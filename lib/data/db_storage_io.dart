/// Хранение баз на телефоне: обычные файлы и нативный SQLite.
///
/// SQLite не умеет читать файл прямо из бандла Flutter, поэтому при первом
/// запуске база распаковывается в каталог приложения. Дальше всё работает
/// офлайн и без сети — это принципиально: Библию читают в самолёте, в храме
/// без связи и в странах с блокировками.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

/// Слова оригинала — это ещё 25 МБ. На телефоне они есть, в браузере нет.
const supportsOriginalWords = true;

/// Открывает вшитую базу, распаковав её при первом запуске.
///
/// [prefix] — начало имени файла без версии: по нему находятся и удаляются
/// копии прошлых версий, чтобы они не копились на устройстве.
Future<CommonDatabase> openBundled({
  required String asset,
  required String fileName,
  required String prefix,
}) async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, fileName));

  if (!file.existsSync()) {
    for (final f in dir.listSync()) {
      if (f is File && p.basename(f.path).startsWith(prefix)) {
        f.deleteSync();
      }
    }
    await _unpack(asset, file);
  }

  return sqlite3.open(file.path, mode: OpenMode.readOnly);
}

/// Распаковывает сжатую базу из бандла в рабочий файл.
///
/// Потоком, а не целиком в память: распакованная база — это десятки мегабайт,
/// и держать их в памяти ради одной записи на диск незачем.
///
/// Распаковка идёт во временный файл, а рабочее имя он получает только в самом
/// конце. Иначе приложение, закрытое посреди первого запуска, оставит обрезанную
/// базу под рабочим именем: раз файл есть, распаковка больше не повторится, и
/// текст не откроется до переустановки. Недописанный `.part` уберёт чистка
/// старых версий — его имя начинается так же.
Future<void> _unpack(String asset, File target) async {
  final data = await rootBundle.load(asset);
  final packed = File('${target.path}.gz');
  final partial = File('${target.path}.part');
  await packed.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true);
  await packed.openRead().transform(gzip.decoder).pipe(partial.openWrite());
  await packed.delete();
  await partial.rename(target.path);
}

/// Личные данные — закладки, выделения, заметки.
Future<CommonDatabase> openUserDatabase() async {
  final dir = await getApplicationSupportDirectory();
  return openUserDatabaseAt(p.join(dir.path, 'user.db'));
}

/// Открытие по явному пути. Нужно тестам: path_provider вне приложения не
/// работает, а логика закладок и заметок проверяема сама по себе.
CommonDatabase openUserDatabaseAt(String path) => sqlite3.open(path);
