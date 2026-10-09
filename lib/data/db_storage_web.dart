/// Хранение баз в браузере: SQLite на WebAssembly и файлы в IndexedDB.
///
/// В браузере нет ни файлов, ни нативного SQLite. Движок приезжает отдельным
/// файлом `web/sqlite3.wasm`, а его «файловая система» — IndexedDB. Поэтому
/// база скачивается один раз: при следующем заходе она уже лежит в браузере, и
/// веб-версия открывается без сети, как приложение на телефоне.
///
/// Распаковка идёт целиком в память: `dart:io` с его потоковым gzip в браузере
/// нет, а 60 МБ вкладка переживает. Это бывает только при первом заходе и при
/// смене версии базы.
library;

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/wasm.dart';

/// Слова оригинала — это ещё 25 МБ поверх базы. В браузере не грузим.
const supportsOriginalWords = false;

WasmSqlite3? _engine;
IndexedDbFileSystem? _files;

Future<(WasmSqlite3, IndexedDbFileSystem)> _sqlite() async {
  final engine = _engine, files = _files;
  if (engine != null && files != null) return (engine, files);

  final fs = await IndexedDbFileSystem.open(dbName: 'holybible');
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  sqlite.registerVirtualFileSystem(fs, makeDefault: true);
  _engine = sqlite;
  _files = fs;
  return (sqlite, fs);
}

/// Открывает вшитую базу, скачав её при первом заходе.
///
/// Что уже скачано, помним в настройках браузера: перечислить файлы в
/// IndexedDB эта файловая система не даёт, а старую версию надо удалить —
/// иначе в браузере накопятся десятки мегабайт прошлых баз.
Future<CommonDatabase> openBundled({
  required String asset,
  required String fileName,
  required String prefix,
}) async {
  final (sqlite, files) = await _sqlite();
  final prefs = await SharedPreferences.getInstance();
  final key = 'web_db_$prefix';
  final saved = prefs.getString(key);
  final path = '/$fileName';

  if (saved != fileName || files.xAccess(path, 0) == 0) {
    if (saved != null && saved != fileName) files.xDelete('/$saved', 0);
    await _put(files, path, await _unpack(asset));
    await prefs.setString(key, fileName);
  }

  return sqlite.open(path);
}

Future<Uint8List> _unpack(String asset) async {
  final packed = await rootBundle.load(asset);
  final bytes = packed.buffer
      .asUint8List(packed.offsetInBytes, packed.lengthInBytes);
  return Uint8List.fromList(const GZipDecoder().decodeBytes(bytes));
}

Future<void> _put(
    IndexedDbFileSystem files, String path, Uint8List bytes) async {
  final file = files
      .xOpen(Sqlite3Filename(path),
          SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE)
      .file;
  try {
    file.xTruncate(0);
    file.xWrite(bytes, 0);
  } finally {
    file.xClose();
  }
  // Пока не сброшено в IndexedDB, база живёт только в памяти вкладки.
  await files.flush();
}

/// Личные данные — закладки, выделения, заметки. Тоже в IndexedDB.
Future<CommonDatabase> openUserDatabase() async {
  final (sqlite, _) = await _sqlite();
  return sqlite.open('/user.db');
}

/// Открытие по явному пути нужно только тестам на настольной машине.
CommonDatabase openUserDatabaseAt(String path) =>
    throw UnsupportedError('В браузере база открывается по имени в IndexedDB');
