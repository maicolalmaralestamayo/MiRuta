#!/usr/bin/env bash
# Compila los dos APK de una versión (64 y 32 bits), ofuscados y con la
# información de depuración aparte (docs/08-version-2.md §8.1).
# Uso: ./tools_build.sh https://mi-servidor/api/v1
set -euo pipefail
cd "$(dirname "$0")"

API_URL="${1:?Indica la dirección de la API, p. ej. https://mi-servidor/api/v1}"
VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
OUT="build/release/$VERSION"
mkdir -p "$OUT"

for platform in android-arm64 android-arm; do
  flutter build apk --release \
    --target-platform "$platform" \
    --obfuscate --split-debug-info="build/symbols/$VERSION" \
    --dart-define=API_URL="$API_URL"
  bits=$([ "$platform" = android-arm64 ] && echo 64 || echo 32)
  cp build/app/outputs/flutter-apk/app-release.apk "$OUT/MiTransporte-${VERSION%%+*}-${bits}bits.apk"
done

ls -la "$OUT"
