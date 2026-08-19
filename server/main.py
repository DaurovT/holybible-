"""Бэкенд разбора отрывков для HolyBible.

Приложение шлёт сюда `POST /explain` — отрывок, что именно спросили и
идентификаторы сущностей. Сервер достаёт по ним статьи и параллельные места из
bible.db, отдаёт модели как единственный источник и возвращает ответ со
ссылками. Ключ модели живёт только здесь: в бандл приложения его класть нельзя.

Формат запроса и ответа задан клиентом — lib/features/ai/ai_service.dart.
"""

import json
import os
import time
from collections import deque

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from sources import Source, SourceIndex

DB_PATH = os.environ.get('BIBLE_DB', 'data/bible.db')
ENDPOINT = os.environ['AZURE_AI_ENDPOINT'].rstrip('/')
API_KEY = os.environ['AZURE_AI_KEY']
MODEL = os.environ.get('AZURE_AI_MODEL', 'gpt-5.6-terra')

# Эндпоинт открыт в интернет, а каждый запрос стоит денег. Ограничение грубое,
# по адресу и на процесс: от случайного скрипта спасает, от настоящей нагрузки
# нужен токен приложения.
RATE_LIMIT = int(os.environ.get('RATE_LIMIT_PER_HOUR', '60'))
_hits: dict[str, deque[float]] = {}

# Общий секрет с приложением. Не защита от разбора бандла — оттуда его
# достанут, как и любой ключ, — но случайный прохожий по адресу туннеля
# ничего не потратит. Настоящая защита от воровства ключа в том, что ключ
# модели остаётся здесь.
APP_TOKEN = os.environ.get('APP_TOKEN', '')

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


app = FastAPI(title='HolyBible AI backend')
index = SourceIndex(DB_PATH)
client = httpx.AsyncClient(timeout=httpx.Timeout(120.0, connect=10.0))


@app.get('/health')
async def health() -> dict[str, object]:
    return {'ok': True, 'model': MODEL}


def _rate_limited(ip: str) -> bool:
    now = time.time()
    q = _hits.setdefault(ip, deque())
    while q and now - q[0] > 3600:
        q.popleft()
    if len(q) >= RATE_LIMIT:
        return True
    q.append(now)
    return False


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


async def _ask_model(prompt: str) -> tuple[str, list[str]]:
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
    raw = res.json()['choices'][0]['message']['content'] or ''
    try:
        parsed = json.loads(raw)
        return str(parsed.get('text', '')).strip(), [
            str(u) for u in parsed.get('used', []) or []]
    except (json.JSONDecodeError, AttributeError):
        # Модель ответила не JSON. Текст всё равно годный — отдаём его,
        # а ссылками показываем всё, что клали в запрос.
        return raw.strip(), []


@app.post('/explain')
async def explain(req: AiRequest, request: Request) -> JSONResponse:
    if APP_TOKEN and request.headers.get('x-app-token') != APP_TOKEN:
        return JSONResponse({'error': 'Неверный токен'}, status_code=401)

    ip = request.headers.get('cf-connecting-ip') or (
        request.client.host if request.client else '?')
    if _rate_limited(ip):
        return JSONResponse({'error': 'Слишком много запросов'}, status_code=429)

    sources = index.collect(req.entityIds, req.crossReferences)
    try:
        text, used = await _ask_model(_build_prompt(req, sources))
    except httpx.HTTPStatusError as e:
        return JSONResponse(
            {'error': f'Модель ответила {e.response.status_code}'},
            status_code=502)
    except httpx.HTTPError:
        return JSONResponse({'error': 'Модель недоступна'}, status_code=502)

    if not text:
        return JSONResponse({'error': 'Пустой ответ модели'}, status_code=502)

    # Ссылки собираем сами, из того что действительно уходило в запрос: так в
    # выдаче не появится источник, которого не было.
    chosen = [s for s in sources if s.sid in used] or sources
    seen: set[tuple[str, str]] = set()
    citations = []
    for s in chosen:
        key = (s.label, s.origin)
        if key in seen:
            continue
        seen.add(key)
        citations.append({'label': s.label, 'source': s.origin})

    return JSONResponse({'text': text, 'citations': citations})
