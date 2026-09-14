/// Android-ветка подтверждения устройства: Play Integrity.
///
/// Нативный мост и сервер подменены: проверяется порядок со стороны
/// приложения — челлендж, вердикт Google Play на этот челлендж, обмен на
/// пропуск — и то, что отказ объясняется, а не прячется.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holy_bible/features/ai/device_attest.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('holybible/play_integrity');
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 'verdict-token';
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  http.Response json(Object body, [int status = 200]) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  /// Сервер: выдаёт челлендж и меняет вердикт на пропуск (или отказывает).
  http.Client server({
    List<Map<String, dynamic>>? seen,
    int status = 200,
    Object? reply,
  }) {
    var issued = 0;
    return MockClient((req) async {
      switch (req.url.path) {
        case '/attest/challenge':
          issued++;
          return json({'challenge': 'challenge-$issued'});
        case '/attest/android':
          seen?.add(jsonDecode(req.body) as Map<String, dynamic>);
          return json(reply ?? {'token': 'pass', 'expiresIn': 3600}, status);
      }
      return http.Response('', 404);
    });
  }

  DeviceAttest android(http.Client client, {String project = '123456789'}) =>
      DeviceAttest(client, 'https://api.test',
          platform: AttestPlatform.android, cloudProject: project);

  group('Android: Play Integrity', () {
    test('вердикт на челлендж сервера меняется на пропуск', () async {
      final seen = <Map<String, dynamic>>[];
      final attest = android(server(seen: seen));

      expect(attest.available, isTrue);
      expect(await attest.token(), 'pass');

      expect(calls.single.method, 'requestToken');
      expect(calls.single.arguments,
          {'cloudProjectNumber': '123456789', 'requestHash': 'challenge-1'});
      expect(seen.single['challenge'], 'challenge-1');
      expect(seen.single['token'], 'verdict-token');
      expect(seen.single['installId'], matches(RegExp(r'^[A-Za-z0-9_-]{16,64}$')));
    });

    test('пропуск берётся из памяти, пока не истёк', () async {
      final attest = android(server());
      await attest.token();
      await attest.token();
      expect(calls, hasLength(1));
    });

    test('идентификатор установки один на все запуски', () async {
      final seen = <Map<String, dynamic>>[];
      await android(server(seen: seen)).token();
      await android(server(seen: seen)).token();
      expect(seen, hasLength(2));
      expect(seen[0]['installId'], seen[1]['installId']);
    });

    test('отказ сервера объясняется, а не прячется', () async {
      final attest = android(server(status: 401, reply: {
        'error': 'Устройство не подтверждено',
        'detail': 'приложение не признано Google Play: UNEVALUATED',
      }));
      expect(await attest.token(), isNull);
      expect(attest.lastProblem,
          'проверка Google Play: приложение не признано Google Play: UNEVALUATED');
    });

    test('ошибка Google Play доходит до сообщения', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
            code: 'integrity_-16', message: 'Cloud project number is invalid');
      });
      final attest = android(server());
      expect(await attest.token(), isNull);
      // Суть по-русски вместо английской стены текста со ссылкой.
      expect(attest.lastProblem,
          'Google Play: в сборке неверный номер проекта Google Cloud (-16)');
    });

    test('без проекта Google Cloud разбор на Android недоступен', () async {
      final attest = android(server(), project: '');
      expect(attest.available, isFalse);
      expect(await attest.token(), isNull);
      expect(calls, isEmpty);
    });
  });
}
