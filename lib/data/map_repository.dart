/// Векторная основа карты: берег, озёра, реки, области.
library;

import 'bible_database.dart';

enum MapLineKind { coast, lake, river, region }

class MapLine {
  final MapLineKind kind;
  final String? name;

  /// Долгота и широта по порядку.
  final List<(double lon, double lat)> points;

  const MapLine({required this.kind, required this.points, this.name});
}

MapLineKind _kind(String s) => switch (s) {
      'lake' => MapLineKind.lake,
      'river' => MapLineKind.river,
      'region' => MapLineKind.region,
      _ => MapLineKind.coast,
    };

extension MapQueries on BibleDatabase {
  /// Вся основа целиком: её меньше двух тысяч точек, дробить запросами незачем.
  List<MapLine> mapLines() => [
        for (final r in raw.select('SELECT kind, name, points FROM map_lines'))
          MapLine(
            kind: _kind(r['kind'] as String),
            name: r['name'] as String?,
            points: [
              for (final p in (r['points'] as String).split(' '))
                if (p.contains(','))
                  (
                    double.parse(p.split(',')[0]),
                    double.parse(p.split(',')[1]),
                  )
            ],
          )
      ];
}
