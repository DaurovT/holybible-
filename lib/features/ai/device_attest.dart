/// Доказательство, что запрос идёт из подлинного приложения.
///
/// Общий секрет в бандле защищает ровно до первого, кто разберёт сборку.
/// Поэтому подлинность подтверждает сама платформа, а сервер, проверив это,
/// выдаёт короткий пропуск — его и предъявляем при разборе отрывка.
///
/// - iPhone — App Attest. Устройство заводит ключ в защищённом элементе, Apple
///   заверяет его, и наружу ключ не выходит. Ключ заводится один раз за
///   установку, дальше на каждый пропуск подписывается свежий челлендж.
/// - Android — Play Integrity. Google Play выдаёт вердикт о приложении и
///   устройстве, привязанный к челленджу, сервер отдаёт его Google на проверку.
///   Вердикт одноразовый, так что на каждый пропуск он запрашивается заново.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Номер проекта Google Cloud, привязанного к приложению в Play Console.
/// Задаётся при сборке: `--dart-define=PLAY_CLOUD_PROJECT=…`. Не секрет: по
/// нему Google Play понимает, чей вердикт выдавать.
const playCloudProject = String.fromEnvironment('PLAY_CLOUD_PROJECT');

/// Чем подтверждается подлинность.
enum AttestPlatform { apple, android, none }

/// Ключ не найден на сервере: приложение переустановили или сервер потерял
/// базу устройств. Лечится повторным заверением.
class _KeyForgotten implements Exception {}

/// Шаг заверения не прошёл по понятной причине — она уходит в [lastProblem].
class _Refused implements Exception {
  _Refused(this.message);
  final String message;
}

class DeviceAttest {
  DeviceAttest(
    this._client,
    this._endpoint, {
    AttestPlatform? platform,
    String cloudProject = playCloudProject,
  })  : _platform = platform ??
            (Platform.isIOS
                ? AttestPlatform.apple
                : Platform.isAndroid
                    ? AttestPlatform.android
                    : AttestPlatform.none),
        _cloudProject = cloudProject;

  static const _appleChannel = MethodChannel('holybible/app_attest');
  static const _playChannel = MethodChannel('holybible/play_integrity');
  static const _keyIdPref = 'attest_key_id';
  static const _installIdPref = 'install_id';

  /// Предел ожидания на каждый шаг заверения: без него пропавшая сеть
  /// подвешивает разбор навсегда.
  static const _timeout = Duration(seconds: 20);

  final http.Client _client;
  final String _endpoint;
  final AttestPlatform _platform;
  final String _cloudProject;

  SharedPreferences? _cached;
  Future<SharedPreferences> get _prefs async =>
      _cached ??= await SharedPreferences.getInstance();

  /// Почему последний раз не удалось получить пропуск. Без этого любой сбой —
  /// другая команда в подписи, не та среда, отказ Apple или Google, пропавшая
  /// сеть — выглядит одинаково: «устройство не подтверждено», и чинить
  /// приходится вслепую.
  String? lastProblem;

  String? _token;
  DateTime? _expires;
  bool? _supported;

  /// Может ли эта сборка вообще доказать подлинность. На iPhone — всегда (в
  /// симуляторе App Attest нет, но там выручает запасной секрет). На Android —
  /// только если при сборке задан проект Google Cloud: без него каждый разбор
  /// кончался бы отказом, и кнопок разбора лучше не показывать вовсе.
  bool get available => switch (_platform) {
        AttestPlatform.apple => true,
        AttestPlatform.android => _cloudProject.isNotEmpty,
        AttestPlatform.none => false,
      };

  String get _vendor => _platform == AttestPlatform.android ? 'Google Play' : 'Apple';

  /// На симуляторе и на старых iPhone App Attest недоступен. Это не ошибка:
  /// вызывающий просто останется без пропуска.
  Future<bool> get supported async {
    if (_supported != null) return _supported!;
    switch (_platform) {
      case AttestPlatform.android:
        _supported = available;
      case AttestPlatform.none:
        _supported = false;
      case AttestPlatform.apple:
        try {
          _supported =
              await _appleChannel.invokeMethod<bool>('isSupported') ?? false;
        } on PlatformException {
          _supported = false;
        } on MissingPluginException {
          _supported = false;
        }
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
      lastProblem = _platform == AttestPlatform.android
          ? 'сборка без проекта Google Cloud (PLAY_CLOUD_PROJECT)'
          : 'App Attest недоступен на этом устройстве';
      return null;
    }

    try {
      if (_platform == AttestPlatform.android) return await _android();
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
      lastProblem = _platform == AttestPlatform.android
          ? _playProblem(e)
          : 'Apple: ${e.message ?? e.code}';
    } on MissingPluginException {
      lastProblem = 'в сборке нет моста к $_vendor';
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

  // --- iPhone: App Attest ---------------------------------------------------

  Future<String?> _register() async {
    final challenge = await _challenge();
    final keyId = await _appleChannel.invokeMethod<String>('generateKey');
    if (keyId == null) throw _Refused('Apple не выдал ключ');
    final attestation = await _appleChannel.invokeMethod<String>('attestKey', {
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
    final assertion =
        await _appleChannel.invokeMethod<String>('generateAssertion', {
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

  // --- Android: Play Integrity ----------------------------------------------

  Future<String?> _android() async {
    final challenge = await _challenge();
    // Первый вердикт за запуск ждёт подготовки провайдера — до нескольких
    // секунд, поэтому предел здесь вдвое больше обычного.
    final verdict = await _playChannel.invokeMethod<String>('requestToken', {
      'cloudProjectNumber': _cloudProject,
      'requestHash': challenge,
    }).timeout(_timeout * 2);
    if (verdict == null) throw _Refused('Google Play не выдал вердикт');
    return _post('/attest/android', {
      'installId': await _installId(),
      'challenge': challenge,
      'token': verdict,
    });
  }

  /// Ошибка Play Integrity по-человечески.
  ///
  /// Google присылает длинный английский текст со ссылкой на документацию —
  /// на экране телефона это стена. Показываем суть и код: по нему ошибку
  /// легко найти. Коды — StandardIntegrityErrorCode из библиотеки 1.6.0.
  static String _playProblem(PlatformException e) {
    final code = int.tryParse(e.code.replaceFirst('integrity_', ''));
    final what = switch (code) {
      -1 => 'проверка недоступна на этом устройстве',
      -2 => 'на устройстве нет Google Play',
      -3 => 'нет связи с Google Play',
      -5 => 'приложение не установлено через Google Play',
      -6 => 'на устройстве нет сервисов Google Play',
      -7 => 'проверка запрошена не этим приложением',
      -8 => 'слишком много проверок, попробуйте позже',
      -9 => 'Google Play не отвечает',
      -12 => 'серверы Google недоступны',
      -14 => 'обновите Google Play',
      -15 => 'обновите сервисы Google Play',
      -16 => 'в сборке неверный номер проекта Google Cloud',
      -17 => 'слишком длинный запрос',
      -18 || -19 => 'временный сбой, попробуйте ещё раз',
      -100 => 'внутренняя ошибка Google Play',
      _ => null,
    };
    if (what != null) return 'Google Play: $what ($code)';
    return 'Google Play: ошибка ${code ?? e.code}';
  }

  /// Случайный идентификатор установки. По нему сервер считает квоты: ключа,
  /// как у App Attest, на Android нет, а вердикт одноразовый.
  Future<String> _installId() async {
    final prefs = await _prefs;
    final saved = prefs.getString(_installIdPref);
    if (saved != null) return saved;
    final random = Random.secure();
    // 18 байт — ровно 24 знака base64 без дополнения.
    final id = base64Url.encode(List<int>.generate(18, (_) => random.nextInt(256)));
    await prefs.setString(_installIdPref, id);
    return id;
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
      // «приложение не признано Google Play»), — это и нужно показать.
      String? why;
      try {
        final j =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        why = (j['detail'] ?? j['error']) as String?;
      } catch (_) {}
      final step = switch (path) {
        '/attest/register' => 'заверение',
        '/attest/android' => 'проверка Google Play',
        _ => 'подпись',
      };
      throw _Refused('$step: ${why ?? 'сервер ответил ${res.statusCode}'}');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    _token = j['token'] as String?;
    _expires = DateTime.now()
        .add(Duration(seconds: (j['expiresIn'] as num?)?.toInt() ?? 3600));
    return _token;
  }
}
