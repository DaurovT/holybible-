/// Доказательство, что запрос идёт из подлинного приложения.
///
/// Общий секрет в бандле защищает ровно до первого, кто разберёт .ipa. App
/// Attest устроен иначе: устройство заводит ключ в защищённом элементе, Apple
/// заверяет его, и наружу ключ не выходит вообще. Сервер, проверив заверение,
/// выдаёт короткий пропуск — его и предъявляем при разборе отрывка.
///
/// Ключ заводится один раз за установку, его идентификатор хранится в
/// настройках. Дальше на каждый пропуск подписывается свежий челлендж сервера.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Ключ не найден на сервере: приложение переустановили или сервер потерял
/// базу устройств. Лечится повторным заверением.
class _KeyForgotten implements Exception {}

/// Шаг заверения не прошёл по понятной причине — она уходит в [lastProblem].
class _Refused implements Exception {
  _Refused(this.message);
  final String message;
}

class DeviceAttest {
  DeviceAttest(this._client, this._endpoint);

  static const _channel = MethodChannel('holybible/app_attest');
  static const _keyIdPref = 'attest_key_id';

  /// Предел ожидания на каждый шаг заверения: без него пропавшая сеть
  /// подвешивает разбор навсегда.
  static const _timeout = Duration(seconds: 20);

  final http.Client _client;
  final String _endpoint;

  SharedPreferences? _cached;
  Future<SharedPreferences> get _prefs async =>
      _cached ??= await SharedPreferences.getInstance();

  /// Почему последний раз не удалось получить пропуск. Без этого любой сбой —
  /// другая команда в подписи, не та среда, отказ Apple, пропавшая сеть —
  /// выглядит одинаково: «устройство не подтверждено», и чинить приходится
  /// вслепую.
  String? lastProblem;

  String? _token;
  DateTime? _expires;
  bool? _supported;

  /// На симуляторе и на старых устройствах App Attest недоступен. Это не
  /// ошибка: вызывающий просто останется без пропуска.
  Future<bool> get supported async {
    if (_supported != null) return _supported!;
    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      _supported = false;
    } on MissingPluginException {
      _supported = false; // Android и всё, где моста нет.
    }
    return _supported!;
  }

  /// Действующий пропуск или null, если получить его не вышло.
  Future<String?> token({bool refresh = false}) async {
    final now = DateTime.now();
    if (!refresh &&
        _token != null &&
        _expires != null &&
        _expires!.isAfter(now.add(const Duration(minutes: 1)))) {
      return _token;
    }
    lastProblem = null;
    if (!await supported) {
      lastProblem = 'App Attest недоступен на этом устройстве';
      return null;
    }

    try {
      final prefs = await _prefs;
      final keyId = prefs.getString(_keyIdPref);
      if (keyId == null) return await _register();
      try {
        return await _assert(keyId);
      } on _KeyForgotten {
        return await _register();
      }
    } on _Refused catch (e) {
      lastProblem = e.message;
    } on PlatformException catch (e) {
      lastProblem = 'Apple: ${e.message ?? e.code}';
    } on http.ClientException {
      lastProblem = 'нет связи с сервером';
    } on SocketException {
      lastProblem = 'нет связи с сервером';
    } on TimeoutException {
      lastProblem = 'сервер не ответил вовремя';
    } on FormatException {
      lastProblem = 'непонятный ответ сервера';
    } on TypeError {
      lastProblem = 'непонятный ответ сервера';
    } on _KeyForgotten {
      // Сервер не узнал ключ, который только что заверили. Второй круг здесь
      // не поможет — остаёмся без пропуска.
      lastProblem = 'сервер не узнал ключ устройства';
    }
    return null;
  }

  Future<String> _challenge() async {
    final res = await _client
        .post(Uri.parse('$_endpoint/attest/challenge'))
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw _Refused('челлендж: сервер ответил ${res.statusCode}');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['challenge'] as String;
  }

  Future<String?> _register() async {
    final challenge = await _challenge();
    final keyId = await _channel.invokeMethod<String>('generateKey');
    if (keyId == null) throw _Refused('Apple не выдал ключ');
    final attestation = await _channel.invokeMethod<String>('attestKey', {
      'keyId': keyId,
      'challenge': challenge,
    });
    if (attestation == null) throw _Refused('Apple не заверил ключ');
    final saved = await _post('/attest/register', {
      'keyId': keyId,
      'attestation': attestation,
      'challenge': challenge,
    });
    if (saved != null) await (await _prefs).setString(_keyIdPref, keyId);
    return saved;
  }

  Future<String?> _assert(String keyId) async {
    final challenge = await _challenge();
    final assertion = await _channel.invokeMethod<String>('generateAssertion', {
      'keyId': keyId,
      'challenge': challenge,
    });
    if (assertion == null) throw _Refused('Apple не подписал запрос');
    return _post('/attest/assert', {
      'keyId': keyId,
      'assertion': assertion,
      'challenge': challenge,
    });
  }

  Future<String?> _post(String path, Map<String, dynamic> body) async {
    final res = await _client.post(
      Uri.parse('$_endpoint$path'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(_timeout);
    if (res.statusCode == 404) throw _KeyForgotten();
    if (res.statusCode != 200) {
      // Сервер пишет, что именно не сошлось («сборка не из той среды»,
      // «заверение выдано другому приложению»), — это и нужно показать.
      String? why;
      try {
        final j =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        why = (j['detail'] ?? j['error']) as String?;
      } catch (_) {}
      final step = path.endsWith('register') ? 'заверение' : 'подпись';
      throw _Refused('$step: ${why ?? 'сервер ответил ${res.statusCode}'}');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    _token = j['token'] as String?;
    _expires = DateTime.now()
        .add(Duration(seconds: (j['expiresIn'] as num?)?.toInt() ?? 3600));
    return _token;
  }
}
