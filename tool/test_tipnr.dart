// Дымовой тест парсера TIPNR. Запуск: dart run tool/test_tipnr.dart
import 'dart:io';
import 'tipnr_parser.dart';

void main() {
  final src = File('data/raw/tipnr.txt').readAsStringSync();
  final all = parseTipnr(src);

  final byKind = <EntityKind, int>{};
  for (final e in all) {
    byKind[e.kind] = (byKind[e.kind] ?? 0) + 1;
  }
  print('всего сущностей: ${all.length}');
  for (final k in EntityKind.values) {
    print('  ${k.name}: ${byKind[k] ?? 0}');
  }

  final withArticle = all.where((e) => e.article.isNotEmpty).length;
  final withRefs = all.where((e) => e.allRefs.isNotEmpty).length;
  final totalRefs = all.fold<int>(0, (s, e) => s + e.allRefs.length);
  print('со статьёй: $withArticle   со ссылками: $withRefs   '
      'всего упоминаний: $totalRefs');

  for (final want in ['Aaron', 'Moses', 'Nicodemus', 'Jerusalem', 'Capernaum']) {
    final e = all.firstWhere((x) => x.id.startsWith('$want@'),
        orElse: () => Entity()..id = '');
    if (e.id.isEmpty) {
      print('\n$want — НЕ НАЙДЕН');
      continue;
    }
    print('\n── ${e.id}  [${e.kind.name}]');
    print('   ${e.description.isNotEmpty ? e.description : e.geoArea}');
    print('   имена: ${e.names.map((n) => '${n.significance}:${n.english}'
        '${n.original.isNotEmpty ? "(${n.original})" : ""}').join(', ')}');
    print('   упоминаний: ${e.allRefs.length}   стронг: ${e.primaryStrong}');
    if (e.parents.isNotEmpty) print('   родители: ${e.parents.join(', ')}');
    if (e.siblings.isNotEmpty) print('   братья/сёстры: ${e.siblings.join(', ')}');
    if (e.offspring.isNotEmpty) print('   дети: ${e.offspring.join(', ')}');
    if (e.tribe.isNotEmpty) print('   колено: ${e.tribe}');
    if (e.openBibleName.isNotEmpty) print('   openbible: ${e.openBibleName}');
    if (e.briefest.isNotEmpty) print('   кратко: ${e.briefest}');
    if (e.brief.isNotEmpty) print('   бейдж: ${e.brief}');
    final a = e.article;
    print('   статья: ${a.length > 150 ? "${a.substring(0, 150)}…" : a}');
  }

  // Тёзки обязаны остаться разными сущностями — на этом держится вся
  // интерактивность текста.
  final abdi = all.where((e) => e.id.startsWith('Abdi@')).toList();
  print('\nтёзки Abdi: ${abdi.map((e) => e.id).join(' | ')}');
  final marys = all.where((e) => e.id.startsWith('Mary@')).toList();
  print('тёзки Mary: ${marys.length} — ${marys.map((e) => e.id).join(' | ')}');
}
