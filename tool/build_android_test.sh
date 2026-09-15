#!/usr/bin/env bash
# Тестовая сборка Android до публикации: разбор с ИИ через тестовый ключ.
#
#     tool/build_android_test.sh
#
# Собирает APK и ставит его на подключённый телефон или эмулятор.
#
# Play Integrity выдаёт вердикт только приложению, которое знает Google Play, а
# до загрузки в Play Console его там нет. Пока так, разбор пускает запасной путь
# сервера — общий секрет APP_TOKEN (на сервере должно быть ALLOW_APP_TOKEN=1).
# Секрет один на все копии и достаётся из APK за минуты, поэтому такая сборка —
# только для своих устройств. В Google Play уходит tool/build_android_release.sh,
# ключа там нет.
#
# Ключ берётся из переменной AI_TOKEN или из файла ~/.holybible-app-token — это
# значение APP_TOKEN из ~/.holybible.env на сервере. В репозиторий не кладётся.
set -euo pipefail
cd "$(dirname "$0")/.."

TOKEN="${AI_TOKEN:-}"
if [[ -z "$TOKEN" && -f "$HOME/.holybible-app-token" ]]; then
  TOKEN="$(tr -d '[:space:]' < "$HOME/.holybible-app-token")"
fi
if [[ -z "$TOKEN" ]]; then
  echo "Нет тестового ключа. Положите значение APP_TOKEN с сервера в ~/.holybible-app-token:" >&2
  echo "  ssh HOLYBIBLE 'grep ^APP_TOKEN= ~/.holybible.env | cut -d= -f2-' > ~/.holybible-app-token" >&2
  echo "  chmod 600 ~/.holybible-app-token" >&2
  exit 1
fi

ENDPOINT="${AI_ENDPOINT:-https://holybible-api.eastus.cloudapp.azure.com}"

# Список плагинов сбрасываем по той же причине, что и в релизной сборке.
rm -f android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
flutter build apk --release \
  --dart-define=AI_ENDPOINT="$ENDPOINT" \
  --dart-define=AI_TOKEN="$TOKEN"

# Отдельное имя — чтобы сборку с ключом не спутать с той, что идёт в Google Play.
OUT=build/app/outputs/flutter-apk/holybible-test-with-token.apk
mv build/app/outputs/flutter-apk/app-release.apk "$OUT"
rm -f build/app/outputs/flutter-apk/app-release.apk.sha1

ADB="$HOME/Library/Android/sdk/platform-tools/adb"
if [[ "$("$ADB" get-state 2>/dev/null)" == "device" ]]; then
  # Приложение, подписанное другим ключом, поверх не встанет — тогда удалите его.
  "$ADB" install -r "$OUT"
  echo "Установлено. Разбор: выделить стих → «Объяснить»."
else
  echo "Устройство не подключено. APK: $OUT"
fi
