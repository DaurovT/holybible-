/// Кладёт в bible.db слой карты: береговая линия, озёра, реки и области.
///
/// Карта офлайновая и без тайлов. Тайлы — это сеть и чужой сервер, а нам нужно
/// работать в самолёте. Поэтому берём векторную основу Natural Earth
/// (общественное достояние), обрезаем по библейскому миру и упрощаем: на экране
/// телефона всё равно не видно колена реки шириной в сто метров.
///
/// Области (Аммон, Васан, Асия) — из OpenBible (CC BY), они уже лежат в
/// data/raw/ob_geometry.jsonl.
///
/// Запуск: dart run tool/build_map.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart';

/// Библейский мир: от Рима до Персии, от Чёрного моря до Египта.
const minLon = 24.0, maxLon = 50.0, minLat = 27.0, maxLat = 43.0;

const schema = '''
DROP TABLE IF EXISTS map_lines;
CREATE TABLE map_lines (
  id     INTEGER PRIMARY KEY,
  kind   TEXT NOT NULL,   -- coast | lake | river | region
  name   TEXT,
  points TEXT NOT NULL    -- «lon,lat lon,lat …»
);
CREATE INDEX idx_map_kind ON map_lines(kind);
''';

bool _inside(double lon, double lat) =>
    lon >= minLon && lon <= maxLon && lat >= minLat && lat <= maxLat;

/// Упрощение Рамера — Дугласа — Пекера: выбрасывает точки, которые почти лежат
/// на прямой между соседями.
List<List<double>> _simplify(List<List<double>> pts, double tolerance) {
  if (pts.length < 3) return pts;

  var maxDist = 0.0;
  var index = 0;
  final first = pts.first, last = pts.last;
  for (var i = 1; i < pts.length - 1; i++) {
    final d = _distanceToSegment(pts[i], first, last);
    if (d > maxDist) {
      maxDist = d;
      index = i;
    }
  }

  if (maxDist <= tolerance) return [first, last];
  final left = _simplify(pts.sublist(0, index + 1), tolerance);
  final right = _simplify(pts.sublist(index), tolerance);
  return [...left.sublist(0, left.length - 1), ...right];
}

double _distanceToSegment(List<double> p, List<double> a, List<double> b) {
  final dx = b[0] - a[0], dy = b[1] - a[1];
  if (dx == 0 && dy == 0) {
    return math.sqrt(math.pow(p[0] - a[0], 2) + math.pow(p[1] - a[1], 2));
  }
  var t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy);
  t = t.clamp(0.0, 1.0);
  final x = a[0] + t * dx, y = a[1] + t * dy;
  return math.sqrt(math.pow(p[0] - x, 2) + math.pow(p[1] - y, 2));
}

/// Режет линию на куски, попадающие в наш прямоугольник.
List<List<List<double>>> _crop(List<List<double>> line) {
  final out = <List<List<double>>>[];
  var current = <List<double>>[];
  for (final p in line) {
    if (_inside(p[0], p[1])) {
      current.add(p);
    } else {
      // Одну точку за границей оставляем, чтобы линия доходила до края.
      if (current.isNotEmpty) {
        current.add(p);
        out.add(current);
        current = <List<double>>[];
      }
    }
  }
  if (current.length > 1) out.add(current);
  return out;
}

Iterable<List<List<double>>> _lines(Map<String, dynamic> geometry) sync* {
  final type = geometry['type'];
  final coords = geometry['coordinates'];
  List<List<double>> asLine(List<dynamic> raw) => [
        for (final p in raw)
          [(p as List)[0] as num, p[1] as num]
              .map((n) => n.toDouble())
              .toList()
      ];

  if (type == 'LineString') {
    yield asLine(coords as List);
  } else if (type == 'MultiLineString' || type == 'Polygon') {
    for (final part in (coords as List)) {
      yield asLine(part as List);
    }
  } else if (type == 'MultiPolygon') {
    for (final poly in (coords as List)) {
      for (final ring in (poly as List)) {
        yield asLine(ring as List);
      }
    }
  }
}

int _load(Database db, String path, String kind, double tolerance) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('нет $path');
    return 0;
  }
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final insert =
      db.prepare('INSERT INTO map_lines(kind,name,points) VALUES(?,?,?)');

  var count = 0;
  for (final f in (data['features'] as List)) {
    final feature = f as Map<String, dynamic>;
    final props = (feature['properties'] as Map?) ?? const {};
    final name = props['name'] ?? props['name_en'];
    for (final line in _lines(feature['geometry'] as Map<String, dynamic>)) {
      for (final piece in _crop(line)) {
        final simple = _simplify(piece, tolerance);
        if (simple.length < 2) continue;
        insert.execute([
          kind,
          name is String ? name : null,
          simple.map((p) => '${p[0].toStringAsFixed(3)},'
              '${p[1].toStringAsFixed(3)}').join(' '),
        ]);
        count++;
      }
    }
  }
  insert.dispose();
  return count;
}

int _loadRegions(Database db, String path) {
  final file = File(path);
  if (!file.existsSync()) return 0;
  final insert =
      db.prepare('INSERT INTO map_lines(kind,name,points) VALUES(?,?,?)');
  var count = 0;

  for (final line in file.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final row = jsonDecode(line) as Map<String, dynamic>;
    final boundary =
        ((row['suggested'] as Map?)?['rough_boundary'] as List?) ?? const [];
    if (boundary.length < 3) continue;

    final pts = <List<double>>[];
    for (final p in boundary) {
      final parts = (p as String).split(',');
      if (parts.length != 2) continue;
      final lon = double.tryParse(parts[0]), lat = double.tryParse(parts[1]);
      if (lon == null || lat == null || !_inside(lon, lat)) continue;
      pts.add([lon, lat]);
    }
    if (pts.length < 3) continue;
    // Контур замыкаем: в источнике последняя точка не повторяет первую.
    pts.add(pts.first);

    insert.execute([
      'region',
      row['name'],
      pts.map((p) => '${p[0].toStringAsFixed(3)},${p[1].toStringAsFixed(3)}')
          .join(' '),
    ]);
    count++;
  }
  insert.dispose();
  return count;
}

void main() {
  final root = Directory.current.path;
  final db = sqlite3.open('$root/assets/db/bible.db');
  db.execute('PRAGMA journal_mode = OFF');
  db.execute(schema);
  db.execute('BEGIN');

  final ne = '$root/data/raw/naturalearth';
  // Берег рисуется тоньше всего — ему нужна точность повыше.
  final coast = _load(db, '$ne/ne_50m_coastline.geojson', 'coast', 0.01);
  final lakes = _load(db, '$ne/ne_50m_lakes.geojson', 'lake', 0.01);
  final rivers =
      _load(db, '$ne/ne_50m_rivers_lake_centerlines.geojson', 'river', 0.02);
  final regions = _loadRegions(db, '$root/data/raw/ob_geometry.jsonl');

  db.execute('COMMIT');
  db.execute('VACUUM');

  final points = db
      .select("SELECT SUM(LENGTH(points) - LENGTH(REPLACE(points,' ','')) + 1) "
          'c FROM map_lines')
      .first['c'];

  stdout.writeln('── карта ──');
  stdout.writeln('береговая линия: $coast');
  stdout.writeln('озёра:           $lakes');
  stdout.writeln('реки:            $rivers');
  stdout.writeln('области:         $regions');
  stdout.writeln('точек всего:     $points');

  db.dispose();
  final mb = (File('$root/assets/db/bible.db').lengthSync() / 1048576)
      .toStringAsFixed(1);
  stdout.writeln('\nbible.db — $mb МБ');
}
