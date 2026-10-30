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
| **HU-001** Proyecto de la API | 5 | Confirmar la versión de PHP del servidor (`php -v`) | Por hacer |
| | | Crear el proyecto Lumen 7 y activar Eloquent y facades | Por hacer |
| | | Configurar MariaDB (`localhost`, usuario con permisos mínimos) | Por hacer |
| | | Middleware `RequireJsonApi` (Content-Type y Accept; 415 si no corresponde) | Por hacer |
| | | Manejador de excepciones con formato `errors[]` y `code` | Por hacer |
| | | Serializador JSON:API base: recurso, colección, `include`, paginación, `sort`, `filter` | Por hacer |
| | | PHPUnit configurado, con base de datos de pruebas | Por hacer |
| **HU-002** Migraciones de nomencladores y ajustes | 3 | Migraciones: `ranks`, `vehicle_types`, `absence_types`, `conversation_topics` | Por hacer |
| | | Migraciones: `setting_definitions`, `setting_options`, `settings`, `user_settings` | Por hacer |
| | | Seeders: las 18 jerarquías, tipos de vehículo, tipos de ausencia, motivos y ajustes | Por hacer |
| **HU-004** Documentación OpenAPI | 2 | Servir `docs/openapi.yaml` con Swagger UI en desarrollo | Por hacer |
| | | Validar la especificación en cada *pull request* | Por hacer |
| **HU-010** Registro | 5 | Migración `workers` (carné cifrado, huella única, sexo, jerarquía, itinerario y parada nulos) | Por hacer |
| | | Validador de carné: 11 dígitos, fecha `AAMMDD`, siglo según el 7.º dígito | Por hacer |
| | | Cálculo del sexo (penúltimo dígito) | Por hacer |
| | | Cifrado del carné y huella HMAC-SHA256 | Por hacer |
| | | `POST /workers` con `WorkersController`, `Worker` y su serializador | Por hacer |
| | | Pruebas: carné válido o inválido, duplicado, siglo, sexo, contraseña | Por hacer |

## Riesgos e impedimentos

| Riesgo | Acción |
|---|---|
| La versión de PHP del servidor es inferior a 7.2.5, y Lumen 7 no funcionaría | Es la primera tarea del sprint. Si ocurre, el Scrum Master gestiona la actualización del servidor |
| No hay entorno de pruebas con MariaDB | El Scrum Master lo solicita el primer día |

## Resultados

*(Se completa en la Sprint Review y en la Retrospective.)*

| | |
|---|---|
| Puntos completados | |
| Historias aceptadas por el Product Owner | |
| Qué salió bien | |
| Qué mejorar | |
| Acciones para el sprint 2 | |
