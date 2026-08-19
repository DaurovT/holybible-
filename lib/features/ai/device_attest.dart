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

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Ключ не найден на сервере: приложение переустановили или сервер потерял
/// базу устройств. Лечится повторным заверением.
class _KeyForgotten implements Exception {}

class DeviceAttest {
  DeviceAttest(this._client, this._endpoint);

  static const _channel = MethodChannel('holybible/app_attest');
  static const _keyIdPref = 'attest_key_id';

  final http.Client _client;
  final String _endpoint;

  SharedPreferences? _cached;
  Future<SharedPreferences> get _prefs async =>
      _cached ??= await SharedPreferences.getInstance();

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
    if (!await supported) return null;

    try {
      final prefs = await _prefs;
      final keyId = prefs.getString(_keyIdPref);
      if (keyId == null) return await _register();
      try {
        return await _assert(keyId);
      } on _KeyForgotten {
        return await _register();
      }
    } on PlatformException {
      return null;
    } on http.ClientException {
      return null;
    }
  }

  Future<String> _challenge() async {
    final res = await _client.post(Uri.parse('$_endpoint/attest/challenge'));
    if (res.statusCode != 200) {
      throw http.ClientException('челлендж: ${res.statusCode}');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['challenge'] as String;
  }

  Future<String?> _register() async {
    final challenge = await _challenge();
    final keyId = await _channel.invokeMethod<String>('generateKey');
    if (keyId == null) return null;
    final attestation = await _channel.invokeMethod<String>('attestKey', {
      'keyId': keyId,
      'challenge': challenge,
    });
    if (attestation == null) return null;
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
    if (assertion == null) return null;
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
    );
    if (res.statusCode == 404) throw _KeyForgotten();
    if (res.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    _token = j['token'] as String?;
    _expires = DateTime.now()
        .add(Duration(seconds: (j['expiresIn'] as num?)?.toInt() ?? 3600));
    return _token;
  }
}
