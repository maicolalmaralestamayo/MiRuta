# 1. Visión, alcance y roles

## 1.1 Visión

**MiTransporte** es una aplicación para gestionar el transporte que las empresas (**Entidades**) ponen a disposición de sus trabajadores. La usan varias Entidades a la vez, cada una con sus datos separados. Gestiona los itinerarios, sus paradas, los vehículos, los choferes y los viajes de salida y regreso. Además permite seguir los recorridos en tiempo real.

Sustituye la coordinación manual (listas, llamadas, mensajes sueltos) por un sistema único donde:

- cada trabajador sabe qué transporte le toca, a qué hora, desde dónde y quién lo conduce;
- el Jefe de Transporte planifica los viajes y ve de inmediato cuándo un vehículo va saturado (de pie) o sobresaturado (no caben);
- los Jefes de itinerario controlan quién sube y en qué parada;
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

- Varias **Entidades**, con los datos de cada una separados; el Administrador las gestiona todas.
- Cuentas de usuario (registro en dos pasos), roles por solicitud o asignados por un superior, y trabajadores sin teléfono registrados por sus jefes.
- Política de contraseñas con caducidad anual, recuperación del acceso aprobada por el Administrador y conversaciones con el desarrollador sin cuenta.
- Itinerarios, paradas (con coordenadas), vehículos y choferes.
- Planificación de viajes (individual y por rango de fechas), confirmación, cancelación y marca de realizado.
- Ocupación en tres niveles: normal, saturado (van de pie) y sobresaturado (no caben). Los niños van cargados y no cuentan.
- Hijos menores que viajan con sus padres.
- Notificaciones de salida, regreso, cambios y paso por paradas, con texto configurable.
- Seguimiento del recorrido en tiempo real, con varios teléfonos como sensores, mapa o línea de hitos, y voz.
- Registro de subida al transporte (automático, "Ya subí", QR o manual).
- Chats: del viaje, con los Jefes de itinerario, con los Jefes de Transporte y con el desarrollador.
- Estadísticas con gráficos y tablas (solo se ven en la app; no se exportan).
- Baja automática por inactividad y ausencias temporales.

**Fuera de alcance (por ahora):**

- App para iOS.
- Notificaciones *push* desde el servidor.
- Cálculo de rutas por calles mediante servicios externos.

## 1.4 Roles de la aplicación

Cada persona tiene una **cuenta**. Salvo el **Administrador**, que está fuera del sistema y no es trabajador, cada cuenta tiene un **trabajador** en una sola **Entidad**, identificado por su **Pase**. **Una persona puede tener varios roles a la vez** (por ejemplo, chofer y Jefe de itinerario); cada uno se solicita por separado o lo asigna un superior. Los roles son de la Entidad del trabajador. El **Administrador** ve y hace todo, en todas las Entidades: cuenta como Jefe de Transporte y Jefe de todos los itinerarios. Los roles solo añaden permisos para aprobar y planificar. Quien tiene un rol sigue viajando en su itinerario y pide los cambios como cualquier otro trabajador.

| Rol | Cómo se obtiene | Qué puede hacer |
|---|---|---|
| **Administrador** | Es la primera cuenta que se crea (no es trabajador) | Todo, en todas las Entidades: crea las Entidades, los nomencladores y los ajustes de la app, y atiende "No puedo entrar". Además es el **desarrollador**: recibe las conversaciones de ideas, errores y consultas, también de quien aún no tiene cuenta |
| **Jefe de Transporte** | Solicitud aprobada por el Administrador, o asignado por él | En **su Entidad**: gestiona vehículos, choferes, itinerarios, paradas, viajes y los ajustes de la Entidad. Aprueba, asigna y retira Jefes de itinerario y choferes. Registra trabajadores sin teléfono. Hace todo lo que hace un Jefe de itinerario, en cualquier itinerario de su Entidad |
| **Jefe de itinerario** | Solicitud aprobada por un Jefe de Transporte, o asignado por él | En **su** itinerario: **planifica sus viajes**, aprueba o asigna miembros, registra trabajadores sin teléfono, controla la subida y marca viajes como realizados. Puede haber cualquier cantidad por itinerario, pero **cada persona solo puede ser Jefe de un itinerario** |
| **Chofer** | Solicitud aprobada por un Jefe de Transporte, o asignado por él | Ve sus viajes, comparte ubicación, controla la subida y marca sus viajes como realizados. El Jefe de Transporte le asigna un vehículo |
| **Trabajador** | Creando su cuenta y uniéndose a su Entidad, o registrado por un superior | Pide su itinerario y su parada, ve sus viajes, recibe avisos y sigue el recorrido |

## 1.5 Roles Scrum

| Rol Scrum | Persona |
|---|---|
| Product Owner | Jefe de Transporte de la Unidad de Servicios |
| Scrum Master | Jefe del Centro de Desarrollo |
| Equipo de desarrollo | Maicol Almarales Tamayo, Especialista de Automatización |

## 1.6 Glosario

| Término | Significado |
|---|---|
| **Entidad** | Empresa que usa la app. Se muestra por su **abreviatura**. Tiene sus propios itinerarios, paradas, vehículos y trabajadores |
| **Pase** | Número del trabajador dentro de su Entidad. Único en ella |
| **Cuenta** | Usuario y contraseña de una persona. El Administrador tiene cuenta pero no es trabajador |
| **Itinerario** | Recorrido fijo, formado por una lista ordenada de paradas |
| **Parada** | Lugar donde se suben o se bajan trabajadores. Tiene punto de referencia, calle, entrecalles y coordenadas. Puede estar en varios itinerarios |
| **Vehículo** (transporte) | Guagua, carro u otro tipo. Tiene matrícula, asientos y capacidad de pie |
| **Capacidad total** | Asientos + capacidad de pie. Se calcula, no se guarda |
| **Viaje** | Planificación de un itinerario con un vehículo y un chofer, con fecha y hora de salida y de regreso |
| **Trayecto** | Cada una de las dos partes de un viaje: **salida** (en el orden de las paradas) y **regreso** (en orden inverso) |
| **Punto de salida / regreso** | La primera y la última parada del itinerario. Se calculan, no se guardan en el viaje |
| **Saturación** | Los trabajadores esperados superan los asientos, pero caben de pie |
| **Sobresaturación** | Los trabajadores esperados superan la capacidad total (asientos + de pie). Los niños no cuentan |
| **Sensor** | Teléfono que envía su ubicación durante un trayecto |
| **Jerarquía** | Categoría del trabajador, común a todas las Entidades. Solo sirve para las estadísticas; cada uno la cambia en su perfil |
| **Solicitud** | Petición de un trabajador que otro con autoridad aprueba o rechaza. Las solicitudes forman el historial |
| **Nomenclador** | Tabla de valores editables, común a todas las Entidades (jerarquías, tipos de vehículo, tipos de ausencia, motivos de conversación, palabras no permitidas en los usuarios) |
