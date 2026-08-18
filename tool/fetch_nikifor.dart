/// Скачивает «Библейскую энциклопедию архимандрита Никифора» (1891) из Викитеки.
///
/// Текст 1891 года — общественное достояние; сама Викитека отдаёт его через
/// официальный API, никакого разбора чужих страниц. Скачанное складывается в
/// data/raw/nikifor/articles.json и дальше собирается офлайн, чтобы сборка базы
/// не зависела от сети.
///
/// Запуск: dart run tool/fetch_nikifor.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _api = 'https://ru.wikisource.org/w/api.php';
const _prefix = 'БЭАН/';

// Викитека просит представляться. Без этого запросы отвергаются.
const _headers = {
  'User-Agent': 'HolyBible/1.0 (offline Bible reader; contact via GitHub)',
};

/// Запрос всегда POST: список заголовков не помещается в адресную строку, и API
/// отвечает на такое отказом.
///
/// Викитека ограничивает частоту обращений и на превышение отвечает 429. Это
/// не ошибка, а просьба подождать — ждём ровно столько, сколько она называет.
Future<Map<String, dynamic>> _get(Map<String, String> params) async {
  final body = {...params, 'format': 'json', 'formatversion': '2'};
  for (var attempt = 0; attempt < 6; attempt++) {
    final res = await http.post(Uri.parse(_api), headers: _headers, body: body);
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    }
    final wait = res.statusCode == 429
        ? Duration(seconds: int.tryParse(res.headers['retry-after'] ?? '') ?? 30)
        : const Duration(seconds: 5);
    stderr.writeln('  HTTP ${res.statusCode}, жду ${wait.inSeconds} с…');
    await Future<void>.delayed(wait);
  }
  throw Exception('не удалось получить ${params['titles'] ?? params['list']}');
}

/// Все заголовки статей энциклопедии.
Future<List<String>> _titles() async {
  final out = <String>[];
  String? from;
  do {
    final data = await _get({
      'action': 'query',
      'list': 'allpages',
      'apprefix': _prefix,
      'apnamespace': '0',
      'aplimit': '500',
      if (from != null) 'apcontinue': from,
    });
    for (final p in (data['query']['allpages'] as List)) {
      out.add((p as Map)['title'] as String);
    }
    from = (data['continue'] as Map?)?['apcontinue'] as String?;
    stdout.write('\r  заголовков: ${out.length}');
    if (from != null) await Future<void>.delayed(const Duration(seconds: 1));
  } while (from != null);
  stdout.writeln();
  return out;
}

/// Разметка статей пачками по 50 — столько разрешает отдать API за раз.
Future<Map<String, String>> _contents(List<String> titles) async {
  final out = <String, String>{};
  for (var i = 0; i < titles.length; i += 50) {
    final batch = titles.skip(i).take(50).toList();
    final data = await _get({
      'action': 'query',
      'prop': 'revisions',
      'rvprop': 'content',
      'rvslots': 'main',
      'titles': batch.join('|'),
    });

    for (final page in (data['query']['pages'] as List)) {
      final p = page as Map;
      final revisions = p['revisions'] as List?;
      if (revisions == null || revisions.isEmpty) continue;
      final content =
          ((revisions.first as Map)['slots'] as Map)['main']['content'];
      if (content is String) out[p['title'] as String] = content;
    }

    stdout.write('\r  статей: ${out.length} из ${titles.length}');
    // Вежливая пауза между пачками: 4683 статьи — это сотня запросов, и
    // торопиться с ними некуда.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
  }
  stdout.writeln();
  return out;
}

Future<void> main() async {
  final dir = Directory('${Directory.current.path}/data/raw/nikifor');
  dir.createSync(recursive: true);
  final target = File('${dir.path}/articles.json');

  stdout.writeln('собираю список статей…');
  final titles = await _titles();

  stdout.writeln('качаю тексты…');
  final contents = await _contents(titles);

  target.writeAsStringSync(jsonEncode(contents));
  final mb = (target.lengthSync() / 1048576).toStringAsFixed(1);
  stdout.writeln('\nсохранено ${contents.length} статей, $mb МБ → ${target.path}');
}
