#!/usr/bin/env bash
# Compila los dos APK de una versión (64 y 32 bits), ofuscados y con la
# información de depuración aparte (docs/08-version-2.md §8.1).
# Uso: ./build_release.sh
# La app no lleva ninguna dirección de servidor: la escribe el usuario al
# abrirla por primera vez (docs/05-app.md §5.2).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
OUT="build/release/$VERSION"
mkdir -p "$OUT"

for platform in android-arm64 android-arm; do
  flutter build apk --release \
    --target-platform "$platform" \
    --obfuscate --split-debug-info="build/symbols/$VERSION"
  bits=$([ "$platform" = android-arm64 ] && echo 64 || echo 32)
  cp build/app/outputs/flutter-apk/app-release.apk "$OUT/MiTransporte-${VERSION%%+*}-${bits}bits.apk"
done

ls -la "$OUT"
