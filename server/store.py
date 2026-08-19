"""Состояние сервера: устройства, квоты, кеш ответов и расходы.

Отдельная база `state.db` рядом с `bible.db`. Смешивать их нельзя: `bible.db`
приезжает из репозитория и перезаписывается при обновлении данных, а здесь
лежит то, что накопил живой сервер.

Всё синхронное и на sqlite3 — нагрузка тут измеряется запросами в минуту, а не
в секунду, и отдельная база данных ради этого не нужна.
"""

import hashlib
import json
import os
import sqlite3
import threading
import time

SCHEMA = """
CREATE TABLE IF NOT EXISTS devices (
  key_id      TEXT PRIMARY KEY,
  public_key  BLOB NOT NULL,
  counter     INTEGER NOT NULL DEFAULT 0,
  created_at  REAL NOT NULL,
  last_seen   REAL NOT NULL,
  blocked     INTEGER NOT NULL DEFAULT 0
);

-- Одноразовые челленджи. Живут минуты: устройство берёт и сразу подписывает.
CREATE TABLE IF NOT EXISTS challenges (
  nonce      TEXT PRIMARY KEY,
  created_at REAL NOT NULL
);

-- Счётчик запросов по устройству и по корзине времени («2026-08-19T14», «2026-08-19»).
CREATE TABLE IF NOT EXISTS usage (
  key_id TEXT NOT NULL,
  bucket TEXT NOT NULL,
  count  INTEGER NOT NULL,
  PRIMARY KEY (key_id, bucket)
);

-- Кеш ответов. Отрывков, о которых спрашивают, немного, а вопросы к ним
-- однотипные: «Ин 3:16 / простыми словами» стоит спросить у модели один раз.
CREATE TABLE IF NOT EXISTS cache (
  key        TEXT PRIMARY KEY,
  answer     TEXT NOT NULL,
  created_at REAL NOT NULL,
  hits       INTEGER NOT NULL DEFAULT 0
);

-- Расходы по дням: чем платим за то, что происходит.
CREATE TABLE IF NOT EXISTS spend (
  day               TEXT PRIMARY KEY,
  requests          INTEGER NOT NULL DEFAULT 0,
  prompt_tokens     INTEGER NOT NULL DEFAULT 0,
  completion_tokens INTEGER NOT NULL DEFAULT 0
);
"""


class Store:
    def __init__(self, path: str) -> None:
        os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
        # sqlite3 из нескольких потоков FastAPI — отсюда check_same_thread и замок.
        self._db = sqlite3.connect(path, check_same_thread=False)
        self._db.execute('PRAGMA journal_mode=WAL')
        self._db.executescript(SCHEMA)
        self._db.commit()
        self._lock = threading.Lock()

    # --- челленджи ---------------------------------------------------------

    def put_challenge(self, nonce: str, ttl: float = 300.0) -> None:
        now = time.time()
        with self._lock:
            self._db.execute('DELETE FROM challenges WHERE created_at < ?',
                             (now - ttl,))
            self._db.execute('INSERT OR REPLACE INTO challenges VALUES (?, ?)',
                             (nonce, now))
            self._db.commit()

    def take_challenge(self, nonce: str, ttl: float = 300.0) -> bool:
        """Забирает челлендж навсегда: второй раз тот же не примут."""
        now = time.time()
        with self._lock:
            row = self._db.execute(
                'SELECT created_at FROM challenges WHERE nonce = ?',
                (nonce,)).fetchone()
            self._db.execute('DELETE FROM challenges WHERE nonce = ?', (nonce,))
            self._db.commit()
        return bool(row) and now - row[0] <= ttl

    # --- устройства --------------------------------------------------------

    def add_device(self, key_id: str, public_key: bytes, counter: int) -> None:
        now = time.time()
        with self._lock:
            self._db.execute(
                'INSERT OR REPLACE INTO devices '
                '(key_id, public_key, counter, created_at, last_seen, blocked) '
                'VALUES (?, ?, ?, ?, ?, '
                ' COALESCE((SELECT blocked FROM devices WHERE key_id = ?), 0))',
                (key_id, public_key, counter, now, now, key_id))
            self._db.commit()

    def device(self, key_id: str) -> tuple[bytes, int, bool] | None:
        row = self._db.execute(
            'SELECT public_key, counter, blocked FROM devices WHERE key_id = ?',
            (key_id,)).fetchone()
        return (row[0], row[1], bool(row[2])) if row else None

    def bump_counter(self, key_id: str, counter: int) -> None:
        with self._lock:
            self._db.execute(
                'UPDATE devices SET counter = ?, last_seen = ? WHERE key_id = ?',
                (counter, time.time(), key_id))
            self._db.commit()

    # --- квоты -------------------------------------------------------------

    def over_quota(self, key_id: str, per_hour: int, per_day: int) -> str | None:
        """Возвращает причину отказа или None. Считает и записывает разом."""
        t = time.gmtime()
        hour = time.strftime('%Y-%m-%dT%H', t)
        day = time.strftime('%Y-%m-%d', t)
        with self._lock:
            rows = dict(self._db.execute(
                'SELECT bucket, count FROM usage WHERE key_id = ? '
                'AND bucket IN (?, ?)', (key_id, hour, day)).fetchall())
            if rows.get(hour, 0) >= per_hour:
                return 'час'
            if rows.get(day, 0) >= per_day:
                return 'сутки'
            for bucket in (hour, day):
                self._db.execute(
                    'INSERT INTO usage VALUES (?, ?, 1) '
                    'ON CONFLICT(key_id, bucket) DO UPDATE SET count = count + 1',
                    (key_id, bucket))
            # Старые корзины не нужны: они только растят файл.
            self._db.execute(
                "DELETE FROM usage WHERE length(bucket) = 10 AND bucket < ?",
                (time.strftime('%Y-%m-%d', time.gmtime(time.time() - 86400 * 30)),))
            self._db.execute(
                "DELETE FROM usage WHERE length(bucket) = 13 AND bucket < ?",
                (time.strftime('%Y-%m-%dT%H', time.gmtime(time.time() - 86400 * 2)),))
            self._db.commit()
        return None

    # --- кеш ---------------------------------------------------------------

    @staticmethod
    def cache_key(payload: dict) -> str:
        raw = json.dumps(payload, ensure_ascii=False, sort_keys=True)
        return hashlib.sha256(raw.encode('utf-8')).hexdigest()

    def cached(self, key: str, ttl: float) -> dict | None:
        row = self._db.execute(
            'SELECT answer, created_at FROM cache WHERE key = ?', (key,)).fetchone()
        if not row or time.time() - row[1] > ttl:
            return None
        with self._lock:
            self._db.execute(
                'UPDATE cache SET hits = hits + 1 WHERE key = ?', (key,))
            self._db.commit()
        return json.loads(row[0])

    def put_cache(self, key: str, answer: dict) -> None:
        with self._lock:
            self._db.execute(
                'INSERT OR REPLACE INTO cache (key, answer, created_at, hits) '
                'VALUES (?, ?, ?, COALESCE((SELECT hits FROM cache WHERE key = ?), 0))',
                (key, json.dumps(answer, ensure_ascii=False), time.time(), key))
            self._db.commit()

    # --- расходы -----------------------------------------------------------

    def spent_today(self) -> tuple[int, int]:
        day = time.strftime('%Y-%m-%d', time.gmtime())
        row = self._db.execute(
            'SELECT requests, prompt_tokens + completion_tokens FROM spend '
            'WHERE day = ?', (day,)).fetchone()
        return (row[0], row[1]) if row else (0, 0)

    def add_spend(self, prompt_tokens: int, completion_tokens: int) -> None:
        day = time.strftime('%Y-%m-%d', time.gmtime())
        with self._lock:
            self._db.execute(
                'INSERT INTO spend (day, requests, prompt_tokens, completion_tokens) '
                'VALUES (?, 1, ?, ?) ON CONFLICT(day) DO UPDATE SET '
                'requests = requests + 1, '
                'prompt_tokens = prompt_tokens + excluded.prompt_tokens, '
                'completion_tokens = completion_tokens + excluded.completion_tokens',
                (day, prompt_tokens, completion_tokens))
            self._db.commit()

    def stats(self) -> dict[str, object]:
        one = lambda q: self._db.execute(q).fetchone()[0]  # noqa: E731
        req, tok = self.spent_today()
        return {
            'devices': one('SELECT COUNT(*) FROM devices'),
            'cached': one('SELECT COUNT(*) FROM cache'),
            'cacheHits': one('SELECT COALESCE(SUM(hits), 0) FROM cache'),
            'requestsToday': req,
            'tokensToday': tok,
        }
