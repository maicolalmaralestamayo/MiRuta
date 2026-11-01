# Servidor de mapas propio

La app **no lleva mapas** ni usa los servidores públicos de OpenStreetMap: pide las
imágenes del mapa a **su propio servidor** (docs/09-repaso-pantallas.md, Mapas).
Así la app no crece, se gastan menos datos y el mapa solo muestra lo necesario:
**calles con sus nombres, edificios y PDI**.

| Pieza | Qué hace |
|---|---|
| `prepare.sh` | Descarga el extracto de Cuba de OpenStreetMap y genera `data/cuba.mbtiles` (teselas vectoriales) con [Planetiler](https://github.com/onthegomap/planetiler) |
| `docker-compose.yml` + `config.json` | Arranca [TileServer GL](https://github.com/maptiler/tileserver-gl), que dibuja las imágenes PNG con el estilo de `style/style.json` |
| `style/style.json` | Estilo sencillo: fondo, agua, calles, nombres de calles, edificios, PDI y nombres de lugares |
| `nginx-tiles.conf` | Publica las imágenes en `/tiles/{z}/{x}/{y}.png` del mismo servidor de la API y las guarda en caché |

## Puesta en marcha

```bash
tools/maps/prepare.sh                                   # una vez (y de vez en cuando, para actualizar)
docker compose -f tools/maps/docker-compose.yml up -d   # servicio de imágenes en 127.0.0.1:8081
```

Después se añade `nginx-tiles.conf` al sitio de la API y se recarga nginx. La app pide
`GET /api/v1/map` y obtiene la plantilla `/tiles/{z}/{x}/{y}.png` (ajuste de la app
`map_tiles_url`), los límites de Cuba y la zona de la Entidad para descargarla.

## En la app

- La vista **no sale de Cuba**.
- Las zonas que se ven **se guardan en el teléfono**: no se vuelven a descargar y se ven sin Internet.
- En **Ajustes → Mapa sin conexión** se descarga de una vez **la zona de la Entidad** (sus paradas con
  unos 2 km de margen), respetando el ajuste «solo con Wi-Fi».

## Requisitos

- Docker. Unos 2 GB de RAM libres mientras se ejecuta `prepare.sh`.
- `prepare.sh` necesita Internet para descargar el extracto de OpenStreetMap y los datos de agua y
  costas que usa Planetiler (`--download`).
