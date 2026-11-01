#!/bin/sh
# Arranque de la API: espera a la base de datos, crea o actualiza las tablas y
# los datos de referencia, y sirve la API. Con ROLE=scheduler ejecuta las
# tareas programadas cada minuto.
set -e
cd /app
until php -r 'new PDO("mysql:host=" . getenv("DB_HOST") . ";port=" . getenv("DB_PORT") . ";dbname=" . getenv("DB_DATABASE"), getenv("DB_USERNAME"), getenv("DB_PASSWORD"));' 2>/dev/null; do
  echo "Esperando a la base de datos…"; sleep 2
done
if [ "$ROLE" = "scheduler" ]; then
  while true; do php artisan schedule:run; sleep 60; done
fi
php artisan migrate --force
php artisan db:seed --force
echo "API lista en http://localhost:8000/api/v1 (documentación en http://localhost:8000/docs)"
exec php -S 0.0.0.0:8000 -t public
