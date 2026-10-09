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

# Разбор с ИИ по умолчанию выключен: кнопок нет, пока не задан адрес сервера.
# Включить — AI_ENDPOINT=… (и PLAY_CLOUD_PROJECT=… для проверки устройства).
DEFINES=()
if [[ -n "${AI_ENDPOINT:-}" ]]; then
  DEFINES+=(--dart-define=AI_ENDPOINT="$AI_ENDPOINT")
  DEFINES+=(--dart-define=PLAY_CLOUD_PROJECT="${PLAY_CLOUD_PROJECT:-}")
  if [[ -z "${PLAY_CLOUD_PROJECT:-}" ]]; then
    echo "PLAY_CLOUD_PROJECT не задан — разбор с ИИ на Android будет скрыт." >&2
  fi
else
  echo "AI_ENDPOINT не задан — сборка без разбора с ИИ." >&2
fi
BT="$(ls -d "$HOME"/Library/Android/sdk/build-tools/* | sort -V | tail -1)"

rm -f android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
flutter build appbundle --release "${DEFINES[@]}"

rm -f android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
flutter build apk --release "${DEFINES[@]}"

APK=build/app/outputs/flutter-apk/app-release.apk
AAB=build/app/outputs/bundle/release/app-release.aab

echo
echo "── проверка ──"
"$BT/aapt2" dump badging "$APK" | grep -E "^package|targetSdkVersion|application-label:|android.permission"
"$BT/apksigner" verify --print-certs "$APK" | grep -m1 "certificate DN"
"$BT/zipalign" -c -P 16 -v 4 "$APK" | tail -1
ls -lh "$AAB" "$APK" | awk '{print $5, $9}'
