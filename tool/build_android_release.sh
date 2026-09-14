#!/usr/bin/env bash
# Релизная сборка для Google Play: AAB для загрузки и APK для проверки руками.
#
#     tool/build_android_release.sh
#
# Перед сборкой удаляется сгенерированный список плагинов. Flutter 3.44 не
# пересобирает его при каждой сборке, а берёт тот, что остался от прошлой: после
# `flutter test` или съёмки скриншотов там есть integration_test, которого в
# релизе нет, и AAB падает с «package dev.flutter.plugins.integration_test does
# not exist». Обратное тоже бывает — отладочная сборка после релизной остаётся
# без плагина теста.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f android/key.properties ]]; then
  echo "Нет android/key.properties — релиз подпишется отладочным ключом, и Google Play его не примет." >&2
  echo "Как завести ключ — раздел «Google Play» в CLAUDE.md." >&2
  exit 1
fi

ENDPOINT="${AI_ENDPOINT:-https://holybible-api.eastus.cloudapp.azure.com}"
# Номер проекта Google Cloud, привязанного к приложению в Play Console
# (App integrity → Play Integrity API). Без него разбор с ИИ на Android скрыт.
PLAY="${PLAY_CLOUD_PROJECT:-}"
if [[ -z "$PLAY" ]]; then
  echo "PLAY_CLOUD_PROJECT не задан — разбор с ИИ на Android будет скрыт." >&2
fi
BT="$(ls -d "$HOME"/Library/Android/sdk/build-tools/* | sort -V | tail -1)"

rm -f android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
flutter build appbundle --release --dart-define=AI_ENDPOINT="$ENDPOINT" --dart-define=PLAY_CLOUD_PROJECT="$PLAY"

rm -f android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
flutter build apk --release --dart-define=AI_ENDPOINT="$ENDPOINT" --dart-define=PLAY_CLOUD_PROJECT="$PLAY"

APK=build/app/outputs/flutter-apk/app-release.apk
AAB=build/app/outputs/bundle/release/app-release.aab

echo
echo "── проверка ──"
"$BT/aapt2" dump badging "$APK" | grep -E "^package|targetSdkVersion|application-label:|android.permission"
"$BT/apksigner" verify --print-certs "$APK" | grep -m1 "certificate DN"
"$BT/zipalign" -c -P 16 -v 4 "$APK" | tail -1
ls -lh "$AAB" "$APK" | awk '{print $5, $9}'
