#!/usr/bin/env bash
# Compila los dos APK de una versión (64 y 32 bits), ofuscados y con la
# información de depuración aparte (docs/08-version-2.md §8.1).
# Uso: ./build_release.sh [dirección del servidor]
# La dirección es opcional: si se da, la app viene con ella puesta; si no, el
# usuario la escribe con el botón «Servidor» (docs/05-app.md §5.2). Puede ser
# https:// o http://.
set -euo pipefail
cd "$(dirname "$0")"

API_URL="${1:-}"
VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
OUT="build/release/$VERSION"
mkdir -p "$OUT"

for platform in android-arm64 android-arm; do
  flutter build apk --release \
    --target-platform "$platform" \
    --obfuscate --split-debug-info="build/symbols/$VERSION" \
    --dart-define=API_URL="$API_URL"
  bits=$([ "$platform" = android-arm64 ] && echo 64 || echo 32)
  cp build/app/outputs/flutter-apk/app-release.apk "$OUT/MiRuta-${VERSION%%+*}-${bits}bits.apk"
done

ls -la "$OUT"
