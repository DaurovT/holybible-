"""Бэкенд разбора отрывков для HolyBible.

Приложение шлёт сюда `POST /explain` — отрывок, что именно спросили и
идентификаторы сущностей. Сервер достаёт по ним статьи и параллельные места из
bible.db, отдаёт модели как единственный источник и возвращает ответ со
ссылками. Ключ модели живёт только здесь: в бандл приложения его класть нельзя.

Кто спрашивает — проверяется через App Attest (см. attest.py): устройство
доказывает, что приложение подлинное, и получает короткий пропуск. Общий
секрет в заголовке остаётся только как временный путь для симулятора и
выключается переменной ALLOW_APP_TOKEN.

Формат запроса и ответа задан клиентом — lib/features/ai/ai_service.dart.
"""

import base64
import json
import logging
import os
import secrets
import time
from pathlib import Path

import httpx
import jwt
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, Field

from attest import AppAttest, AttestError
from play_integrity import IntegrityError, PlayIntegrity
from sources import Source, SourceIndex
from store import Store

log = logging.getLogger('holybible')

DB_PATH = os.environ.get('BIBLE_DB', 'data/bible.db')
STATE_PATH = os.environ.get('STATE_DB', 'data/state.db')
ENDPOINT = os.environ['AZURE_AI_ENDPOINT'].rstrip('/')
API_KEY = os.environ['AZURE_AI_KEY']
MODEL = os.environ.get('AZURE_AI_MODEL', 'gpt-5.6-terra')

# App Attest. Без команды и идентификатора сборки проверять нечего.
TEAM_ID = os.environ.get('APPLE_TEAM_ID', '')
BUNDLE_ID = os.environ.get('APPLE_BUNDLE_ID', '')
ATTEST_ENV = os.environ.get('ATTEST_ENV', 'production')
JWT_SECRET = os.environ.get('JWT_SECRET', '')
TOKEN_TTL = int(os.environ.get('TOKEN_TTL', '86400'))

# Общий секрет с приложением. Он один на все копии: кто разберёт .ipa, получит
# его навсегда, и отозвать можно только сменив у всех сразу. Поэтому путь через
# него по умолчанию закрыт и включается вручную — на время работы в симуляторе,
# где App Attest недоступен.
APP_TOKEN = os.environ.get('APP_TOKEN', '')
ALLOW_APP_TOKEN = os.environ.get('ALLOW_APP_TOKEN', '0') == '1'

# Play Integrity — то же для Android (см. play_integrity.py). Пакет и отпечаток
# ключа подписи Play App Signing не секреты; ключ сервисного аккаунта Google
# Cloud — секрет и лежит только на сервере.
ANDROID_PACKAGE = os.environ.get('ANDROID_PACKAGE', 'com.holybible.holy_bible')
ANDROID_CERT_SHA256 = os.environ.get('ANDROID_CERT_SHA256', '')
PLAY_INTEGRITY_ENV = os.environ.get('PLAY_INTEGRITY_ENV', 'production')
PLAY_INTEGRITY_CREDENTIALS = os.environ.get('PLAY_INTEGRITY_CREDENTIALS', '')

# Квоты считаются по устройству, а не по адресу: телефоны за общим оператором
# делят один адрес и мешали бы друг другу.
PER_HOUR = int(os.environ.get('QUOTA_PER_HOUR', '40'))
PER_DAY = int(os.environ.get('QUOTA_PER_DAY', '200'))

# Потолок расходов на сутки — чтобы счёт не мог убежать в принципе.
DAILY_REQUESTS = int(os.environ.get('DAILY_REQUEST_CAP', '3000'))
DAILY_TOKENS = int(os.environ.get('DAILY_TOKEN_CAP', '3000000'))

# Кеш ответов. Отрывков, о которых спрашивают, немного, а вопросы к ним
# однотипные: «Ин 3:16 / простыми словами» стоит спросить у модели один раз.
CACHE_TTL = float(os.environ.get('CACHE_TTL_DAYS', '30')) * 86400

MODE_RU = {
    'explain': 'объяснение отрывка',
    'context': 'исторический и повествовательный контекст',
    'whyMatters': 'значение отрывка и его связи',
    'ask': 'вопрос читателя об отрывке',
}

SYSTEM = """\
Ты помогаешь читателю Библии разобраться в отрывке.

Отвечай только по источникам, которые даны в запросе. Если источников не
хватает, чтобы ответить, так и скажи — не восполняй пробел общими знаниями и
не придумывай подробностей, которых в источниках нет.

Правила:
— пиши по-русски, спокойно и без проповеди;
— не решай за читателя, во что ему верить, и не подталкивай к вере или от неё;
— где traditions расходятся, покажи расхождение, а не одну сторону;
— 2–4 абзаца, без списков, если читатель не просил разбора по пунктам;
— опирайся на текст самого отрывка, он дан целиком.

Верни JSON: {"text": "<ответ>", "used": ["<id использованных источников>"]}.
В used перечисли только те источники, на которые опирался."""


class AiRequest(BaseModel):
    mode: str = 'explain'
    instruction: str = ''
    reference: str = ''
    passage: str = ''
    entityIds: list[str] = Field(default_factory=list)
    crossReferences: list[str] = Field(default_factory=list)


class RegisterRequest(BaseModel):
    keyId: str
    attestation: str
    challenge: str


class AssertRequest(BaseModel):
    keyId: str
    assertion: str
    challenge: str


class AndroidAttestRequest(BaseModel):
    # Случайный идентификатор установки: по нему считаются квоты — так же, как
    # на iPhone по ключу App Attest.
    installId: str = Field(pattern=r'^[A-Za-z0-9_-]{16,64}$')
    challenge: str
    token: str = Field(max_length=16000)


app = FastAPI(title='HolyBible AI backend')
index = SourceIndex(DB_PATH)
store = Store(STATE_PATH)
attest = AppAttest(TEAM_ID, BUNDLE_ID, ATTEST_ENV)
client = httpx.AsyncClient(timeout=httpx.Timeout(120.0, connect=10.0))

ATTEST_READY = bool(TEAM_ID and BUNDLE_ID and JWT_SECRET)
if not ATTEST_READY:
    log.warning('App Attest выключен: не заданы APPLE_TEAM_ID, '
                'APPLE_BUNDLE_ID или JWT_SECRET')

integrity = PlayIntegrity(ANDROID_PACKAGE, ANDROID_CERT_SHA256.split(','),
                          PLAY_INTEGRITY_ENV, PLAY_INTEGRITY_CREDENTIALS)
ANDROID_READY = bool(integrity.ready and JWT_SECRET)
if not ANDROID_READY:
    log.warning('Play Integrity выключен: не задан PLAY_INTEGRITY_CREDENTIALS '
                'или JWT_SECRET')
elif PLAY_INTEGRITY_ENV == 'production' and not ANDROID_CERT_SHA256:
    log.warning('ANDROID_CERT_SHA256 не задан: подпись приложения не сверяется')


@app.get('/health')
async def health() -> dict[str, object]:
    return {
        'ok': True,
        'model': MODEL,
        'attest': ATTEST_READY,
        'appTokenAllowed': ALLOW_APP_TOKEN,
        # Не секреты: команда и идентификатор есть в любой копии приложения.
        # Зато по ним снаружи видно, с какой сборкой сервер согласится.
        'teamId': TEAM_ID,
        'bundleId': BUNDLE_ID,
        'attestEnv': ATTEST_ENV,
        'playIntegrity': ANDROID_READY,
        'playIntegrityEnv': PLAY_INTEGRITY_ENV,
        'androidPackage': ANDROID_PACKAGE,
        **store.stats(),
    }


# Политика конфиденциальности и страница поддержки. App Store Connect требует
# ссылки на обе, а своего сайта у приложения нет — отдаём их отсюда же, с того
# адреса, куда и так ходит разбор. Читаются на каждый запрос: правка текста не
# требует перезапуска.
PAGES_DIR = Path(__file__).parent


@app.get('/privacy', response_class=HTMLResponse)
async def privacy() -> HTMLResponse:
    return HTMLResponse((PAGES_DIR / 'privacy.html').read_text(encoding='utf-8'))


@app.get('/support', response_class=HTMLResponse)
async def support() -> HTMLResponse:
    return HTMLResponse((PAGES_DIR / 'support.html').read_text(encoding='utf-8'))


# --- App Attest ------------------------------------------------------------


@app.post('/attest/challenge')
async def challenge() -> dict[str, str]:
    """Одноразовые случайные байты. Устройство подпишет именно их."""
    nonce = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip('=')
    store.put_challenge(nonce)
    return {'challenge': nonce}


def _issue(key_id: str) -> dict[str, object]:
    now = int(time.time())
    token = jwt.encode({'sub': key_id, 'iat': now, 'exp': now + TOKEN_TTL},
                       JWT_SECRET, algorithm='HS256')
    return {'token': token, 'expiresIn': TOKEN_TTL}


@app.post('/attest/register')
async def register(req: RegisterRequest) -> JSONResponse:
    """Один раз за установку: заверение ключа от Apple."""
    if not ATTEST_READY:
        return JSONResponse({'error': 'Проверка устройств не настроена'},
                            status_code=503)
    if not store.take_challenge(req.challenge):
        return JSONResponse({'error': 'Челлендж просрочен'}, status_code=400)
    try:
        key_id = base64.b64decode(req.keyId)
        public_key, counter = attest.verify_attestation(
            key_id, base64.b64decode(req.attestation), req.challenge.encode())
    except AttestError as e:
        log.warning('заверение отклонено: %s', e)
        # Причина уходит клиенту: подделать заверение она не помогает, а без
        # неё сбой настройки («не та среда», «другая команда») не отличить от
        # чужого приложения.
        return JSONResponse({'error': 'Устройство не подтверждено',
                             'detail': str(e)}, status_code=401)
    except Exception as e:  # noqa: BLE001 — битый вход не должен ронять сервер
        log.warning('заверение не разобрано: %s', e)
        return JSONResponse({'error': 'Заверение не разобрано'}, status_code=400)
    store.add_device(req.keyId, public_key, counter)
    return JSONResponse(_issue(req.keyId))


@app.post('/attest/assert')
async def assert_key(req: AssertRequest) -> JSONResponse:
    """Каждый следующий заход: подпись свежего челленджа известным ключом."""
    if not ATTEST_READY:
        return JSONResponse({'error': 'Проверка устройств не настроена'},
                            status_code=503)
    if not store.take_challenge(req.challenge):
        return JSONResponse({'error': 'Челлендж просрочен'}, status_code=400)
    known = store.device(req.keyId)
    if not known:
        # Ключ сервер не знает: приложение переустановили или база потеряна.
        return JSONResponse({'error': 'Ключ неизвестен'}, status_code=404)
    public_key, counter, blocked = known
    if blocked:
        return JSONResponse({'error': 'Устройство заблокировано'},
                            status_code=403)
    try:
        counter = attest.verify_assertion(
            public_key, base64.b64decode(req.assertion),
            req.challenge.encode(), counter)
    except AttestError as e:
        log.warning('подпись отклонена: %s', e)
        return JSONResponse({'error': 'Подпись не принята', 'detail': str(e)},
                            status_code=401)
    except Exception as e:  # noqa: BLE001
        log.warning('подпись не разобрана: %s', e)
        return JSONResponse({'error': 'Подпись не разобрана'}, status_code=400)
    store.bump_counter(req.keyId, counter)
    return JSONResponse(_issue(req.keyId))


@app.post('/attest/android')
async def attest_android(req: AndroidAttestRequest) -> JSONResponse:
    """Android: вердикт Google Play вместо заверения Apple.

    Вердикт одноразовый и привязан к челленджу, так что пропуск выдаётся на
    каждый новый вердикт — отдельного «подписать ещё раз», как у App Attest,
    здесь нет.
    """
    if not ANDROID_READY:
        return JSONResponse({'error': 'Проверка устройств Android не настроена'},
                            status_code=503)
    if not store.take_challenge(req.challenge):
        return JSONResponse({'error': 'Челлендж просрочен'}, status_code=400)
    key_id = f'android:{req.installId}'
    known = store.device(key_id)
    if known and known[2]:
        return JSONResponse({'error': 'Устройство заблокировано'},
                            status_code=403)
    try:
        payload = await integrity.decode(client, req.token)
        integrity.check(payload, req.challenge)
    except IntegrityError as e:
        log.warning('вердикт Play Integrity отклонён: %s', e)
        return JSONResponse({'error': 'Устройство не подтверждено',
                             'detail': str(e)}, status_code=401)
    except httpx.HTTPStatusError as e:
        log.warning('Play Integrity ответил %s: %s', e.response.status_code,
                    e.response.text[:300])
        return JSONResponse(
            {'error': 'Google не проверил устройство',
             'detail': f'Play Integrity ответил {e.response.status_code}'},
            status_code=502)
    except httpx.HTTPError as e:
        log.warning('Play Integrity недоступен: %s', e)
        return JSONResponse({'error': 'Google не проверил устройство',
                             'detail': 'Play Integrity недоступен'},
                            status_code=502)
    if known:
        store.bump_counter(key_id, 0)
    else:
        store.add_device(key_id, b'', 0)
    return JSONResponse(_issue(key_id))


def _caller(request: Request) -> tuple[str, JSONResponse | None]:
    """Кто спрашивает. Возвращает идентификатор устройства или отказ."""
    auth = request.headers.get('authorization', '')
    if auth.startswith('Bearer ') and JWT_SECRET:
        try:
            claims = jwt.decode(auth[7:], JWT_SECRET, algorithms=['HS256'])
            return str(claims['sub']), None
        except jwt.PyJWTError:
            return '', JSONResponse({'error': 'Пропуск просрочен'},
                                    status_code=401)
    if ALLOW_APP_TOKEN and APP_TOKEN and \
            request.headers.get('x-app-token') == APP_TOKEN:
        # Запасной путь для симулятора: считаем такие запросы одним «устройством»,
        # чтобы квота на них всё равно действовала.
        return 'app-token', None
    return '', JSONResponse({'error': 'Устройство не подтверждено'},
                            status_code=401)


# --- разбор ----------------------------------------------------------------


def _build_prompt(req: AiRequest, sources: list[Source]) -> str:
    parts = [f'Запрос читателя: {MODE_RU.get(req.mode, req.mode)}.']
    if req.instruction:
        parts.append(f'Что именно спросили: {req.instruction}')
    parts.append(f'\nОтрывок ({req.reference or "без ссылки"}):\n{req.passage}')
    if sources:
        parts.append('\nИсточники:')
        for s in sources:
            parts.append(f'[{s.sid}] {s.label} — {s.origin}\n{s.text}')
    else:
        parts.append('\nИсточников по этому отрывку в базе нет: '
                     'отвечай только по тексту самого отрывка.')
    return '\n\n'.join(parts)


async def _ask_model(prompt: str) -> tuple[str, list[str], tuple[int, int]]:
    res = await client.post(
        f'{ENDPOINT}/openai/v1/chat/completions',
        headers={'api-key': API_KEY, 'content-type': 'application/json'},
        json={
            'model': MODEL,
            'messages': [
                {'role': 'system', 'content': SYSTEM},
                {'role': 'user', 'content': prompt},
            ],
            'response_format': {'type': 'json_object'},
        },
    )
    res.raise_for_status()
    body = res.json()
    usage = body.get('usage') or {}
    spent = (int(usage.get('prompt_tokens', 0)),
             int(usage.get('completion_tokens', 0)))
    raw = body['choices'][0]['message']['content'] or ''
    try:
        parsed = json.loads(raw)
        return str(parsed.get('text', '')).strip(), [
            str(u) for u in parsed.get('used', []) or []], spent
    except (json.JSONDecodeError, AttributeError):
        # Модель ответила не JSON. Текст всё равно годный — отдаём его,
        # а ссылками показываем всё, что клали в запрос.
        return raw.strip(), [], spent


@app.post('/explain')
async def explain(req: AiRequest, request: Request) -> JSONResponse:
    device, denied = _caller(request)
    if denied is not None:
        return denied

    key = store.cache_key({
        'mode': req.mode, 'instruction': req.instruction,
        'reference': req.reference, 'passage': req.passage,
        'entityIds': sorted(req.entityIds),
        'crossReferences': sorted(req.crossReferences),
        'model': MODEL,
    })
    hit = store.cached(key, CACHE_TTL)
    if hit is not None:
        # Из кеша отдаём мимо квоты и мимо счёта: этот ответ ничего не стоит.
        return JSONResponse(hit)

    reason = store.over_quota(device, PER_HOUR, PER_DAY)
    if reason:
        return JSONResponse(
            {'error': f'Слишком много разборов за {reason}. '
                      'Попробуйте позже — офлайновые разделы работают как обычно.'},
            status_code=429)

    requests_today, tokens_today = store.spent_today()
    if requests_today >= DAILY_REQUESTS or tokens_today >= DAILY_TOKENS:
        log.warning('дневной потолок расходов достигнут: %s запросов, %s токенов',
                    requests_today, tokens_today)
        return JSONResponse(
            {'error': 'Разбор сегодня недоступен: исчерпан дневной лимит. '
                      'Всё остальное в приложении работает без сети.'},
            status_code=503)

    sources = index.collect(req.entityIds, req.crossReferences)
    try:
        text, used, spent = await _ask_model(_build_prompt(req, sources))
    except httpx.HTTPStatusError as e:
        return JSONResponse(
            {'error': f'Модель ответила {e.response.status_code}'},
            status_code=502)
    except httpx.HTTPError:
        return JSONResponse({'error': 'Модель недоступна'}, status_code=502)

    store.add_spend(*spent)

    if not text:
        return JSONResponse({'error': 'Пустой ответ модели'}, status_code=502)

    # Ссылки собираем сами, из того что действительно уходило в запрос: так в
    # выдаче не появится источник, которого не было.
    chosen = [s for s in sources if s.sid in used] or sources
    seen: set[tuple[str, str]] = set()
    citations = []
    for s in chosen:
        label = (s.label, s.origin)
        if label in seen:
            continue
        seen.add(label)
        citations.append({'label': s.label, 'source': s.origin})

    answer = {'text': text, 'citations': citations}
    store.put_cache(key, answer)
    return JSONResponse(answer)
