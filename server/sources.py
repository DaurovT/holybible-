"""Сбор источников для разбора отрывка.

Модель не должна опираться на память: всё, о чём она говорит, приходит из
bible.db — русские статьи энциклопедии Никифора, карточки сущностей и тексты
параллельных мест. Здесь эти куски достаются и режутся по длине, чтобы запрос
не разрастался.
"""

import re
import sqlite3
from dataclasses import dataclass

# Сокращения книг ровно те же, что в приложении: приложение присылает
# параллельные места подписями вида «Ин 3:16», и разобрать их можно только
# этой таблицей (lib/core/text/bible_reference.dart).
RUSSIAN_ABBREV = {
    'GEN': 'Быт', 'EXO': 'Исх', 'LEV': 'Лев', 'NUM': 'Числ', 'DEU': 'Втор',
    'JOS': 'Нав', 'JDG': 'Суд', 'RUT': 'Руф', '1SA': '1Цар', '2SA': '2Цар',
    '1KI': '3Цар', '2KI': '4Цар', '1CH': '1Пар', '2CH': '2Пар', 'EZR': 'Езд',
    'NEH': 'Неем', 'EST': 'Есф', 'JOB': 'Иов', 'PSA': 'Пс', 'PRO': 'Притч',
    'ECC': 'Еккл', 'SNG': 'Песн', 'ISA': 'Ис', 'JER': 'Иер', 'LAM': 'Плач',
    'EZK': 'Иез', 'DAN': 'Дан', 'HOS': 'Ос', 'JOL': 'Иоил', 'AMO': 'Ам',
    'OBA': 'Авд', 'JON': 'Иона', 'MIC': 'Мих', 'NAM': 'Наум', 'HAB': 'Авв',
    'ZEP': 'Соф', 'HAG': 'Агг', 'ZEC': 'Зах', 'MAL': 'Мал',
    'MAT': 'Мф', 'MRK': 'Мк', 'LUK': 'Лк', 'JHN': 'Ин', 'ACT': 'Деян',
    'ROM': 'Рим', '1CO': '1Кор', '2CO': '2Кор', 'GAL': 'Гал', 'EPH': 'Еф',
    'PHP': 'Флп', 'COL': 'Кол', '1TH': '1Фес', '2TH': '2Фес', '1TI': '1Тим',
    '2TI': '2Тим', 'TIT': 'Тит', 'PHM': 'Флм', 'HEB': 'Евр', 'JAS': 'Иак',
    '1PE': '1Пет', '2PE': '2Пет', '1JN': '1Ин', '2JN': '2Ин', '3JN': '3Ин',
    'JUD': 'Иуд', 'REV': 'Откр',
}

# Сколько всего кладём в запрос. Верхняя граница нужна не ради контекстного
# окна, а ради счёта: статьи Никифора бывают на десятки тысяч знаков.
MAX_ENTITIES = 8
MAX_ARTICLE_CHARS = 2500
MAX_CROSS_REFS = 12
TOTAL_BUDGET_CHARS = 24000

KIND_RU = {'person': 'человек', 'place': 'место', 'other': 'понятие'}

NIKIFOR = 'Библейская энциклопедия архимандрита Никифора, 1891'
SYNODAL = 'Синодальный перевод'
TIPNR = 'TIPNR, Tyndale House (CC BY 4.0)'


@dataclass
class Source:
    """Кусок контекста с меткой, по которой на него потом сошлётся ответ."""
    sid: str
    label: str
    origin: str
    text: str


def _normalize(s: str) -> str:
    s = s.lower().replace('ё', 'е')
    return ''.join(ch for ch in s if ch.isalnum())


class SourceIndex:
    def __init__(self, db_path: str):
        # Соединение только на чтение и общее на все запросы: sqlite тут
        # выступает справочником, писать в него никто не собирается.
        self._db = sqlite3.connect(
            f'file:{db_path}?mode=ro', uri=True, check_same_thread=False)
        self._db.row_factory = sqlite3.Row
        self._books = self._load_books()

    def _load_books(self) -> dict[str, str]:
        """Все написания книги → её код. И «Ин», и «Иоанна», и «JHN»."""
        out: dict[str, str] = {}
        for code, ab in RUSSIAN_ABBREV.items():
            out[_normalize(ab)] = code
        rows = self._db.execute(
            'select book_id, name, short, abbrev from book_names').fetchall()
        for r in rows:
            for form in (r['name'], r['short'], r['abbrev']):
                out.setdefault(_normalize(form), r['book_id'])
        for (bid,) in self._db.execute('select id from books'):
            out.setdefault(_normalize(bid), bid)
        return out

    def entities(self, ids: list[str]) -> list[Source]:
        """Карточки сущностей и привязанные к ним русские статьи."""
        if not ids:
            return []
        ids = ids[:MAX_ENTITIES]
        marks = ','.join('?' * len(ids))
        rows = self._db.execute(
            f'''select id, kind, name_ru, name_en, article, short, brief,
                       descr, modern, geo_area, tribe
                  from entities where id in ({marks})
                 order by ref_count desc''', ids).fetchall()

        out: list[Source] = []
        for r in rows:
            name = r['name_ru'] or r['name_en'] or r['id']
            head = f"{name} — {KIND_RU.get(r['kind'], r['kind'])}"
            extra = [v for v in (r['tribe'], r['geo_area'], r['modern']) if v]
            if extra:
                head += ' (' + ', '.join(extra) + ')'

            # Русская статья лучше английской справки, поэтому сначала ищем её.
            art = self._db.execute(
                'select title, text from articles_ru where entity_id = ?'
                ' order by length(text) desc limit 1', (r['id'],)).fetchone()
            if art:
                body = art['text'][:MAX_ARTICLE_CHARS]
                origin = NIKIFOR
            else:
                body = (r['article'] or r['short'] or r['brief']
                        or r['descr'] or '')[:MAX_ARTICLE_CHARS]
                origin = TIPNR
            if not body.strip():
                continue
            out.append(Source(
                sid=f'e{len(out) + 1}',
                label=name,
                origin=origin,
                text=f'{head}. {body}',
            ))
        return out

    def cross_refs(self, labels: list[str]) -> list[Source]:
        """Тексты параллельных мест по подписям вида «Ин 3:16» и «Ин 3:16–18»."""
        out: list[Source] = []
        seen: set[str] = set()
        for label in labels:
            if len(out) >= MAX_CROSS_REFS:
                break
            parsed = self._parse_ref(label)
            if parsed is None:
                continue
            book_id, chapter, verse, verse_end = parsed
            rows = self._db.execute(
                '''select verse, text from verses
                    where translation_id = 'syn' and book_id = ?
                      and chapter = ? and verse between ? and ?
                    order by verse''',
                (book_id, chapter, verse, verse_end)).fetchall()
            if not rows:
                continue
            key = f'{book_id}:{chapter}:{verse}-{verse_end}'
            if key in seen:
                continue
            seen.add(key)
            body = ' '.join(f'{r["verse"]} {r["text"]}' for r in rows)
            out.append(Source(
                sid=f'x{len(out) + 1}',
                label=label.strip(),
                origin=SYNODAL,
                text=body,
            ))
        return out

    def _parse_ref(self, label: str) -> tuple[str, int, int, int] | None:
        # «1 Кор 13:4–7»: цифра впереди — часть названия, цифры после букв —
        # уже глава и стих. Тире бывает и обычным, и длинным.
        m = re.match(
            r'^\s*([1-4]\s*)?([^\d]+?)\s*(\d+)\s*[:.]\s*(\d+)'
            r'(?:\s*[–—-]\s*(\d+))?\s*$', label)
        if not m:
            return None
        book_id = self._books.get(_normalize((m.group(1) or '') + m.group(2)))
        if book_id is None:
            return None
        chapter, verse = int(m.group(3)), int(m.group(4))
        verse_end = int(m.group(5)) if m.group(5) else verse
        if verse_end < verse:
            verse_end = verse
        return book_id, chapter, verse, verse_end

    def collect(self, entity_ids: list[str],
                cross_refs: list[str]) -> list[Source]:
        """Всё вместе, обрезанное по общему бюджету длины."""
        items = self.entities(entity_ids) + self.cross_refs(cross_refs)
        out: list[Source] = []
        used = 0
        for s in items:
            if used + len(s.text) > TOTAL_BUDGET_CHARS:
                continue
            used += len(s.text)
            out.append(s)
        return out
