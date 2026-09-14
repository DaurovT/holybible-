"""Проверка Play Integrity — Android-аналог App Attest.

App Attest есть только у Apple. На Android подлинность приложения подтверждает
Google Play: приложение просит у Play вердикт, привязанный к нашему
одноразовому челленджу, и отдаёт его серверу как есть. Вердикт зашифрован и
подписан Google, расшифровывает его тоже Google: сервер отправляет токен в
Play Integrity API от имени сервисного аккаунта и получает ответ открытым
текстом. Ключ сервисного аккаунта лежит только здесь.

Что проверяется в вердикте:

1. запрос от нашего пакета, с нашим челленджем и свежий;
2. приложение признано Google Play — установлено из Play и подписано нашим
   ключом подписи (ключ Play App Signing, а не ключ загрузки);
3. устройство честное: MEETS_DEVICE_INTEGRITY.

В среде development пропускаются сборки не из Play (UNRECOGNIZED_VERSION) и
устройства только с базовой целостностью — так проверяется сборка,
поставленная через adb, и эмулятор. В бою — production.

Поля — по документации «Play Integrity API: make a standard API request».
"""

import base64
import json
import logging
import time

import httpx
import jwt

log = logging.getLogger('play_integrity')

TOKEN_SCOPE = 'https://www.googleapis.com/auth/playintegrity'
TOKEN_URI = 'https://oauth2.googleapis.com/token'
DECODE_URL = 'https://playintegrity.googleapis.com/v1/{package}:decodeIntegrityToken'

# Сколько может пройти между выдачей вердикта и проверкой. Челлендж сам живёт
# пять минут, дольше ждать незачем.
MAX_AGE_MS = 5 * 60 * 1000

# Вердикты об устройстве вложены друг в друга: сильная целостность включает
# обычную, обычная — базовую.
DEVICE_LEVELS = {
    'MEETS_BASIC_INTEGRITY': 1,
    'MEETS_DEVICE_INTEGRITY': 2,
    'MEETS_STRONG_INTEGRITY': 3,
}


class IntegrityError(Exception):
    """Вердикт не подходит. Текст уходит в журнал и приложению."""


def digest_forms(value: str) -> set[str]:
    """Отпечаток сертификата во всех видах, в которых он встречается.

    Play Console показывает SHA-256 шестнадцатеричным с двоеточиями, а в
    вердикте он в base64 без дополнения. Сравниваем по любому.
    """
    raw = value.strip()
    forms = {raw}
    try:
        data = bytes.fromhex(raw.replace(':', ''))
    except ValueError:
        return forms
    if len(data) == 32:
        forms |= {
            data.hex(),
            base64.urlsafe_b64encode(data).decode().rstrip('='),
            base64.b64encode(data).decode().rstrip('='),
        }
    return forms


class PlayIntegrity:
    def __init__(self, package: str, cert_digests: list[str], environment: str,
                 credentials_path: str) -> None:
        self.package = package
        self.environment = environment
        self.certs: set[str] = set()
        for digest in cert_digests:
            if digest.strip():
                self.certs |= digest_forms(digest)
        self._credentials: dict[str, str] | None = None
        if credentials_path:
            try:
                with open(credentials_path, encoding='utf-8') as f:
                    self._credentials = json.load(f)
            except (OSError, json.JSONDecodeError) as e:
                log.warning('ключ сервисного аккаунта не прочитан: %s', e)
        self._access: str | None = None
        self._access_until = 0.0

    @property
    def ready(self) -> bool:
        return bool(self.package and self._credentials)

    # --- доступ к Google ----------------------------------------------------

    def assertion(self, now: float | None = None) -> str:
        """Подписанный ключом сервисного аккаунта JWT для обмена на доступ."""
        assert self._credentials is not None
        issued = int(now if now is not None else time.time())
        c = self._credentials
        headers = {'kid': c['private_key_id']} if c.get('private_key_id') else None
        return jwt.encode(
            {
                'iss': c['client_email'],
                'scope': TOKEN_SCOPE,
                'aud': c.get('token_uri', TOKEN_URI),
                'iat': issued,
                'exp': issued + 3600,
            },
            c['private_key'],
            algorithm='RS256',
            headers=headers,
        )

    async def _access_token(self, client: httpx.AsyncClient) -> str:
        if self._access and time.time() < self._access_until - 60:
            return self._access
        assert self._credentials is not None
        res = await client.post(
            self._credentials.get('token_uri', TOKEN_URI),
            data={
                'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion': self.assertion(),
            },
            timeout=15.0,
        )
        res.raise_for_status()
        body = res.json()
        self._access = str(body['access_token'])
        self._access_until = time.time() + int(body.get('expires_in', 3600))
        return self._access

    async def decode(self, client: httpx.AsyncClient, token: str) -> dict:
        """Отдаёт токен Google и возвращает вердикт открытым текстом."""
        for attempt in range(2):
            access = await self._access_token(client)
            res = await client.post(
                DECODE_URL.format(package=self.package),
                headers={'authorization': f'Bearer {access}'},
                json={'integrity_token': token},
                timeout=15.0,
            )
            if res.status_code == 401 and attempt == 0:
                # Доступ отозвали раньше срока — берём новый и пробуем ещё раз.
                self._access = None
                continue
            if res.status_code == 400:
                raise IntegrityError('Google не принял вердикт: токен битый или чужой')
            res.raise_for_status()
            payload = res.json().get('tokenPayloadExternal')
            if not isinstance(payload, dict):
                raise IntegrityError('в ответе Google нет вердикта')
            return payload
        raise IntegrityError('Google не пустил сервисный аккаунт')

    # --- сам вердикт ----------------------------------------------------------

    def check(self, payload: dict, challenge: str, now_ms: int | None = None) -> None:
        """Проходит молча или бросает IntegrityError с причиной."""
        production = self.environment == 'production'
        now_ms = now_ms if now_ms is not None else int(time.time() * 1000)

        request = payload.get('requestDetails') or {}
        if request.get('requestPackageName') != self.package:
            raise IntegrityError(
                f'вердикт выдан другому приложению: {request.get("requestPackageName")}')
        if request.get('requestHash') != challenge:
            raise IntegrityError('челлендж не совпал — вердикт чужой или повторный')
        try:
            issued = int(request.get('timestampMillis', 0))
        except (TypeError, ValueError):
            issued = 0
        if abs(now_ms - issued) > MAX_AGE_MS:
            raise IntegrityError('вердикт устарел')

        app = payload.get('appIntegrity') or {}
        verdict = app.get('appRecognitionVerdict')
        allowed = {'PLAY_RECOGNIZED'} if production else {
            'PLAY_RECOGNIZED', 'UNRECOGNIZED_VERSION'}
        if verdict not in allowed:
            raise IntegrityError(f'приложение не признано Google Play: {verdict}')
        if app.get('packageName') and app['packageName'] != self.package:
            raise IntegrityError('вердикт о другом пакете')
        if verdict == 'PLAY_RECOGNIZED' and self.certs:
            if not set(app.get('certificateSha256Digest') or []) & self.certs:
                raise IntegrityError('приложение подписано не нашим ключом')

        device = (payload.get('deviceIntegrity') or {}).get(
            'deviceRecognitionVerdict') or []
        level = max((DEVICE_LEVELS.get(v, 0) for v in device), default=0)
        if level < (2 if production else 1):
            raise IntegrityError(
                'устройство не прошло проверку Google Play: '
                f'{", ".join(device) or "вердикта нет"}')
