#!/usr/bin/env bash
# Ejecuta las pruebas de la API con PHP 7.2 y MariaDB 10.6 en Docker.
# Uso: docker/test-api.sh [argumentos de phpunit]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NETWORK=mitransporte-test
DB=mitransporte-test-db

docker build -q -t mitransporte-php72 -f "$ROOT/docker/php72.Dockerfile" "$ROOT/docker" >/dev/null
docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK" >/dev/null

if ! docker ps --format '{{.Names}}' | grep -qx "$DB"; then
    docker rm -f "$DB" >/dev/null 2>&1 || true
    docker run -d --name "$DB" --network "$NETWORK" \
        -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=mitransporte_test \
        -e MARIADB_USER=mitransporte -e MARIADB_PASSWORD=secret \
        mariadb:10.6 >/dev/null
fi

until docker exec "$DB" mariadb-admin ping -uroot -proot --silent >/dev/null 2>&1; do sleep 1; done

docker run --rm --network "$NETWORK" -v "$ROOT:/repo" -w /repo/api \
    -e DB_HOST="$DB" mitransporte-php72 vendor/bin/phpunit "$@"
