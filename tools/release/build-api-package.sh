#!/usr/bin/env bash
# Prepara el paquete de la API para un servidor de producción:
# código + vendor sin dependencias de desarrollo + base de datos inicial (SQL)
# + guía de instalación. Requiere Docker.
#
# Uso: tools/release/build-api-package.sh 2.1.0
set -euo pipefail
VERSION="${1:?Indique la versión, p. ej. 2.1.0}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/entregas/servidor"
WORK="$(mktemp -d)"
PKG="$WORK/miruta-api"
trap 'docker rm -f miruta-pkg-db >/dev/null 2>&1 || true; docker network rm miruta-pkg >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

echo "Copiando la API…"
mkdir -p "$PKG"
tar -C "$ROOT/api" --exclude=./tests --exclude=./.env --exclude=./.phpunit.result.cache --exclude=./phpunit.xml \
    --exclude='./storage/logs/*.log' --exclude='./public/uploads/*' --exclude=./vendor -cf - . | tar -C "$PKG" -xf -
mkdir -p "$PKG/public/uploads" && touch "$PKG/public/uploads/.gitkeep"
cp "$ROOT/docs/openapi.yaml" "$PKG/openapi.yaml"
cp "$ROOT/tools/release/env.production.example" "$PKG/.env.example"
cp "$ROOT/tools/release/INSTALAR.md" "$PKG/INSTALAR.md"
mkdir -p "$PKG/servidor"
cp "$ROOT/tools/release/nginx-miruta.conf" "$PKG/servidor/"
cp -r "$ROOT/tools/maps" "$PKG/servidor/mapas" && rm -rf "$PKG/servidor/mapas/data"

echo "Instalando dependencias (sin las de desarrollo)…"
docker run --rm -v "$PKG:/app" -w /app composer:2.2 \
    composer install --no-dev --optimize-autoloader --no-interaction --ignore-platform-reqs
find "$PKG/vendor" -name .git -prune -exec rm -rf {} +

echo "Generando la base de datos inicial…"
docker network create miruta-pkg >/dev/null
docker run -d --name miruta-pkg-db --network miruta-pkg -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=miruta mariadb:10.6 >/dev/null
until docker exec miruta-pkg-db mariadb -uroot -proot -e 'select 1' miruta >/dev/null 2>&1; do sleep 2; done
docker run --rm --network miruta-pkg -v "$PKG:/app" -w /app \
    -e DB_CONNECTION=mysql -e DB_HOST=miruta-pkg-db -e DB_DATABASE=miruta -e DB_USERNAME=root -e DB_PASSWORD=root \
    -e APP_KEY=base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= php:7.2-cli \
    sh -c 'docker-php-ext-install pdo_mysql >/dev/null && php artisan migrate --seed --force'
docker exec miruta-pkg-db mariadb-dump -uroot -proot --single-transaction --skip-comments --no-tablespaces miruta \
    > "$PKG/database/miruta-$VERSION-inicial.sql"

mkdir -p "$OUT"
(cd "$WORK" && zip -qr9 "$OUT/miruta-api-$VERSION.zip" miruta-api)
ls -la "$OUT/miruta-api-$VERSION.zip"
