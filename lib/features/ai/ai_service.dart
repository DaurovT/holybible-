/// Клиент разбора отрывков.
///
/// Ключи моделей нельзя зашивать в приложение — их извлекут из бандла за
/// минуты. Поэтому запрос всегда идёт на собственный сервер, который держит
/// ключ, собирает контекст из источников и требует от модели отвечать только
/// по ним. Пока сервер не поднят, приложение честно говорит об этом, а не
/// подставляет выдуманный ответ.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'device_attest.dart';

/// Адрес бэкенда. Задаётся при сборке:
/// `flutter run --dart-define=AI_ENDPOINT=https://…`
const aiEndpoint = String.fromEnvironment('AI_ENDPOINT');

/// Запасной общий секрет: `--dart-define=AI_TOKEN=…`. Нужен только там, где
/// App Attest недоступен — в симуляторе. Он один на все копии приложения, из
/// бандла его достанут, поэтому на сервере путь через него по умолчанию
/// закрыт. Подлинность сборки доказывает App Attest, см. device_attest.dart.
const aiToken = String.fromEnvironment('AI_TOKEN');

class AiRequest {
  final String mode;
  final String instruction;
  final String reference;
  final String passage;

  /// Идентификаторы сущностей отрывка. Сервер подтянет по ним статьи и
  /// передаст модели как источник — вместо того чтобы полагаться на её память.
  final List<String> entityIds;
  final List<String> crossReferences;

  const AiRequest({
    required this.mode,
    required this.instruction,
    required this.reference,
    required this.passage,
    this.entityIds = const [],
    this.crossReferences = const [],
  });

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'instruction': instruction,
        'reference': reference,
        'passage': passage,
        'entityIds': entityIds,
        'crossReferences': crossReferences,
      };
}

class Citation {
  final String label;
  final String source;
  const Citation(this.label, this.source);

  factory Citation.fromJson(Map<String, dynamic> j) =>
      Citation(j['label'] as String? ?? '', j['source'] as String? ?? '');
}

class AiAnswer {
  final String text;
  final List<Citation> citations;
  const AiAnswer(this.text, this.citations);

  factory AiAnswer.fromJson(Map<String, dynamic> j) => AiAnswer(
        j['text'] as String? ?? '',
        [
          for (final c in (j['citations'] as List? ?? const []))
            Citation.fromJson(c as Map<String, dynamic>)
        ],
      );
}

class AiUnavailable implements Exception {
  final String message;
  const AiUnavailable(this.message);
  @override
  String toString() => message;
}

class AiService {
  AiService(this._client) : _attest = DeviceAttest(_client, aiEndpoint);

  final http.Client _client;
  final DeviceAttest _attest;

  bool get isConfigured => aiEndpoint.isNotEmpty;

  Future<AiAnswer> explain(AiRequest request) async {
    if (!isConfigured) {
      throw const AiUnavailable(
        'Разбор с ИИ появится, когда будет подключён сервер. '
        'Ниже уже доступно то, что приложение знает offline: '
        'кто и что упомянуто в отрывке и куда ведут параллельные места.',
      );
    }
    try {
      var res = await _send(request);
      if (res.statusCode == 401) {
        // Пропуск просрочен или сервер забыл устройство — заводимся заново.
        res = await _send(request, refresh: true);
      }
      if (res.statusCode != 200) throw AiUnavailable(_reason(res));
      return AiAnswer.fromJson(
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
    } on TimeoutException {
      throw const AiUnavailable(
          'Сервер не ответил вовремя. Попробуйте ещё раз — '
          'остальное приложение работает без сети.');
    } on SocketException {
      throw const AiUnavailable(_offline);
    } on http.ClientException {
      throw const AiUnavailable(_offline);
    } on FormatException {
      throw const AiUnavailable(_garbled);
    } on TypeError {
      // JSON разобрался, но не того вида: прокси или страница входа в Wi-Fi.
      throw const AiUnavailable(_garbled);
    }
  }

  static const _offline = 'Нет связи с сервером. Разбору нужен интернет, '
      'а текст, поиск и карточки работают и так.';
  static const _garbled =
      'Сервер прислал непонятный ответ. Попробуйте позже.';

  /// Сколько ждать разбора. Модель отвечает за секунды, но без предела запрос
  /// в метро висит бесконечно, и панель так и крутит индикатор.
  static const _timeout = Duration(seconds: 60);

  Future<http.Response> _send(AiRequest request, {bool refresh = false}) async {
    final pass = await _attest.token(refresh: refresh);
    return _client.post(
      Uri.parse('$aiEndpoint/explain'),
      headers: {
        'content-type': 'application/json',
        if (pass != null) 'authorization': 'Bearer $pass',
        if (pass == null && aiToken.isNotEmpty) 'x-app-token': aiToken,
      },
      body: jsonEncode(request.toJson()),
    ).timeout(_timeout);
  }

  /// Сервер объясняет отказ по-русски — показываем это, а не код ошибки:
  /// «слишком много разборов за час» читателю понятнее, чем «429».
  String _reason(http.Response res) {
    final problem = _attest.lastProblem;
    if (res.statusCode == 401 && problem != null) {
      return 'Не удалось подтвердить устройство — $problem. Разбор недоступен, '
          'остальное приложение работает без сети.';
    }
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final error = (j['error'] as String?)?.trim();
      if (error != null && error.isNotEmpty) return error;
    } catch (_) {
      // Сервер ответил не JSON или JSON не того вида — ниже общий текст.
    }
    if (res.statusCode == 401) {
      return 'Не удалось подтвердить устройство. Разбор недоступен, '
          'остальное приложение работает без сети.';
    }
    return 'Сервер ответил ${res.statusCode}';
  }
}

final aiServiceProvider = Provider<AiService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return AiService(client);
});
