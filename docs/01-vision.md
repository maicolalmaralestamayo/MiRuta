# 1. Visión, alcance y roles

## 1.1 Visión

**MiTransporte** es una aplicación para gestionar el transporte que la empresa pone a disposición de sus trabajadores: los itinerarios, sus paradas, los vehículos, los choferes y los viajes de salida y regreso. Además permite seguir los recorridos en tiempo real.

Sustituye la coordinación manual (listas, llamadas, mensajes sueltos) por un sistema único donde:

- cada trabajador sabe qué transporte le toca, a qué hora, desde dónde y quién lo conduce;
- el Jefe de Transporte planifica los viajes y ve de inmediato cuándo un vehículo está sobresaturado;
- los Jefes de itinerario controlan quién sube, en qué orden y en qué parada;
- todo cambio queda registrado como historial.

## 1.2 Stack tecnológico

| Capa | Tecnología |
|---|---|
| App móvil | Flutter (Android) |
| API | Lumen 7 (PHP ≥ 7.2.5), patrón modelo-controlador, convenciones de Laravel |
| Formato de la API | [JSON:API 1.1](https://jsonapi.org/format/), con la extensión *Atomic Operations* para las operaciones en lote |
| Autenticación | JWT ([RFC 7519](https://www.rfc-editor.org/rfc/rfc7519)): token de acceso de 30 min y token de renovación de 90 días, con rotación |
| Base de datos | MariaDB, en el mismo servidor que la API (acceso por `localhost`) |
| Mapas | OpenStreetMap con `flutter_map` |
| Notificaciones | Locales, programadas en el teléfono (`flutter_local_notifications`) y sincronizadas periódicamente (`workmanager`) |
| Voz | TTS del teléfono (`flutter_tts`) |

**Idiomas:** el código, la base de datos y la API van en **inglés**. La interfaz de la app y esta documentación, en **español**.

### Deuda técnica conocida

- **PHP 7.x y Lumen 7 no tienen soporte de seguridad.** Se aceptan por restricción del servidor. Conviene confirmar la versión exacta con `php -v` y, en cuanto se pueda, migrar a PHP 8 y Lumen 10 (o Laravel).
- El código se escribe compatible con PHP 7.2.5: sin propiedades tipadas, sin funciones flecha y sin `??=`.

## 1.3 Alcance

**Incluido:**

- Cuentas de usuario, roles y solicitudes con aprobación jerárquica.
- Itinerarios, paradas (con coordenadas), vehículos y choferes.
- Planificación de viajes (individual y por rango de fechas), confirmación, cancelación y marca de realizado.
- Detección de sobresaturación.
- Hijos menores que viajan con sus padres.
- Notificaciones de salida, regreso, cambios y paso por paradas, con texto configurable.
- Seguimiento del recorrido en tiempo real, con varios teléfonos como sensores, mapa o línea de hitos, y voz.
- Registro de subida al transporte (automático, "Ya subí", QR o manual) y orden de subida.
- Chats: del viaje, con los Jefes de itinerario, con los Jefes de Transporte y con el desarrollador.
- Estadísticas con gráficos y tablas, exportables a Excel y PDF.
- Baja automática por inactividad y ausencias temporales.

**Fuera de alcance (por ahora):**

- App para iOS.
- Notificaciones *push* desde el servidor.
- Cálculo de rutas por calles mediante servicios externos.

## 1.4 Roles de la aplicación

Todos los usuarios son **trabajadores**. **Una persona puede tener varios roles a la vez** (por ejemplo, chofer y Jefe de itinerario); cada uno se solicita por separado. El **Administrador** tiene, además, todos los permisos de Jefe de Transporte y de Jefe de todos los itinerarios. Los roles solo añaden permisos para aprobar y planificar. Quien tiene un rol sigue viajando en su itinerario y pide los cambios como cualquier otro trabajador.

| Rol | Cómo se obtiene | Qué puede hacer |
|---|---|---|
| **Administrador** | Es el primer usuario que se registra | Todo. Además es el **desarrollador**: recibe las conversaciones de ideas, errores y consultas sobre la app |
| **Jefe de Transporte** | Solicitud aprobada por el Administrador | Gestiona vehículos, choferes, itinerarios, paradas y viajes. Aprueba a Jefes de itinerario y a choferes. Hace todo lo que hace un Jefe de itinerario, en cualquier itinerario. Ve todo |
| **Jefe de itinerario** | Solicitud aprobada por un Jefe de Transporte | En **su** itinerario: **planifica sus viajes**, aprueba solicitudes de miembros, controla la subida y marca viajes como realizados. Puede haber cualquier cantidad por itinerario, pero **cada persona solo puede ser Jefe de un itinerario** |
| **Chofer** | Solicitud aprobada por un Jefe de Transporte | Ve sus viajes, comparte ubicación, controla la subida y marca sus viajes como realizados. El Jefe de Transporte le asigna un vehículo |
| **Trabajador** | Registrándose | Pide su itinerario y su parada, ve sus viajes, recibe avisos y sigue el recorrido |

## 1.5 Roles Scrum

| Rol Scrum | Persona |
|---|---|
| Product Owner | Jefe de Transporte de la Unidad de Servicios |
| Scrum Master | Jefe del Centro de Desarrollo |
| Equipo de desarrollo | Maicol Almarales Tamayo, Especialista de Automatización |

## 1.6 Glosario

| Término | Significado |
|---|---|
| **Itinerario** | Recorrido fijo, formado por una lista ordenada de paradas |
| **Parada** | Lugar donde se suben o se bajan trabajadores. Tiene punto de referencia, calle, entrecalles y coordenadas. Puede estar en varios itinerarios |
| **Vehículo** (transporte) | Guagua, carro u otro tipo. Tiene matrícula, asientos y capacidad de pie |
| **Capacidad total** | Asientos + capacidad de pie. Se calcula, no se guarda |
| **Viaje** | Planificación de un itinerario con un vehículo y un chofer, con fecha y hora de salida y de regreso |
| **Trayecto** | Cada una de las dos partes de un viaje: **salida** (en el orden de las paradas) y **regreso** (en orden inverso) |
| **Punto de salida / regreso** | La primera y la última parada del itinerario. Se calculan, no se guardan en el viaje |
| **Sobresaturación** | Situación en que los pasajeros esperados superan la capacidad total del vehículo |
| **Sensor** | Teléfono que envía su ubicación durante un trayecto |
| **Jerarquía** | Categoría del trabajador que determina su prioridad al subir. Es solo un orden, sin ningún otro significado |
| **Solicitud** | Petición de un trabajador que otro con autoridad aprueba o rechaza. Las solicitudes forman el historial |
| **Nomenclador** | Tabla de valores editables (jerarquías, tipos de vehículo, tipos de ausencia, motivos de conversación) |
