# Sprint 1

| | |
|---|---|
| **Fechas** | Lunes 2 – viernes 6 de noviembre de 2026 |
| **Objetivo del sprint** | Tener la API base funcionando sobre MariaDB y que un trabajador pueda **registrarse** con su carné |
| **Capacidad** | 15 puntos |
| **Product Owner** | Jefe de Transporte de la Unidad de Servicios |
| **Scrum Master** | Jefe del Centro de Desarrollo |
| **Equipo de desarrollo** | Maicol Almarales Tamayo |

## Sprint Backlog

| Historia | Puntos | Tarea | Estado |
|---|:-:|---|:-:|
| **HU-001** Proyecto de la API | 5 | Confirmar la versión de PHP del servidor (`php -v`) | **Pendiente**: requiere acceso al servidor |
| | | Crear el proyecto Lumen 7 y activar Eloquent y facades | Hecho (dependencias resueltas para PHP 7.2.5) |
| | | Configurar MariaDB (`localhost`, usuario con permisos mínimos) | Hecho en `.env.example`; el usuario se crea al instalar en el servidor |
| | | Middleware `RequireJsonApi` (Content-Type y Accept; 415 si no corresponde) | Hecho |
| | | Manejador de excepciones con formato `errors[]` y `code` | Hecho |
| | | Serializador JSON:API base: recurso, colección, `include`, paginación, `sort`, `filter` | Hecho |
| | | PHPUnit configurado, con base de datos de pruebas | Hecho (`docker/test-api.sh`: PHP 7.2 + MariaDB 10.6) |
| **HU-002** Migraciones de nomencladores y ajustes | 3 | Migraciones: `ranks`, `vehicle_types`, `absence_types`, `conversation_topics` | Hecho |
| | | Migraciones: `setting_definitions`, `setting_options`, `settings`, `user_settings` | Hecho |
| | | Seeders: las 18 jerarquías, tipos de vehículo, tipos de ausencia, motivos y ajustes | Hecho |
| **HU-004** Documentación OpenAPI | 2 | Servir `docs/openapi.yaml` con Swagger UI en desarrollo | Hecho |
| | | Validar la especificación en cada *pull request* | Hecho (GitHub Actions, `.github/workflows/api.yml`) |
| **HU-010** Registro | 5 | Migración `workers` (carné cifrado, huella única, sexo, jerarquía, itinerario y parada nulos) | Hecho |
| | | Validador de carné: 11 dígitos, fecha `AAMMDD`, siglo según el 7.º dígito | Hecho |
| | | Cálculo del sexo (penúltimo dígito) | Hecho |
| | | Cifrado del carné y huella HMAC-SHA256 | Hecho |
| | | `POST /workers` con `WorkerController`, `Worker` y su serializador | Hecho |
| | | Pruebas: carné válido o inválido, duplicado, siglo, sexo, contraseña | Hecho |
| | | `GET /ranks` público, porque la pantalla de registro necesita las jerarquías antes de iniciar sesión | Hecho (añadida durante el sprint) |

## Riesgos e impedimentos

| Riesgo | Acción |
|---|---|
| La versión de PHP del servidor es inferior a 7.2.5, y Lumen 7 no funcionaría | Es la primera tarea del sprint. Si ocurre, el Scrum Master gestiona la actualización del servidor |
| No hay entorno de pruebas con MariaDB | El Scrum Master lo solicita el primer día |

## Resultados

*(Se completa en la Sprint Review y en la Retrospective. Datos del equipo de desarrollo para la Review:)*

- **Pruebas automáticas:** 55 pruebas y 207 aserciones, todas en verde, ejecutadas con PHP 7.2 y MariaDB 10.6.
- **Demostración:** `POST /api/v1/workers` (registro; el primero es Administrador), `GET /api/v1/ranks` (paginación, orden y filtro) y Swagger UI en `/docs`.
- **Pendiente:** confirmar la versión de PHP del servidor de producción.

| | |
|---|---|
| Puntos completados | |
| Historias aceptadas por el Product Owner | |
| Qué salió bien | |
| Qué mejorar | |
| Acciones para el sprint 2 | |
