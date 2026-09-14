# Бэкенд разбора отрывков

Единственная часть проекта, которой нужен сервер. Приложение шлёт сюда
`POST /explain`; сервер достаёт из `bible.db` статьи и параллельные места,
отдаёт их модели как единственный источник и возвращает ответ со ссылками.

- [main.py](main.py) — эндпоинты, проверка устройства, квоты, кеш, потолок
  расходов, запрос к модели.
- [sources.py](sources.py) — сборка источников из `bible.db`.
- [attest.py](attest.py) — проверка App Attest: подлинное ли приложение спрашивает.
- [store.py](store.py) — состояние сервера: устройства, квоты, кеш, расходы.
- [test_attest.py](test_attest.py) — проверки разбора подписей.
- [deploy/](deploy/) — юниты systemd и конфиг Caddy, копии рабочих.

## Кто может спрашивать

Общий секрет в бандле защищает до первого, кто разберёт .ipa: он один на все
копии, отозвать его можно только сменив у всех сразу. Поэтому подлинность
доказывает **App Attest** — ключ в защищённом элементе устройства, заверенный
Apple. Порядок: приложение берёт одноразовый челлендж (`/attest/challenge`),
один раз за установку присылает заверение ключа (`/attest/register`), дальше
подписывает свежий челлендж (`/attest/assert`) и получает пропуск на сутки.
С пропуском идёт в `/explain`.

`ALLOW_APP_TOKEN=1` открывает запасной путь по заголовку `x-app-token` — он
нужен только в симуляторе, где App Attest недоступен. **Перед публикацией в
App Store поставить 0.**

## Чем ограничены расходы

- **Кеш ответов.** Отрывков, о которых спрашивают, немного, а вопросы к ним
  однотипные. Повтор того же запроса отдаётся из кеша мимо модели, мимо квоты
  и мимо счёта: 3 секунды превращаются в 40 миллисекунд.
- **Квоты по устройству** — `QUOTA_PER_HOUR`, `QUOTA_PER_DAY`. Считаются по
  ключу App Attest, а не по адресу: телефоны за общим оператором делят один
  адрес и мешали бы друг другу.
- **Потолок на сутки** — `DAILY_REQUEST_CAP`, `DAILY_TOKEN_CAP`. Упёрлись —
  сервер честно отвечает, что разбор сегодня недоступен.

Что накопилось, видно в `/health`.

## Что где лежит на машине

Рабочая копия — `~/holybible-server/`: там виртуальное окружение, `bible.db`
(57 МБ, в репозиторий не входит, берётся из `assets/db/`) и `state.db`
(устройства, квоты, кеш). Исходники там — символические ссылки сюда, чтобы
правка в репозитории сразу доходила до сервера и копии не расходились.

Ключи — `~/.holybible.env` с правами 600, в репозитории их нет:

    AZURE_AI_ENDPOINT=  AZURE_AI_KEY=  AZURE_AI_MODEL=
    APPLE_TEAM_ID=  APPLE_BUNDLE_ID=  ATTEST_ENV=  JWT_SECRET=
    APP_TOKEN=  ALLOW_APP_TOKEN=
    PLAY_INTEGRITY_CREDENTIALS=  ANDROID_CERT_SHA256=  PLAY_INTEGRITY_ENV=
    ANDROID_PACKAGE=

`ATTEST_ENV=development` принимает и отладочные сборки, и боевые;
`production` — только боевые. Для App Store ставится `production`.

## Android: Play Integrity

Android-аналог App Attest (`play_integrity.py`, маршрут `/attest/android`).
Приложение присылает вердикт Google Play, сервер отдаёт его на расшифровку в
Play Integrity API от имени сервисного аккаунта Google Cloud и проверяет:
пакет, челлендж, свежесть, признание Google Play, подпись и честность
устройства. Проверки — `.venv/bin/python test_play_integrity.py`.

Один раз настроить:

1. Play Console → приложение `com.holybible.holy_bible` → **App integrity** →
   Play Integrity API → привязать проект Google Cloud (или создать). Номер
   проекта нужен приложению при сборке: `PLAY_CLOUD_PROJECT`.
2. Google Cloud → этот проект → IAM → **сервисный аккаунт** без ролей → ключ
   JSON. Положить на сервер, например `~/.play-integrity.json` с правами 600,
   путь — в `PLAY_INTEGRITY_CREDENTIALS`.
3. Play Console → App integrity → **App signing key certificate** → SHA-256 в
   `ANDROID_CERT_SHA256` как есть, с двоеточиями. Именно ключ Play App Signing:
   Google Play переподписывает сборку им, ключ загрузки в вердикт не попадает.
4. `PLAY_INTEGRITY_ENV=development`, пока проверяете сборку через adb или на
   эмуляторе: пропускает приложение не из Google Play и базовую целостность
   устройства. Для публикации — `production`.

`/health` показывает `playIntegrity: true`, когда ключ прочитан.

## Развернуть с нуля

    python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
    gunzip -c <репозиторий>/assets/db/bible.db.gz > data/bible.db
    for f in main.py sources.py attest.py store.py apple_app_attest_root_ca.pem \
             privacy.html support.html; do ln -sfn <репозиторий>/server/$f $f; done
    sudo cp deploy/holybible-api.service deploy/holybible-watch.* /etc/systemd/system/
    sudo systemctl enable --now holybible-api holybible-watch.timer

В репозитории база лежит только сжатой, несжатой `bible.db` там нет.

## Обновить после git pull

Исходники — ссылки в репозиторий, так что новый код уже на диске, но
работающий процесс его не видит. Порядок:

1. **Новые файлы в `server/`** — завести на них ссылки, как выше. Страница без
   ссылки отдаёт ошибку, а не 404.
2. **Изменилась `assets/db/bible.db.gz`** — распаковать во временный файл,
   проверить и только потом подменить: сервер держит базу открытой, а битая
   база сломает разбор, не запуск.

       gunzip -c <репозиторий>/assets/db/bible.db.gz > data/bible.db.incoming
       mv data/bible.db data/bible.db.old && mv data/bible.db.incoming data/bible.db

   Если в базе поменялись статьи или тексты, очистить кеш ответов — иначе
   старые разборы отдаются ещё `CACHE_TTL_DAYS`:

       python3 -c "import sqlite3; c=sqlite3.connect('data/state.db'); c.execute('delete from cache'); c.commit()"

3. **Изменился `deploy/holybible-api.service`** — скопировать в
   `/etc/systemd/system/` и `sudo systemctl daemon-reload`.
4. `sudo systemctl restart holybible-api` и проверить `/health`.

Наружу смотрит Caddy, не бэкенд: тот слушает `127.0.0.1:8099` и из интернета
недоступен. `deploy/Caddyfile` держит 443 и сам выпускает сертификат
Let's Encrypt — для этого нужен открытый 80-й порт.

`holybible-watch.timer` раз в пять минут проверяет, что сервер именно
отвечает, и перезапускает его, если нет: `Restart=always` поднимает упавший
процесс, но не помогает, когда процесс жив и молчит.

## Проверить

    curl https://holybible-api.eastus.cloudapp.azure.com/health
    .venv/bin/python test_attest.py
