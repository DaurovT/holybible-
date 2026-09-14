"""Проверки Play Integrity.

Сам вердикт подписывает и расшифровывает Google — подделать его здесь нельзя,
и не нужно. Проверяется то, что делает сервер: правила приёма вердикта,
подпись запроса к Google и маршрут /attest/android целиком — с вердиктом,
подставленным вместо ответа Google.

Запуск: `.venv/bin/python test_play_integrity.py`
"""

import base64
import json
import os
import tempfile
import time

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from play_integrity import IntegrityError, PlayIntegrity, digest_forms

PACKAGE = 'com.holybible.holy_bible'
CERT = bytes(range(32))
CERT_HEX = ':'.join(f'{b:02X}' for b in CERT)  # так его показывает Play Console
CERT_B64 = base64.urlsafe_b64encode(CERT).decode().rstrip('=')  # так — вердикт
SA_EMAIL = 'bot@holybible.iam.gserviceaccount.com'


def credentials(tmp: str):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = key.private_bytes(serialization.Encoding.PEM,
                            serialization.PrivateFormat.PKCS8,
                            serialization.NoEncryption()).decode()
    path = os.path.join(tmp, 'service-account.json')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump({'client_email': SA_EMAIL, 'private_key': pem,
                   'private_key_id': 'k1',
                   'token_uri': 'https://oauth2.googleapis.com/token'}, f)
    return path, key.public_key()


def verdict(challenge: str, now_ms: int, **changes) -> dict:
    """Вердикт честного устройства; `раздел__поле=значение` портит одно поле."""
    payload = {
        'requestDetails': {'requestPackageName': PACKAGE,
                           'requestHash': challenge,
                           'timestampMillis': str(now_ms)},
        'appIntegrity': {'appRecognitionVerdict': 'PLAY_RECOGNIZED',
                         'packageName': PACKAGE,
                         'certificateSha256Digest': [CERT_B64],
                         'versionCode': '1'},
        'deviceIntegrity': {'deviceRecognitionVerdict': ['MEETS_DEVICE_INTEGRITY']},
    }
    for name, value in changes.items():
        section, field = name.split('__')
        payload[section][field] = value
    return payload


def refused(check, reason: str) -> None:
    try:
        check()
    except IntegrityError as e:
        assert reason in str(e), f'ждали «{reason}», а причина «{e}»'
        return
    raise AssertionError(f'вердикт должен был не пройти: {reason}')


def rules(tmp: str) -> None:
    path, public = credentials(tmp)
    prod = PlayIntegrity(PACKAGE, [CERT_HEX], 'production', path)
    dev = PlayIntegrity(PACKAGE, [CERT_HEX], 'development', path)
    assert prod.ready
    now = int(time.time() * 1000)
    ch = 'challenge-abc'

    assert CERT_B64 in digest_forms(CERT_HEX)
    prod.check(verdict(ch, now), ch, now)
    prod.check(verdict(ch, now, deviceIntegrity__deviceRecognitionVerdict=[
        'MEETS_BASIC_INTEGRITY', 'MEETS_DEVICE_INTEGRITY', 'MEETS_STRONG_INTEGRITY']), ch, now)

    refused(lambda: prod.check(verdict(
        ch, now, requestDetails__requestPackageName='com.evil'), ch, now), 'другому приложению')
    refused(lambda: prod.check(verdict('other', now), ch, now), 'челлендж не совпал')
    refused(lambda: prod.check(verdict(ch, now - 6 * 60 * 1000), ch, now), 'устарел')
    refused(lambda: prod.check(verdict(
        ch, now, appIntegrity__certificateSha256Digest=['AAAA']), ch, now), 'не нашим ключом')
    refused(lambda: prod.check(verdict(
        ch, now, appIntegrity__appRecognitionVerdict='UNRECOGNIZED_VERSION'), ch, now), 'не признано')
    refused(lambda: prod.check(verdict(
        ch, now, deviceIntegrity__deviceRecognitionVerdict=['MEETS_BASIC_INTEGRITY']), ch, now),
        'устройство не прошло')
    refused(lambda: prod.check(verdict(
        ch, now, deviceIntegrity__deviceRecognitionVerdict=[]), ch, now), 'вердикта нет')

    # В разработке пропускаем сборку не из Play и эмулятор с базовой
    # целостностью — но не «не оценено».
    dev.check(verdict(ch, now,
                      appIntegrity__appRecognitionVerdict='UNRECOGNIZED_VERSION',
                      appIntegrity__certificateSha256Digest=['debug-key'],
                      deviceIntegrity__deviceRecognitionVerdict=['MEETS_BASIC_INTEGRITY']), ch, now)
    refused(lambda: dev.check(verdict(
        ch, now, appIntegrity__appRecognitionVerdict='UNEVALUATED'), ch, now), 'не признано')

    assertion = prod.assertion()
    claims = jwt.decode(assertion, public, algorithms=['RS256'],
                        audience='https://oauth2.googleapis.com/token')
    assert claims['iss'] == SA_EMAIL
    assert claims['scope'] == 'https://www.googleapis.com/auth/playintegrity'
    assert jwt.get_unverified_header(assertion)['kid'] == 'k1'
    print('  правила вердикта и подпись запроса к Google — сходится')


def route(tmp: str) -> None:
    path, _ = credentials(tmp)
    here = os.path.dirname(os.path.abspath(__file__))
    os.environ.update({
        'AZURE_AI_ENDPOINT': 'https://model.invalid',
        'AZURE_AI_KEY': 'test',
        'BIBLE_DB': os.path.join(here, '..', 'assets', 'db', 'bible.db'),
        'STATE_DB': os.path.join(tmp, 'state.db'),
        'JWT_SECRET': 'test-secret',
        'PLAY_INTEGRITY_CREDENTIALS': path,
        'ANDROID_CERT_SHA256': CERT_HEX,
        'PLAY_INTEGRITY_ENV': 'production',
    })
    from fastapi.testclient import TestClient

    import main

    answers: dict[str, dict] = {}

    async def google(_client, token: str) -> dict:
        return answers[token]

    main.integrity.decode = google
    api = TestClient(main.app)

    health = api.get('/health').json()
    assert health['playIntegrity'] is True, health
    assert health['androidPackage'] == PACKAGE

    install = 'AbCdEfGhIjKlMnOpQrStUvWx'
    ch = api.post('/attest/challenge').json()['challenge']
    answers['honest'] = verdict(ch, int(time.time() * 1000))
    ok = api.post('/attest/android',
                  json={'installId': install, 'challenge': ch, 'token': 'honest'})
    assert ok.status_code == 200, ok.text
    claims = jwt.decode(ok.json()['token'], 'test-secret', algorithms=['HS256'])
    assert claims['sub'] == f'android:{install}'

    again = api.post('/attest/android',
                     json={'installId': install, 'challenge': ch, 'token': 'honest'})
    assert again.status_code == 400, 'тот же челлендж второй раз не принимают'

    ch2 = api.post('/attest/challenge').json()['challenge']
    answers['emulator'] = verdict(
        ch2, int(time.time() * 1000),
        deviceIntegrity__deviceRecognitionVerdict=['MEETS_BASIC_INTEGRITY'])
    bad = api.post('/attest/android',
                   json={'installId': install, 'challenge': ch2, 'token': 'emulator'})
    assert bad.status_code == 401, bad.text
    assert 'устройство не прошло' in bad.json()['detail'], bad.text

    ch3 = api.post('/attest/challenge').json()['challenge']
    junk = api.post('/attest/android',
                    json={'installId': '../../etc', 'challenge': ch3, 'token': 'honest'})
    assert junk.status_code == 422, 'кривой идентификатор установки отсекается сразу'

    # Пропуск открывает разбор: дальше запрос упирается уже в модель (её в
    # тесте нет), а не в «устройство не подтверждено».
    explain = api.post('/explain',
                       headers={'authorization': f'Bearer {ok.json()["token"]}'},
                       json={'mode': 'explain', 'reference': 'Ин 3:16',
                             'passage': 'Ибо так возлюбил Бог мир'})
    assert explain.status_code != 401, explain.text
    print('  маршрут /attest/android и пропуск к разбору — сходится')


def run() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        rules(tmp)
        route(tmp)
    print('play integrity: всё сходится')


if __name__ == '__main__':
    run()
