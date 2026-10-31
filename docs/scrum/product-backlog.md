# Product Backlog

- **Responsable:** Product Owner (Jefe de Transporte de la Unidad de Servicios).
- **Orden:** por prioridad. La prioridad sigue el método MoSCoW: **M** *Must* (imprescindible), **S** *Should* (importante), **C** *Could* (deseable).
- **Estimación:** puntos de historia en escala Fibonacci (1, 2, 3, 5, 8, 13). Los estima el equipo de desarrollo y se revisan en cada refinamiento.
- **Formato de las historias:** *Como [rol] quiero [acción] para [beneficio]*, con sus criterios de aceptación.
- **Detalle funcional:** está en [`docs/02-procesos.md`](../02-procesos.md). Las historias hacen referencia a él.

## Resumen por épica

| Épica | Nombre | Prioridad | Puntos | Entrega |
|---|---|:-:|:-:|:-:|
| E01 | Base técnica | M | 15 | 1 |
| E02 | Cuentas y acceso | M | 30 | 1 |
| E03 | Nomencladores y ajustes | M | 14 | 1 |
| E04 | Itinerarios y paradas | M | 11 | 1 |
| E05 | Solicitudes y aprobaciones | M | 28 | 1 |
| E06 | Hijos | S | 9 | 1 |
| E07 | Vehículos y choferes | M | 5 | 1 |
| E08 | Planificación de viajes | M | 32 | 1 |
| E09 | Notificaciones y sincronización | M | 21 | 1 |
| E10 | Recorrido en tiempo real | S | 42 | 2 |
| E11 | Subida al transporte | S | 20 | 2 |
| E14 | Baja automática por inactividad | S | 5 | 2 |
| E12 | Chats | C | 14 | 2–3 |
| E13 | Estadísticas | C | 28 | 3 |
| | **Total** | | **272** | |

---

## E01 · Base técnica

### HU-001 · Proyecto de la API · M · 5 pts
*Como equipo de desarrollo quiero el proyecto Lumen 7 con su estructura modelo-controlador para construir la API sobre una base común.*
- El proyecto arranca con PHP 7.2.5 o superior y se conecta a MariaDB por `localhost`.
- Todas las respuestas usan `application/vnd.api+json`. Una petición con otro tipo de contenido devuelve 415.
- Los errores siguen el formato `errors[]` de JSON:API, con `code` (ver [04-api.md §4.7](../04-api.md#47-errores)).
- La capa de serialización JSON:API admite `include`, paginación, `sort` y `filter`.

### HU-002 · Migraciones y datos iniciales de nomencladores y ajustes · M · 3 pts
*Como equipo de desarrollo quiero las migraciones y los seeders de los nomencladores y los ajustes para disponer de los datos de referencia.*
- Migraciones de `ranks`, `vehicle_types`, `absence_types`, `conversation_topics`, `setting_definitions`, `setting_options`, `settings` y `user_settings`, con `created_at`, `updated_at` y `deleted_at`.
- Los seeders cargan los datos de [03-datos.md §3.7](../03-datos.md#37-datos-iniciales-seeders).

### HU-003 · Proyecto de la app · M · 5 pts
*Como equipo de desarrollo quiero el proyecto Flutter con navegación, cliente JSON:API y gestión de errores para construir las pantallas sobre una base común.*
- Compila y se instala en Android.
- El cliente HTTP convierte documentos JSON:API (`data`, `included`, `errors`) en objetos.
- Los errores de la API se muestran al usuario en español.

### HU-004 · Documentación OpenAPI · M · 2 pts
*Como desarrollador quiero la especificación OpenAPI publicada para consultar y probar la API.*
- `docs/openapi.yaml` es válido y se mantiene al día en cada historia que cambie la API.
- Se puede abrir en Swagger UI desde el servidor de desarrollo.

## E02 · Cuentas y acceso

### HU-010 · Registro · M · 5 pts
*Como persona de la empresa quiero registrarme con mi carné, un usuario, nombre, apellidos, jerarquía y contraseña para usar la app.*
- Se valida el carné: 11 dígitos, fecha válida y siglo según el 7.º dígito.
- Un carné repetido devuelve `CARD_NUMBER_TAKEN`.
- El sexo se calcula a partir del penúltimo dígito del carné.
- El usuario es único (sin distinguir mayúsculas). Uno repetido devuelve `USERNAME_TAKEN`. La app propone uno a partir del nombre.
- El registro se hace en la app y en la API (`POST /workers`).

### HU-011 · Primer usuario Administrador · M · 1 pt
*Como primer usuario quiero convertirme en Administrador para poder configurar el sistema.*
- El primer registro tiene `isAdmin = true`. Los siguientes, no.

### HU-012 · Inicio de sesión · M · 5 pts
*Como trabajador quiero iniciar sesión con mi usuario y mi contraseña para acceder a mis datos sin escribir el carné.*
- `POST /tokens` devuelve un token de acceso (30 min) y uno de renovación (90 días).
- Con credenciales incorrectas devuelve `INVALID_CREDENTIALS`, sin indicar cuál de los dos datos falló.
- Como alternativa se acepta el carné en lugar del usuario; quien entra así ve cuál es su usuario.
- El usuario se puede cambiar en Mi perfil.

### HU-013 · Sesión duradera · M · 3 pts
*Como trabajador quiero que la app no me pida la contraseña cada vez para no perder tiempo.*
- La app renueva el token de acceso sin intervención del usuario.
- Cada renovación entrega un token de renovación nuevo. Reutilizar uno viejo devuelve `TOKEN_REVOKED`.

### HU-014 · Cierre de sesión · M · 2 pts
*Como trabajador quiero cerrar sesión en este teléfono o en todos para proteger mi cuenta.*
- `DELETE /tokens/current` y `DELETE /tokens` revocan los tokens de renovación que corresponden.

### HU-015 · PIN de la app · S · 3 pts
*Como trabajador quiero proteger la app con un PIN propio, y que recuerde mi usuario, para entrar rápido y con seguridad en cualquier teléfono.*
- Se puede activar y desactivar en los ajustes. Funciona sin conexión.

### HU-016 · Mi perfil · M · 3 pts
*Como trabajador quiero ver y editar mi perfil y cambiar mi contraseña para mantener mis datos al día.*
- Cambiar la contraseña exige la actual y revoca todos los tokens de renovación.

### HU-017 · Foto de perfil · S · 3 pts
*Como trabajador quiero poner una foto de perfil para que me reconozcan.*
- JPG o PNG, con el tamaño máximo según `photo_max_kb`. Sin foto se muestra un icono por defecto.

### HU-018 · Privacidad del carné · M · 3 pts
*Como trabajador quiero que nadie más vea mi carné para proteger mis datos.*
- El carné se guarda cifrado, con una huella HMAC para buscar.
- Solo se devuelve en `/me` y al Administrador. Hay pruebas automáticas que lo comprueban.

### HU-019 · Activar y desactivar trabajadores · M · 2 pts
*Como Administrador quiero desactivar y reactivar trabajadores para controlar quién usa el sistema.*
- Desactivar es un borrado lógico y revoca sus tokens. Reactivar restaura la fila.

## E03 · Nomencladores y ajustes

### HU-020 · Jerarquías · M · 3 pts
*Como Administrador quiero gestionar las jerarquías y sus iconos para definir el orden de subida.*
- CRUD con `precedence` única. Subida de icono (PNG o SVG). Sin icono se muestra uno por defecto.

### HU-021 · Tipos de vehículo y de ausencia · M · 2 pts
*Como Jefe de Transporte quiero gestionar los tipos de vehículo y de ausencia para adaptarlos a la empresa.*

### HU-022 · Motivos de conversación · C · 1 pt
*Como Administrador quiero gestionar los motivos de conversación para clasificar las consultas.*

### HU-023 · Ajustes globales · M · 5 pts
*Como Administrador o Jefe de Transporte quiero cambiar los ajustes globales que me corresponden para adaptar el sistema sin programar.*
- Solo puede cambiar cada ajuste quien indica `editable_by` (y siempre el Administrador).
- Un valor fuera de los límites devuelve `SETTING_OUT_OF_RANGE`.

### HU-024 · Ajustes de usuario · M · 3 pts
*Como trabajador quiero personalizar mis ajustes y poder volver al valor global para usar la app a mi manera.*

## E04 · Itinerarios y paradas

### HU-030 · Itinerarios · M · 2 pts
*Como Jefe de Transporte quiero crear y editar itinerarios (nombre, descripción, observación) para organizar los recorridos.*

### HU-031 · Paradas con ubicación · M · 5 pts
*Como Jefe de Transporte quiero crear paradas con su dirección y marcarlas en el mapa para que todos sepan dónde están.*
- Punto de referencia, calle, entrecalles, latitud y longitud.
- La ubicación se elige tocando en el mapa (OpenStreetMap).

### HU-032 · Paradas de un itinerario · M · 3 pts
*Como Jefe de Transporte quiero ordenar las paradas de cada itinerario para definir el recorrido y sus puntos de salida y regreso.*
- Se reordenan arrastrando. La primera parada es el punto de salida y la última, el de regreso.
- Al cambiar una parada extrema se marcan como modificados los viajes pendientes del itinerario.

### HU-033 · Paradas con miembros · M · 1 pt
*Como Jefe de Transporte quiero que no se pueda quitar una parada con miembros para no dejar a nadie sin parada.*
- Devuelve `STOP_HAS_MEMBERS`.

## E05 · Solicitudes y aprobaciones

### HU-040 · Pedir itinerario y parada · M · 3 pts
*Como trabajador quiero pedir mi itinerario y mi parada (o cambiarlos) para que me asignen transporte.*
- Solo se muestran las paradas del itinerario elegido.
- Mientras la solicitud está pendiente, el trabajador sigue en su itinerario anterior.

### HU-041 · Bandeja de aprobación · M · 5 pts
*Como Jefe de itinerario o Jefe de Transporte quiero aprobar o rechazar solicitudes para controlar quién viaja.*
- Cada uno solo ve las solicitudes que puede resolver. Nadie resuelve las suyas (`SELF_APPROVAL`).
- Al aprobar una pertenencia, cambia el itinerario y la parada del trabajador.

### HU-042 · Ser Jefe de itinerario · M · 3 pts
*Como trabajador quiero pedir ser Jefe de un itinerario para controlar sus viajes.*
- La aprueba un Jefe de Transporte. Al aprobarla, el trabajador pasa a ese itinerario y parada, y se cancelan sus solicitudes de itinerario pendientes.

### HU-043 · Ser chofer · M · 2 pts
*Como trabajador quiero pedir ser chofer para que me asignen un vehículo.*

### HU-044 · Ser Jefe de Transporte · M · 2 pts
*Como trabajador quiero pedir ser Jefe de Transporte para planificar los viajes.* La aprueba el Administrador.

### HU-045 · Cambio de jerarquía · M · 2 pts
*Como trabajador quiero pedir un cambio de jerarquía para que se respete mi orden de subida.*

### HU-046 · Cancelar solicitudes · M · 1 pt
*Como trabajador quiero cancelar una solicitud pendiente para corregir un error.*

### HU-047 · Bajas voluntarias · M · 3 pts
*Como trabajador quiero darme de baja del itinerario o de un rol para dejar de tener esa responsabilidad.*
- Las cuatro bajas de [02-procesos.md §2.2](../02-procesos.md#bajas-voluntarias), con sus efectos y avisos.

### HU-048 · Avisos de solicitudes · M · 5 pts
*Como aprobador quiero saber cuándo llega una solicitud nueva, y como solicitante, cuándo se resuelve la mía, para actuar a tiempo.*
- Se crean `notices`, que la app muestra al sincronizar.

### HU-049 · Historial · M · 2 pts
*Como trabajador quiero ver el historial de mis solicitudes e itinerarios para saber por dónde he estado.*

## E06 · Hijos

### HU-050 · Declarar hijo · S · 5 pts
*Como trabajador quiero declarar a mis hijos menores para que viajen conmigo.*
- Nombre, apellidos y carné. La app no deja enviarla si el niño no tiene derecho (`CHILD_NOT_ELIGIBLE`) o si ya está declarado (`CHILD_ALREADY_DECLARED`).
- Muestra la nota para parejas. El aprobador no ve la fecha de nacimiento.

### HU-051 · Quitar hijo · S · 1 pt

### HU-052 · Edad máxima · S · 2 pts
*Como Jefe de Transporte quiero configurar la edad máxima para viajar para ajustarla a las normas de la empresa.*
- Derecho hasta el 31 de agosto siguiente al cumpleaños de la edad máxima, con pruebas para los casos límite.

### HU-053 · Cantidad de hijos pública · S · 1 pt
*Como trabajador quiero ver cuántos hijos con derecho tiene cada compañero para entender la ocupación.*

## E07 · Vehículos y choferes

### HU-060 · Vehículos · M · 3 pts
*Como Jefe de Transporte quiero gestionar los vehículos para planificar con ellos.*
- Tipo, matrícula única, asientos y capacidad de pie. Se muestra la capacidad total calculada.

### HU-061 · Chofer habitual · M · 2 pts
*Como Jefe de Transporte quiero asignar a cada vehículo su chofer habitual para que se proponga al planificar.*

## E08 · Planificación de viajes

### HU-070 · Crear viaje · M · 5 pts
*Como Jefe de Transporte quiero crear un viaje con itinerario, vehículo, chofer, salida y regreso para planificar el transporte.*
- El regreso es posterior a la salida (`TRIP_DATES_INVALID`). Se crea confirmado o no confirmado.

### HU-071 · Copiar a un rango · M · 5 pts
*Como Jefe de Transporte quiero copiar un viaje a un rango de fechas para no crearlo día a día.*
- Una fila por día, manteniendo la distancia entre salida y regreso. Si alguna falla, no se crea ninguna.

### HU-072 · Confirmar y desconfirmar · M · 5 pts
*Como Jefe de Transporte quiero confirmar o desconfirmar viajes uno a uno o en masa para controlar qué se notifica.*
- Al confirmar se comprueba el solapamiento de vehículo y chofer (`TRIP_OVERLAP`, indicando con qué viaje choca).

### HU-073 · Cancelar viaje · M · 2 pts
- No se puede cancelar un viaje realizado (`TRIP_TRANSITION_NOT_ALLOWED`).

### HU-074 · Sobresaturación · M · 3 pts
*Como Jefe de Transporte o de itinerario quiero ver en color llamativo los viajes sobresaturados para tomar medidas.*
- Pasajeros esperados según [02-procesos.md §2.6](../02-procesos.md#sobresaturación).

### HU-075 · Marcar como realizado · M · 3 pts
*Como chofer o jefe quiero marcar el viaje como realizado para dejar constancia.*
- Solo el chofer del viaje, los Jefes de su itinerario, los Jefes de Transporte y el Administrador.
- Se guarda quién lo marcó. Si se revierte, las marcas se conservan.

### HU-076 · Realizado automático · M · 2 pts
*Como Jefe de Transporte quiero que el servidor marque los viajes como realizados al pasar su hora de regreso para no tener que hacerlo a mano.*

### HU-077 · Viajes para reasignar · M · 2 pts
*Como Jefe de Transporte quiero ver los viajes cuyo chofer se dio de baja para reasignarlos.*

### HU-078 · Mis viajes · M · 3 pts
*Como trabajador quiero ver mis viajes confirmados con todos sus datos para organizarme.*
- Tipo y matrícula del vehículo, chofer, capacidad, y fecha, hora y punto de salida y de regreso.

### HU-079 · Viajes del chofer · M · 2 pts
*Como chofer quiero ver los viajes que debo hacer y cuántos pasajeros llevo para prepararme.*

## E09 · Notificaciones y sincronización

### HU-080 · Sincronización · M · 5 pts
*Como trabajador quiero que la app se mantenga al día sola, con la frecuencia que yo elija, para enterarme de los cambios.*
- Sincronización incremental (`filter[updatedSince]`), en primer y en segundo plano, con las frecuencias de [06-ajustes.md](../06-ajustes.md).

### HU-081 · Avisos de salida y regreso · M · 5 pts
*Como trabajador quiero un aviso antes de la salida y antes del regreso, cuando yo lo elija, para no perder el transporte.*
- Tiempo antes u hora fija, con la opción de qué hacer si la hora fija no sirve.

### HU-082 · Avisos de cambios · M · 3 pts
*Como trabajador quiero enterarme si mi viaje cambia, se cancela o se desconfirma para reorganizarme.*

### HU-083 · Textos personalizables · S · 3 pts
*Como trabajador quiero personalizar el texto de mis avisos para leerlos a mi manera.*

### HU-084 · Ausencia temporal · M · 5 pts
*Como trabajador quiero declarar una ausencia (vacaciones, enfermedad…) para no contar como pasajero ni perder mi plaza.*
- Se aprueba por un Jefe de itinerario o de Transporte. Tiene los efectos de [02-procesos.md §2.2](../02-procesos.md#22-solicitudes).

## E10 · Recorrido en tiempo real

### HU-090 · Iniciar y finalizar recorrido · S · 3 pts
*Como chofer o jefe quiero iniciar y finalizar cada trayecto para que todos sepan que el transporte está en camino.*
- Termina al pasar por la última parada o con el botón, lo que ocurra primero.

### HU-091 · Compartir ubicación · S · 8 pts
*Como trabajador del recorrido quiero compartir mi ubicación, cada cuánto yo elija, para que los demás sigan el transporte.*
- Servicio en primer plano con notificación fija. Sin cobertura, guarda las posiciones y las envía después.
- Deja de enviar al llegar a su parada de bajada.

### HU-092 · Combinación de sensores · S · 5 pts
*Como trabajador quiero ver una posición fiable y cuántos sensores la respaldan para confiar en ella.*
- Mediana de las posiciones recientes, descarte de sensores atípicos y cuenta de los activos.

### HU-093 · Paso por paradas · S · 5 pts
*Como sistema quiero detectar el paso por cada parada para avisar, hablar y mostrar listas.*

### HU-094 · Mapa · S · 5 pts
*Como trabajador quiero ver en un mapa el itinerario, las paradas y la posición del transporte para saber dónde está.*

### HU-095 · Línea con hitos · S · 5 pts
*Como trabajador quiero una línea con las paradas, proporcional a la distancia real, para ver el avance de un vistazo.*

### HU-096 · Avisos de paso por paradas · S · 5 pts
*Como trabajador quiero que me avise cuando el transporte pase por paradas anteriores a la mía para salir a tiempo.*
- Alcance: ninguna, la anterior o todas las anteriores, y si sigue avisando después de subir.

### HU-097 · Voz · S · 3 pts
*Como chofer o jefe quiero que la app anuncie en voz alta el recorrido para no tener que mirar la pantalla.*

### HU-098 · Estadísticas del viaje en marcha · S · 3 pts

## E11 · Subida al transporte

### HU-100 · Orden de subida · S · 3 pts
*Como chofer o Jefe de itinerario quiero la lista de pasajeros en orden de subida para organizar la subida.*
- Primero los que suben con niños; luego mujeres y después hombres; dentro de cada grupo, por jerarquía y alfabético.

### HU-101 · "Ya subí" · S · 2 pts
- El trabajador indica con cuántos niños sube (como máximo, los que tiene con derecho).

### HU-102 · Subida con QR · S · 5 pts
*Como chofer o Jefe de itinerario quiero escanear el QR de cada trabajador para registrar su subida sin errores.*
- El QR lleva un token temporal, sin el carné.

### HU-103 · Subida manual · S · 2 pts

### HU-104 · Subida automática · S · 5 pts
*Como trabajador quiero que se registre mi subida sin hacer nada si mi teléfono va con el transporte.*

### HU-105 · Lista de la próxima parada · S · 3 pts
*Como chofer o Jefe de itinerario quiero ver, al salir de una parada, quién sube o se baja en la siguiente para estar preparado.*

## E14 · Baja automática por inactividad

### HU-130 · Baja por inactividad · S · 5 pts
*Como Jefe de Transporte quiero que se libere la plaza de quien no viaja durante N días para mantener los itinerarios reales.*
- Solo cuentan los días con viajes realizados; las ausencias aprobadas no cuentan.
- Aviso previo según `inactivity_warning_days`.

## E12 · Chats

### HU-110 · Chat del viaje · C · 5 pts
- Visible mientras el viaje está confirmado. Se borra al cancelarse o realizarse.

### HU-111 · Conversaciones con jefes · C · 5 pts
*Como trabajador quiero escribir a los Jefes de mi itinerario o de Transporte, indicando el motivo, para resolver problemas, quejas o dudas.*

### HU-112 · Conversaciones con el desarrollador · C · 2 pts
*Como trabajador quiero escribir al desarrollador para dar ideas, reportar errores o pedir información.*

### HU-113 · Caducidad de conversaciones · C · 2 pts
- Se borran a los `conversation_retention_days` días del último mensaje.

## E13 · Estadísticas

### HU-120 · Selector de periodo · C · 3 pts
- Rango, fechas explícitas o relativo (últimos X días, semanas, meses o años).

### HU-121 · Estadísticas de viajes · C · 5 pts
- Por estado, puntualidad, duración y por chofer o vehículo.

### HU-122 · Estadísticas de ocupación · C · 5 pts
- Sobresaturación, ocupación, asistencia y niños transportados.

### HU-123 · Estadísticas de trabajadores y solicitudes · C · 3 pts

### HU-124 · Estadísticas de paradas y recorrido · C · 5 pts

### HU-125 · Exportar a PDF · C · 3 pts
- El PDF incluye los gráficos. Los archivos se pueden guardar o compartir.

### HU-126 · Visibilidad por rol · C · 2 pts
- Cada rol ve solo las estadísticas que le corresponden (ver [04-api.md §4.5](../04-api.md#45-permisos)).
