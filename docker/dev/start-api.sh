#!/bin/sh
# Arranque de la API en el contenedor: dependencias, base de datos y servidor.
set -e
cd /repo/api
echo "Esperando a la base de datos…"
until php -r 'new PDO("mysql:host=db;dbname=miruta", "miruta", "miruta");' 2>/dev/null; do sleep 2; done
# Crea o actualiza las tablas y los datos de referencia (se pueden aplicar varias veces).
php artisan migrate --force
php artisan db:seed --force
echo "API lista en http://localhost:8000/api/v1 (documentación en http://localhost:8000/docs)"
exec php -S 0.0.0.0:8000 -t public
