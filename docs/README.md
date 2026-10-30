# Documentación de MiTransporte

| Documento | Contenido |
|---|---|
| [01-vision.md](01-vision.md) | Visión, stack, alcance, roles de la app, roles Scrum y glosario |
| [02-procesos.md](02-procesos.md) | Reglas de negocio: registro, solicitudes, hijos, vehículos, itinerarios, viajes, notificaciones, recorrido, subida, chats, estadísticas y tareas programadas |
| [03-datos.md](03-datos.md) | Modelo de datos: diagrama entidad-relación, diagrama de tablas, restricciones y normalización (3FN) |
| [04-api.md](04-api.md) | API JSON:API: arquitectura, autenticación JWT, recursos, permisos, estadísticas y errores |
| [openapi.yaml](openapi.yaml) | Especificación OpenAPI 3.0.3 para importar en Swagger, Postman o Insomnia |
| [05-app.md](05-app.md) | App Flutter: arquitectura, pantallas por rol y ajustes del usuario |
| [06-ajustes.md](06-ajustes.md) | Todos los ajustes, con sus valores por defecto y sus límites |

## Scrum

| Documento | Contenido |
|---|---|
| [scrum/objetivo-producto.md](scrum/objetivo-producto.md) | Objetivo del producto, equipo Scrum, eventos y artefactos |
| [scrum/product-backlog.md](scrum/product-backlog.md) | Épicas e historias de usuario con criterios de aceptación, prioridad y estimación |
| [scrum/definicion-de-hecho.md](scrum/definicion-de-hecho.md) | Definición de Hecho |
| [scrum/definicion-de-listo.md](scrum/definicion-de-listo.md) | Definición de Listo |
| [scrum/plan-de-entregas.md](scrum/plan-de-entregas.md) | Entregas y previsión de los 19 sprints |
| [scrum/sprint-01.md](scrum/sprint-01.md) | Objetivo y Sprint Backlog del sprint 1 |

## Cómo ver la API en Swagger

- **En línea:** abrir <https://editor.swagger.io> y usar *File → Import file* con `openapi.yaml`.
- **En local:**

  ```bash
  docker run -p 8080:8080 -e SWAGGER_JSON=/spec/openapi.yaml -v "$PWD/docs:/spec" swaggerapi/swagger-ui
  ```

- **Postman:** *Import* → seleccionar `openapi.yaml`. Genera una colección con todas las rutas.
