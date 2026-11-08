#!/usr/bin/env bash
# Ejecuta las pruebas de la API con PHP 8.2 y MariaDB 10.3 en Docker.
# Uso: docker/test-api.sh [argumentos de phpunit]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NETWORK=miruta-test
DB=miruta-test-db

docker build -q -t miruta-php82 -f "$ROOT/docker/php82.Dockerfile" "$ROOT/docker" >/dev/null
docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK" >/dev/null

if ! docker ps --format '{{.Names}}' | grep -qx "$DB"; then
    docker rm -f "$DB" >/dev/null 2>&1 || true
    docker run -d --name "$DB" --network "$NETWORK" \
        -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=miruta_test \
        -e MARIADB_USER=miruta -e MARIADB_PASSWORD=secret \
        mariadb:10.3 >/dev/null
fi

# Esperar a que termine la inicialización (el usuario de pruebas ya puede conectarse)
until docker exec "$DB" mariadb -umiruta -psecret -e "SELECT 1" miruta_test >/dev/null 2>&1; do sleep 1; done

docker run --rm --network "$NETWORK" -v "$ROOT:/repo" -w /repo/api \
    -e DB_CONNECTION=mysql -e DB_HOST="$DB" -e DB_DATABASE=miruta_test -e DB_USERNAME=miruta -e DB_PASSWORD=secret -e APP_DEBUG="${APP_DEBUG:-false}" miruta-php82 vendor/bin/phpunit "$@"
