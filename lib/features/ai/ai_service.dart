/// Клиент разбора отрывков.
///
/// Ключи моделей нельзя зашивать в приложение — их извлекут из бандла за
/// минуты. Поэтому запрос всегда идёт на собственный сервер, который держит
/// ключ, собирает контекст из источников и требует от модели отвечать только
/// по ним. Пока сервер не поднят, приложение честно говорит об этом, а не
/// подставляет выдуманный ответ.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Адрес бэкенда. Задаётся при сборке:
/// `flutter run --dart-define=AI_ENDPOINT=https://…`
const aiEndpoint = String.fromEnvironment('AI_ENDPOINT');

/// Общий секрет с сервером: `--dart-define=AI_TOKEN=…`. Он не прячет ключ
/// модели — тот и так остаётся на сервере, — а отсекает чужие запросы к
/// адресу, за которые платил бы владелец сервера.
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
  const AiService(this._client);
  final http.Client _client;

  bool get isConfigured => aiEndpoint.isNotEmpty;

  Future<AiAnswer> explain(AiRequest request) async {
    if (!isConfigured) {
      throw const AiUnavailable(
        'Разбор с ИИ появится, когда будет подключён сервер. '
        'Ниже уже доступно то, что приложение знает offline: '
        'кто и что упомянуто в отрывке и куда ведут параллельные места.',
      );
    }
    final res = await _client.post(
      Uri.parse('$aiEndpoint/explain'),
      headers: {
        'content-type': 'application/json',
        if (aiToken.isNotEmpty) 'x-app-token': aiToken,
      },
      body: jsonEncode(request.toJson()),
    );
    if (res.statusCode != 200) {
      throw AiUnavailable('Сервер ответил ${res.statusCode}');
    }
    return AiAnswer.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }
}

final aiServiceProvider = Provider<AiService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return AiService(client);
});
