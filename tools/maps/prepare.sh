#!/usr/bin/env bash
# Prepara los datos del mapa de Cuba para el servidor de mapas propio
# (docs/09-repaso-pantallas.md, Mapas). Descarga el extracto de OpenStreetMap
# y genera data/cuba.mbtiles (teselas vectoriales, esquema OpenMapTiles).
#
# Uso: tools/maps/prepare.sh
# Requiere Docker. Volver a ejecutarlo de vez en cuando actualiza el mapa.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

EXTRACT_URL="${EXTRACT_URL:-https://download.geofabrik.de/central-america/cuba-latest.osm.pbf}"

echo "Descargando el extracto de OpenStreetMap…"
curl -fL --retry 3 -o data/cuba.osm.pbf "$EXTRACT_URL"

echo "Generando data/cuba.mbtiles (puede tardar varios minutos)…"
docker run --rm -e JAVA_TOOL_OPTIONS="-Xmx2g" -v "$PWD/data:/data" \
  ghcr.io/onthegomap/planetiler:0.8.3 \
  --osm-path=/data/cuba.osm.pbf --output=/data/cuba.mbtiles \
  --download --force --maxzoom=14 \
  --bounds=-85.2,19.6,-73.9,23.45

ls -lh data/cuba.mbtiles
echo "Listo. Arranque el servicio con: docker compose -f tools/maps/docker-compose.yml up -d"
