#!/usr/bin/env bash
# Prepara MiRuta para un hospedaje compartido (solo FTP, sin SSH ni cron):
#   htdocs/miruta/            parte pública (index.php, .htaccess, uploads/)
#   htdocs/miruta/servidor/   código, dependencias y configuracion.php (protegido)
#   subida-rapida/            lo mismo en un .zip + desempaquetar.php (2 archivos por FTP)
#   base-de-datos/            SQL inicial, por si se prefiere importarlo a mano
# La base de datos se instala o actualiza desde la app (Mantenimiento del servidor).
#
# Uso (los datos del hospedaje van en variables):
#   APP_URL=http://www.ejemplo.cu/miruta DB_HOST=... DB_DATABASE=... DB_USERNAME=... \
#   DB_PASSWORD=... TEMP_PATH=/srv/www/www.ejemplo.cu/tmp \
#   tools/release/build-hosting-package.sh 2.2.0
# Opcional: VENDOR_DIR=carpeta con un vendor/ ya instalado sin dependencias de desarrollo.
# Requiere Docker, zip y python3. Las claves secretas se generan nuevas cada vez.
set -euo pipefail
VERSION="${1:?Indique la versión, p. ej. 2.2.0}"
: "${APP_URL:?}" "${DB_HOST:?}" "${DB_DATABASE:?}" "${DB_USERNAME:?}" "${DB_PASSWORD:?}" "${TEMP_PATH:?}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOSTING="$ROOT/tools/release/hosting"
OUT="$ROOT/entregas/hosting"
WORK="$(mktemp -d)"
NAME="miruta-hosting-$VERSION"
PUB="$WORK/$NAME/htdocs/miruta"
SRV="$PUB/servidor"
trap 'docker rm -f miruta-pkg-db >/dev/null 2>&1 || true; docker network rm miruta-pkg >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

echo "Copiando el servidor…"
mkdir -p "$SRV"
tar -C "$ROOT/api" --exclude=./tests --exclude=./.env --exclude=./.env.example --exclude=./.phpunit.result.cache \
    --exclude=./phpunit.xml --exclude=./public --exclude=./vendor --exclude=./README.md \
    --exclude='./storage/logs/*.log' --exclude='./storage/framework/cache/data/*' -cf - . | tar -C "$SRV" -xf -
cp "$HOSTING/servidor-htaccess" "$SRV/.htaccess"
cp "$HOSTING/index.php" "$HOSTING/diagnostico.php" "$PUB/"
cp "$HOSTING/htaccess" "$PUB/.htaccess"
cp "$HOSTING/user.ini" "$PUB/.user.ini"
for folder in apk photos ranks; do mkdir -p "$PUB/uploads/$folder" && touch "$PUB/uploads/$folder/.vacio"; done

echo "Configuración con claves nuevas…"
WORK="$WORK" python3 - "$HOSTING/configuracion.example.php" "$SRV/configuracion.php" <<'PY'
import base64, os, secrets, sys
text = open(sys.argv[1]).read()
values = {
    'APP_URL': os.environ['APP_URL'].rstrip('/'),
    'APP_KEY': 'base64:' + base64.b64encode(secrets.token_bytes(32)).decode(),
    'JWT_SECRET': secrets.token_hex(32),
    'MAINTENANCE_KEY': secrets.token_urlsafe(18).replace('-', 'x').replace('_', 'y'),
    'DB_HOST': os.environ['DB_HOST'], 'DB_DATABASE': os.environ['DB_DATABASE'],
    'DB_USERNAME': os.environ['DB_USERNAME'], 'DB_PASSWORD': os.environ['DB_PASSWORD'],
    'TEMP_PATH': os.environ['TEMP_PATH'].replace('//', '/').rstrip('/'),
}
for key, value in values.items():
    text = text.replace('__%s__' % key, value.replace("\\", "\\\\").replace("'", "\\'"))
assert '__' not in text.split('return [', 1)[1], 'Falta algún valor'
open(sys.argv[2], 'w').write(text)
open(os.environ['WORK'] + '/clave', 'w').write(values['MAINTENANCE_KEY'])
PY

if [ -n "${VENDOR_DIR:-}" ]; then
  echo "Copiando dependencias de $VENDOR_DIR…"
  cp -r "$VENDOR_DIR" "$SRV/vendor"
else
  echo "Instalando dependencias (sin las de desarrollo)…"
  docker run --rm -v "$SRV:/app" -w /app composer:2.2 \
      composer install --no-dev --optimize-autoloader --no-interaction --ignore-platform-reqs
fi
find "$SRV/vendor" -name .git -prune -exec rm -rf {} +

echo "Generando la base de datos inicial (SQL)…"
docker network create miruta-pkg >/dev/null
docker run -d --name miruta-pkg-db --network miruta-pkg -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=miruta mariadb:10.6 >/dev/null
until docker exec miruta-pkg-db mariadb -uroot -proot -e 'select 1' miruta >/dev/null 2>&1; do sleep 2; done
docker run --rm --network miruta-pkg -v "$SRV:/app" -w /app \
    -e DB_CONNECTION=mysql -e DB_HOST=miruta-pkg-db -e DB_DATABASE=miruta -e DB_USERNAME=root -e DB_PASSWORD=root \
    -e STORAGE_PATH=/tmp/miruta -e APP_KEY=base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= mitransporte-php72 \
    sh -c 'mv configuracion.php /tmp/c.php && php artisan migrate --seed --force; s=$?; mv /tmp/c.php configuracion.php; exit $s'
mkdir -p "$WORK/$NAME/base-de-datos"
docker exec miruta-pkg-db mariadb-dump -uroot -proot --single-transaction --skip-comments --no-tablespaces miruta \
    > "$WORK/$NAME/base-de-datos/miruta-$VERSION-inicial.sql"

echo "Opción rápida: un solo .zip y el desempaquetador…"
mkdir -p "$WORK/$NAME/subida-rapida"
(cd "$PUB" && zip -qr9 "$WORK/$NAME/subida-rapida/miruta-servidor.zip" .)
sed "s/__MAINTENANCE_KEY__/$(cat "$WORK/clave")/" "$HOSTING/desempaquetar.php" > "$WORK/$NAME/subida-rapida/desempaquetar.php"

cp "$HOSTING/LEEME.md" "$WORK/$NAME/LEEME.md"
printf 'Clave de mantenimiento: %s\n\nGuárdela en un lugar seguro. También está en htdocs/miruta/servidor/configuracion.php.\n' \
    "$(cat "$WORK/clave")" > "$WORK/$NAME/CLAVE-DE-MANTENIMIENTO.txt"
mkdir -p "$OUT"
rm -f "$OUT/$NAME.zip"
(cd "$WORK" && zip -qr9 "$OUT/$NAME.zip" "$NAME")
ls -la "$OUT/$NAME.zip"
