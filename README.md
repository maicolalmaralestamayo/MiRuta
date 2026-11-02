# MiRuta

(Antes MiTransporte.) Gestión del transporte de los trabajadores de la empresa: itinerarios, paradas, vehículos, choferes, planificación de viajes, avisos (también de viajes atrasados, paradas no realizadas y desvíos) y seguimiento de los recorridos en tiempo real con un mapa propio.

| Capa | Tecnología |
|---|---|
| App móvil | Flutter (Android) |
| API | Lumen 7 (PHP ≥ 7.2.5), JSON:API, JWT (RFC 7519) |
| Base de datos | MariaDB |

| Carpeta | Contenido |
|---|---|
| [`api/`](api/README.md) | API (Lumen 7) |
| [`app/`](app/README.md) | App Android (Flutter) |
| [`docs/`](docs/README.md) | Documentación funcional, técnica y Scrum; especificación OpenAPI |
| `docker/` | PHP 7.2 y MariaDB para ejecutar las pruebas de la API (`docker/test-api.sh`) |
| `tools/` | Generador de `docs/openapi.yaml` (`tools/openapi`) y servidor de mapas propio de Cuba (`tools/maps`) |

**Para montar todo desde cero (traspaso de tecnología), empiece por [`docs/10-traspaso.md`](docs/10-traspaso.md).**
