#!/usr/bin/env bash
# Compila los dos APK de una versión (64 y 32 bits), ofuscados y con la
# información de depuración aparte (docs/08-version-2.md §8.1).
# Uso: ./build_release.sh [dirección del servidor]
# Con SOLO_32=1 compila solo el de 32 bits (lo que se entrega desde la 4.3.0,
# docs/11 §11.64): SOLO_32=1 ./build_release.sh
# Por defecto la app NO trae la dirección del servidor (docs/11 §11.14): el
# usuario la escribe con el botón «Indicar servidor». Solo si se da aquí,
# la app viene con ella puesta. Puede ser https:// o http://.
set -euo pipefail
cd "$(dirname "$0")"

API_URL="${1:-}"
VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
OUT="build/release/$VERSION"
mkdir -p "$OUT"

PLATFORMS="android-arm64 android-arm"
if [ "${SOLO_32:-0}" = "1" ]; then PLATFORMS="android-arm"; fi

for platform in $PLATFORMS; do
  flutter build apk --release \
    --target-platform "$platform" \
    --obfuscate --split-debug-info="build/symbols/$VERSION" \
    --dart-define=API_URL="$API_URL"
  bits=$([ "$platform" = android-arm64 ] && echo 64 || echo 32)
  cp build/app/outputs/flutter-apk/app-release.apk "$OUT/MiRuta-${VERSION%%+*}-${bits}bits.apk"
done

ls -la "$OUT"
