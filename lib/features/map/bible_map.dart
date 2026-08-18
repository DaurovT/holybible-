/// Карта библейского мира — без тайлов и без сети.
///
/// Основа векторная и лежит в самой базе: берег, озёра, реки, границы областей.
/// Тайлы означали бы чужой сервер и работу только онлайн, а приложение обещает
/// открываться в самолёте.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/reading_theme.dart';
import '../../data/entity_repository.dart';
import '../../data/map_repository.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

class BibleMap extends ConsumerWidget {
  const BibleMap({
    super.key,
    this.focus,
    this.height = 260,
    this.spanDegrees = 3.0,
    this.onTapPlace,
  });

  /// Место, вокруг которого строится вид. null — весь библейский мир.
  final BibleEntity? focus;
  final double height;

  /// Сколько градусов широты показывать вокруг выбранного места.
  final double spanDegrees;
  final void Function(BibleEntity place)? onTapPlace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final db = ref.watch(bibleDbProvider).valueOrNull;
    if (db == null) return SizedBox(height: height);

    final lines = db.mapLines();
    final places = db.placesWithLocation();

    final centerLon = focus?.lon ?? 35.2;
    final centerLat = focus?.lat ?? 33.0;
    final halfLat = focus == null ? 7.5 : spanDegrees / 2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: height,
        color: c.surface,
        child: LayoutBuilder(
          builder: (ctx, box) {
            final view = _View(
              centerLon: centerLon,
              centerLat: centerLat,
              halfLat: halfLat,
              size: Size(box.maxWidth, height),
            );
            // Тысяча точек в одном окне сливается в кляксу. Оставляем те, о
            // которых Писание говорит хоть сколько-нибудь часто, плюс само
            // выбранное место — оно должно быть видно всегда.
            final visible = [
              for (final p in places)
                if (view.contains(p.lon!, p.lat!) &&
                    (p.refCount >= 6 || p.id == focus?.id))
                  p
            ];

            // Карту можно приблизить и подвинуть: на общем плане Иудея — это
            // пятно в палец шириной, и разобрать в нём что-либо нельзя.
            return InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: GestureDetector(
                onTapUp: onTapPlace == null
                    ? null
                    : (d) {
                        final hit = _nearest(visible, view, d.localPosition);
                        if (hit != null) onTapPlace!(hit);
                      },
                child: CustomPaint(
                  painter: _MapPainter(
                    lines: lines,
                    places: visible,
                    focus: focus,
                    view: view,
                    colors: c,
                  ),
                  size: Size.infinite,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  BibleEntity? _nearest(List<BibleEntity> places, _View view, Offset tap) {
    BibleEntity? best;
    var bestDistance = 28.0;
    for (final p in places) {
      final at = view.project(p.lon!, p.lat!);
      final d = (at - tap).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = p;
      }
    }
    return best;
  }
}

/// Пересчёт координат в пиксели.
///
/// Долгота сжимается на косинус широты: без этого на широте Иерусалима карта
/// растягивается вширь почти в полтора раза.
class _View {
  _View({
    required this.centerLon,
    required this.centerLat,
    required this.halfLat,
    required this.size,
  }) {
    final k = math.cos(centerLat * math.pi / 180);
    final halfLon = halfLat * (size.width / size.height) / k;
    minLon = centerLon - halfLon;
    maxLon = centerLon + halfLon;
    minLat = centerLat - halfLat;
    maxLat = centerLat + halfLat;
  }

  final double centerLon, centerLat, halfLat;
  final Size size;
  late final double minLon, maxLon, minLat, maxLat;

  Offset project(double lon, double lat) => Offset(
        (lon - minLon) / (maxLon - minLon) * size.width,
        (maxLat - lat) / (maxLat - minLat) * size.height,
      );

  bool contains(double lon, double lat) =>
      lon >= minLon && lon <= maxLon && lat >= minLat && lat <= maxLat;
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.lines,
    required this.places,
    required this.focus,
    required this.view,
    required this.colors,
  });

  final List<MapLine> lines;
  final List<BibleEntity> places;
  final BibleEntity? focus;
  final _View view;
  final ReadingColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final water = colors.accent.withValues(alpha: 0.30);

    void drawLines(MapLineKind kind, Paint paint) {
      for (final line in lines) {
        if (line.kind != kind) continue;
        final path = Path();
        var started = false;
        for (final (lon, lat) in line.points) {
          final at = view.project(lon, lat);
          if (!started) {
            path.moveTo(at.dx, at.dy);
            started = true;
          } else {
            path.lineTo(at.dx, at.dy);
          }
        }
        if (started) canvas.drawPath(path, paint);
      }
    }

    // Области — самым бледным: это фон, а не предмет разговора.
    drawLines(
        MapLineKind.region,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = colors.faint.withValues(alpha: 0.35));
    drawLines(
        MapLineKind.river,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = water);
    drawLines(
        MapLineKind.lake,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = water);
    drawLines(
        MapLineKind.coast,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = colors.muted.withValues(alpha: 0.55));

    // Точки мест: сначала малозаметные, поверх — те, о которых говорят чаще.
    final sorted = [...places]
      ..sort((a, b) => a.refCount.compareTo(b.refCount));
    // Подписи расставляем сверху вниз по значимости и пропускаем те, что легли
    // бы на уже нарисованную: карта, заросшая текстом, не читается вовсе.
    final taken = <Rect>[];
    // Подпись выбранного места рисуется последней, поверх точек, но место под
    // неё занимаем первым: иначе соседняя подпись оказывается под ней.
    if (focus != null && focus!.lat != null) {
      final at = view.project(focus!.lon!, focus!.lat!) + const Offset(10, -8);
      final p = _painterFor(focus!.displayName, colors.text, true);
      taken.add(Rect.fromLTWH(at.dx - 4, at.dy - 3, p.width + 8, p.height + 6));
    }
    for (final p in sorted.reversed) {
      if (focus != null && p.id == focus!.id) continue;
      if (p.refCount < 12) continue;
      // Только русские имена: у части мест выравнивание не нашло русского
      // соответствия, и посреди кириллицы всплывали «Great» и «South».
      if (!_cyrillic.hasMatch(p.displayName)) continue;
      _tryLabel(canvas, p, view, taken, colors);
    }

    for (final p in sorted) {
      final at = view.project(p.lon!, p.lat!);
      final isFocus = focus != null && p.id == focus!.id;
      final radius = isFocus ? 6.0 : (p.refCount > 60 ? 3.5 : 2.5);

      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..color = isFocus
              ? colors.accent
              : colors.muted.withValues(alpha: p.refCount > 12 ? 0.85 : 0.5),
      );
      if (isFocus) {
        canvas.drawCircle(
          at,
          radius + 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = colors.accent.withValues(alpha: 0.5),
        );
      }

      if (isFocus) {
        _label(canvas, p.displayName, at + const Offset(10, -8), colors.text,
            true);
      }
    }
  }

  static final _cyrillic = RegExp('[А-Яа-яЁё]');

  /// Рисует подпись, если она не сталкивается с уже нарисованными.
  void _tryLabel(Canvas canvas, BibleEntity place, _View view,
      List<Rect> taken, ReadingColors colors) {
    final at = view.project(place.lon!, place.lat!) + const Offset(7, -6);
    final painter = _painterFor(place.displayName, colors.muted, false);
    final rect = Rect.fromLTWH(
        at.dx - 4, at.dy - 3, painter.width + 8, painter.height + 6);
    if (rect.right > view.size.width) return;
    for (final other in taken) {
      if (other.overlaps(rect)) return;
    }
    taken.add(rect);
    painter.paint(canvas, at);
  }

  TextPainter _painterFor(String text, Color color, bool bold) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: bold ? 13 : 11,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  void _label(Canvas canvas, String text, Offset at, Color color, bool bold) {
    _painterFor(text, color, bold).paint(canvas, at);
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.focus?.id != focus?.id ||
      old.colors != colors ||
      old.places.length != places.length;
}
