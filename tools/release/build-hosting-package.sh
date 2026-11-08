#!/usr/bin/env bash
# Prepara MiRuta para un hospedaje compartido (solo FTP, sin SSH, sin cron y quizá
# sin Composer): Apache + PHP 8.2 + MariaDB 10.3.
#
#   htdocs/miruta/            parte pública (index.php, .htaccess, uploads/)
#   htdocs/miruta/servidor/   código CON vendor/ ya instalado (--no-dev, autoload optimizado)
#                             y configuracion.php (protegido por su .htaccess)
#   subida-rapida/            lo mismo en un .zip + desempaquetar.php (2 archivos por FTP)
#   base-de-datos/            SQL inicial (opcional, GENERAR_SQL=1), por si se prefiere importarlo a mano
#
# Todo lo que hay que ejecutar en el servidor (instalar o actualizar la base de datos,
# tareas programadas, limpiar la caché…) se hace desde la app, con los endpoints de
# mantenimiento de la API (Mantenimiento del servidor).
#
# Uso (los datos del hospedaje van en variables; si faltan, configuracion.php lleva
# «CAMBIAR» en su lugar y hay que editarlo con FileZilla antes de usarlo):
#   APP_URL=http://www.ejemplo.cu/miruta DB_HOST=... DB_DATABASE=... DB_USERNAME=... \
#   DB_PASSWORD=... TEMP_PATH=/srv/www/www.ejemplo.cu/tmp \
#   tools/release/build-hosting-package.sh 4.0.0
#
# Dependencias (vendor/), según VENDOR_METODO:
#   composer (por omisión)  composer install --no-dev --optimize-autoloader (Composer local o, si no hay, Docker)
#   git                     tools/release/vendor-desde-git.py --no-dev (si no se pueden descargar los .zip de GitHub)
#   VENDOR_DIR=carpeta      copia un vendor/ ya instalado sin dependencias de desarrollo
#
# SQL inicial (opcional): GENERAR_SQL=1 con SQL_DB_HOST, SQL_DB_DATABASE, SQL_DB_USERNAME y
# SQL_DB_PASSWORD de una base de datos DE PRUEBAS (se vacía) y mariadb-dump o mysqldump.
#
# Para ACTUALIZAR un servidor ya instalado: ACTUALIZACION=1 tools/release/build-hosting-package.sh 4.0.1
# (sin datos del hospedaje): el paquete NO lleva configuracion.php, así que no toca las
# claves ni la base de datos configuradas, y desempaquetar.php usa la clave de
# mantenimiento que ya está en el servidor. Después, en la app: Mantenimiento del
# servidor → Actualizar base de datos.
#
# Requiere bash, tar, zip y python3. El resultado queda en entregas/hosting/ (no se sube a git).
set -euo pipefail
VERSION="${1:?Indique la versión, p. ej. 4.0.0}"
UPDATE="${ACTUALIZACION:-0}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOSTING="$ROOT/tools/release/hosting"
OUT="$ROOT/entregas/hosting"
WORK="$(mktemp -d)"
NAME="miruta-servidor-$VERSION"
[ "$UPDATE" = 1 ] && NAME="miruta-actualizacion-$VERSION"
PUB="$WORK/$NAME/htdocs/miruta"
SRV="$PUB/servidor"
trap 'rm -rf "$WORK"' EXIT

echo "Copiando el servidor…"
mkdir -p "$SRV"
tar -C "$ROOT/api" --exclude=./tests --exclude=./.env --exclude=./.env.example --exclude=./.phpunit.result.cache \
    --exclude=./.phpunit.cache --exclude=./phpunit.xml --exclude=./public --exclude=./vendor --exclude=./README.md \
    --exclude=./configuracion.php --exclude='./bootstrap/cache/*.php' \
    --exclude='./storage/logs/*.log' --exclude='./storage/framework/cache/data/*' --exclude='./storage/app/*.json' -cf - . | tar -C "$SRV" -xf -
cp "$HOSTING/servidor-htaccess" "$SRV/.htaccess"
cp "$HOSTING/index.php" "$HOSTING/diagnostico.php" "$HOSTING/router.php" "$PUB/"
cp "$HOSTING/htaccess" "$PUB/.htaccess"
cp "$HOSTING/user.ini" "$PUB/.user.ini"
for folder in apk photos children images; do mkdir -p "$PUB/uploads/$folder" && touch "$PUB/uploads/$folder/.vacio"; done

if [ "$UPDATE" = 1 ]; then
  echo "Actualización: sin configuracion.php (se conserva la del servidor)."
  echo "__DEL_SERVIDOR__" > "$WORK/clave"
else
echo "Configuración con claves nuevas…"
WORK="$WORK" python3 - "$HOSTING/configuracion.example.php" "$SRV/configuracion.php" <<'PY'
import base64, os, secrets, sys
text = open(sys.argv[1]).read()
def env(name):
    return os.environ.get(name) or 'CAMBIAR'
values = {
    'APP_URL': env('APP_URL').rstrip('/'),
    'APP_KEY': 'base64:' + base64.b64encode(secrets.token_bytes(32)).decode(),
    'JWT_SECRET': secrets.token_hex(32),
    'MAINTENANCE_KEY': secrets.token_urlsafe(18).replace('-', 'x').replace('_', 'y'),
    'DB_HOST': env('DB_HOST'), 'DB_DATABASE': env('DB_DATABASE'),
    'DB_USERNAME': env('DB_USERNAME'), 'DB_PASSWORD': env('DB_PASSWORD'),
    'TEMP_PATH': env('TEMP_PATH').replace('//', '/').rstrip('/'),
}
for key, value in values.items():
    text = text.replace('__%s__' % key, value.replace("\\", "\\\\").replace("'", "\\'"))
assert '__' not in text.split('return [', 1)[1], 'Falta algún valor'
open(sys.argv[2], 'w').write(text)
open(os.environ['WORK'] + '/clave', 'w').write(values['MAINTENANCE_KEY'])
missing = [k for k, v in values.items() if v.startswith('CAMBIAR')]
if missing:
    print('  Aviso: faltan ' + ', '.join(missing) + ': edite servidor/configuracion.php antes de usarlo.')
PY
fi

if [ -n "${VENDOR_DIR:-}" ]; then
  echo "Copiando dependencias de $VENDOR_DIR…"
  cp -r "$VENDOR_DIR" "$SRV/vendor"
elif [ "${VENDOR_METODO:-composer}" = git ]; then
  echo "Instalando dependencias con git (sin las de desarrollo)…"
  python3 "$ROOT/tools/release/vendor-desde-git.py" "$SRV" --no-dev
elif command -v composer >/dev/null 2>&1; then
  echo "Instalando dependencias con Composer (sin las de desarrollo)…"
  (cd "$SRV" && COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction --prefer-dist --no-scripts \
      && COMPOSER_ALLOW_SUPERUSER=1 composer dump-autoload --no-dev --optimize --no-interaction)
else
  echo "Instalando dependencias con Composer en Docker (sin las de desarrollo)…"
  docker run --rm -v "$SRV:/app" -w /app composer:2 \
      composer install --no-dev --optimize-autoloader --no-interaction --prefer-dist --ignore-platform-reqs
fi
find "$SRV/vendor" -name .git -prune -exec rm -rf {} +
rm -f "$SRV"/bootstrap/cache/*.php
test -f "$SRV/vendor/autoload.php" || { echo "Falta vendor/autoload.php"; exit 1; }
if [ -d "$SRV/vendor/phpunit" ]; then echo "vendor/ tiene dependencias de desarrollo"; exit 1; fi

if [ "$UPDATE" != 1 ] && [ "${GENERAR_SQL:-0}" = 1 ]; then
  echo "Generando la base de datos inicial (SQL)…"
  : "${SQL_DB_HOST:?}" "${SQL_DB_DATABASE:?}" "${SQL_DB_USERNAME:?}" "${SQL_DB_PASSWORD:?}"
  mv "$SRV/configuracion.php" "$WORK/configuracion.php"
  (cd "$SRV" && DB_CONNECTION=mysql DB_HOST="$SQL_DB_HOST" DB_DATABASE="$SQL_DB_DATABASE" DB_USERNAME="$SQL_DB_USERNAME" \
      DB_PASSWORD="$SQL_DB_PASSWORD" STORAGE_PATH="$WORK/storage" APP_KEY=base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \
      php artisan migrate:fresh --seed --force) || { mv "$WORK/configuracion.php" "$SRV/configuracion.php"; exit 1; }
  mv "$WORK/configuracion.php" "$SRV/configuracion.php"
  rm -f "$SRV"/bootstrap/cache/*.php
  DUMP="$(command -v mariadb-dump || command -v mysqldump)"
  mkdir -p "$WORK/$NAME/base-de-datos"
  "$DUMP" -h "$SQL_DB_HOST" -u "$SQL_DB_USERNAME" -p"$SQL_DB_PASSWORD" --single-transaction --skip-comments --no-tablespaces \
      "$SQL_DB_DATABASE" | sed '1{/enable the sandbox mode/d}' > "$WORK/$NAME/base-de-datos/miruta-$VERSION-inicial.sql"
  # (la línea «sandbox mode» de mariadb-dump 10.11 no la entiende MariaDB 10.3)
fi

echo "Opción rápida: un solo .zip y el desempaquetador…"
mkdir -p "$WORK/$NAME/subida-rapida"
(cd "$PUB" && zip -qr9 "$WORK/$NAME/subida-rapida/miruta-servidor.zip" .)
sed "s/__MAINTENANCE_KEY__/$(cat "$WORK/clave")/" "$HOSTING/desempaquetar.php" > "$WORK/$NAME/subida-rapida/desempaquetar.php"

cp "$ROOT/docs/10-traspaso.md" "$WORK/$NAME/GUIA.md"
mkdir -p "$WORK/$NAME/otros" && cp "$HOSTING/nginx-miruta.conf" "$WORK/$NAME/otros/"
[ "$UPDATE" = 1 ] || printf 'Clave de mantenimiento: %s\n\nGuárdela en un lugar seguro. También está en htdocs/miruta/servidor/configuracion.php.\n' \
    "$(cat "$WORK/clave")" > "$WORK/$NAME/CLAVE-DE-MANTENIMIENTO.txt"
mkdir -p "$OUT"
rm -f "$OUT/$NAME.zip"
(cd "$WORK" && zip -qr9 "$OUT/$NAME.zip" "$NAME")
ls -la "$OUT/$NAME.zip"
