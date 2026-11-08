# MiRuta

(Antes MiTransporte.) Gestión del transporte de los trabajadores: Entidades, itinerarios, paradas compartidas, personas y solicitudes, planificación de viajes de ida y de regreso, y su seguimiento en tiempo real con la línea del recorrido (sin mapas), calculado en los teléfonos de los trabajadores.

| Capa | Tecnología |
|---|---|
| App móvil | Flutter (Android) |
| API | Laravel 12 (PHP 8.2), JSON:API, JWT (RFC 7519) |
| Base de datos | MariaDB 10.3 o superior |

| Carpeta | Contenido |
|---|---|
| [`api/`](api/README.md) | API (Laravel 12) |
| [`app/`](app/README.md) | App Android (Flutter) |
| [`docs/`](docs/README.md) | Documentación funcional, técnica y Scrum; especificación OpenAPI |
| `docker/` | PHP 8.2 y MariaDB 10.3 para ejecutar las pruebas de la API (`docker/test-api.sh`) |
| `tools/` | Generador de `docs/openapi.yaml` (`tools/openapi`) y paquete del servidor para el hospedaje (`tools/release`) |

**Para montar todo desde cero (traspaso de tecnología), empiece por [`docs/10-traspaso.md`](docs/10-traspaso.md).**
