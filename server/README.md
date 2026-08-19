# Бэкенд разбора отрывков

Единственная часть проекта, которой нужен сервер. Приложение шлёт сюда
`POST /explain`; сервер достаёт из `bible.db` статьи и параллельные места,
отдаёт их модели как единственный источник и возвращает ответ со ссылками.

- [main.py](main.py) — эндпоинты `/explain` и `/health`, проверка токена,
  ограничение частоты, запрос к модели.
- [sources.py](sources.py) — сборка источников из `bible.db`.
- [deploy/](deploy/) — юнит systemd и конфиг Caddy, копии рабочих.

## Что где лежит на машине

Рабочая копия — `~/holybible-server/`: там виртуальное окружение и `bible.db`
(57 МБ, в репозиторий не входит, берётся из `assets/db/`). `main.py` и
`sources.py` там — символические ссылки сюда, чтобы правка в репозитории сразу
доходила до сервера и копии не расходились.

Ключи — `~/.holybible.env` с правами 600, в репозитории их нет:

    AZURE_AI_ENDPOINT=  AZURE_AI_KEY=  AZURE_AI_MODEL=  APP_TOKEN=

`APP_TOKEN` — общий секрет с приложением. Публичный адрес без него — открытый
кран на чужой счёт: запросы шлёт кто угодно, платит владелец сервера.

## Развернуть с нуля

    python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
    cp <репозиторий>/assets/db/bible.db data/bible.db
    sudo cp deploy/holybible-api.service /etc/systemd/system/
    sudo systemctl enable --now holybible-api

Наружу смотрит Caddy, не бэкенд: тот слушает `127.0.0.1:8099` и из интернета
недоступен. `deploy/Caddyfile` держит 443 и сам выпускает сертификат
Let's Encrypt — для этого нужен открытый 80-й порт.

## Проверить

    curl https://holybible-api.eastus.cloudapp.azure.com/health
