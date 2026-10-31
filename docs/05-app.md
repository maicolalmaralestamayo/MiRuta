# 5. App móvil (Flutter, Android)

Interfaz en **español**. Las opciones de menú solo aparecen si el rol del usuario las permite.

## 5.1 Arquitectura

| Aspecto | Decisión |
|---|---|
| Estructura | Por funcionalidad (`lib/features/<funcionalidad>/{data,domain,presentation}`) |
| Cliente HTTP | `dio`, con un interceptor que añade el JWT y renueva el token automáticamente al recibir 401 |
| JSON:API | Parser propio para `data`, `included`, `relationships` y `errors` |
| Almacenamiento seguro | `flutter_secure_storage`: token de renovación y último usuario |
| Base local | `sqflite`: copia de los viajes para comparar cambios y trabajar sin conexión |
| Tareas en segundo plano | `workmanager` (sincronización) y servicio en primer plano para compartir ubicación |
| Notificaciones | `flutter_local_notifications` |
| Mapa | `flutter_map` + OpenStreetMap |
| Ubicación | `geolocator` |
| QR | `qr_flutter` (mostrar) y `mobile_scanner` (escanear) |
| Voz | `flutter_tts` |
| PIN propio | Guardado como hash **PBKDF2-HMAC-SHA256** con sal en `flutter_secure_storage`; no depende de la huella ni del bloqueo del teléfono |
| Servidor | La dirección del servidor **no se pide al abrir la app**: puede venir puesta al compilar (`./build_release.sh <dirección>`, opcional) y el usuario la indica o la cambia con el botón **Servidor**. Se guarda en el teléfono. La app **no impone el protocolo**: sirve con `https://` y con `http://` (`usesCleartextTraffic`) |
| Ícono | El de la pantalla de bienvenida se dibuja con las mismas formas y colores que el ícono adaptable de Android (`AppIcon`), así siempre coinciden |
| Instalación | `device_info_plus`: modelo del teléfono y tipos de procesador admitidos. La instalación se registra en el servidor la primera vez que hace falta (cabecera `X-Installation`) |
| Actualizaciones | `ota_update` (descarga con verificación SHA-256 e instalación), `package_info_plus`, `file_picker` (publicar los APK), `connectivity_plus` (solo con Wi-Fi), `share_plus` (compartir la app) |
| Gráficos | `fl_chart` (las estadísticas no se exportan) |
| Indicador de carga | Componentes comunes (`BusyButton`, `BusyIconButton`, `BusyListTile`, `BusySwitchListTile`): mientras se espera al servidor, el control que lanzó la acción muestra el indicador y queda desactivado |

## 5.2 Pantallas comunes

| Pantalla | Contenido |
|---|---|
| **Servidor** | Se abre con el botón **Servidor** del pie de la bienvenida (muestra la dirección actual). Se escribe la dirección, p. ej. `transporte.miempresa.com`; si no lleva protocolo, la app prueba primero `https://` y, si ahí no responde, `http://`, añade `/api/v1`, comprueba que responde MiTransporte y la guarda (avisa si la conexión va sin cifrar). Si se intenta entrar sin servidor, la app indica que se use ese botón. Si la dirección cambia, la instalación se vuelve a registrar en el servidor nuevo. Al compartir la app, el mensaje incluye la dirección |
| **Bienvenida / inicio de sesión** | Ícono de la app, usuario (recordado en el teléfono) y contraseña. Enlaces a **No puedo entrar**, **Crear cuenta**, **Ya me registró un superior** y **Hablar con el desarrollador** |
| **Crear cuenta** | Cuatro nombres, usuario (lo elige el usuario; la app comprueba las reglas mientras escribe) y contraseña (con los requisitos a la vista) |
| **Unirse a la Entidad** | Abreviatura de la Entidad (la app muestra su nombre para confirmar), Pase, sexo y jerarquía. Obligatoria salvo para el Administrador |
| **Ya me registró un superior** | Abreviatura, Pase, código de activación, usuario y contraseña |
| **No puedo entrar** | Qué olvidó (usuario, contraseña o los dos), abreviatura, Pase y teléfono. Después muestra el estado; al aprobarse, el usuario o la contraseña nueva |
| **Hablar con el desarrollador (sin cuenta)** | Nombre, teléfono, motivo y mensaje; las respuestas llegan a ese teléfono |
| **Contraseña nueva obligatoria** | Cuando caduca la contraseña (pide también la actual) o tras recuperar el acceso |
| **PIN** | PIN propio de la app (4 a 6 dígitos), si el usuario lo activó. Se pide al abrir la app y al volver tras 5 minutos fuera. Tras 5 intentos fallidos, o si se olvida, se cierra la sesión |
| **Actualización** | Al abrir la app se comprueba si hay una versión nueva. Si es obligatoria, no se puede seguir sin instalarla |
| **Inicio** | Próximo viaje: tipo, matrícula, chofer, capacidad, salida y regreso. Estado de las solicitudes. Avisos sin leer |
| **Mis viajes** | Lista de viajes confirmados de su itinerario, con su estado. Indicador de cambios |
| **Detalle del viaje** | Datos completos, chat del viaje, botón **"Ya subí"**, botón **"Mi QR"**, botón **"Seguir recorrido"** |
| **Seguir recorrido** | Mapa o línea con hitos (según su ajuste), sensores activos, estadísticas del viaje en marcha |
| **Mi perfil** | Foto, nombres, usuario (se puede cambiar), Entidad, Pase, jerarquía (se cambia aquí, sin solicitud), caducidad de la contraseña, itinerario y parada, roles, hijos |
| **Solicitudes** | Una sección por tipo: itinerario y parada, Jefe de itinerario, chofer, Jefe de Transporte, hijos, ausencia temporal. Historial de las propias (incluidas las asignaciones de superiores). Cancelar las pendientes |
| **Bajas** | Darse de baja del itinerario, como Jefe de itinerario, como chofer o como Jefe de Transporte, con confirmación |
| **Hijos** | Lista de hijos declarados con su fecha de nacimiento y su fecha límite de viaje. Declarar uno nuevo con cuatro nombres y fecha de nacimiento (la app comprueba la edad antes de enviar). Incluye la nota para parejas |
| **Conversaciones** | Con los Jefes de mi itinerario, con los Jefes de Transporte de mi Entidad y con el desarrollador. Al abrir una se elige el motivo |
| **Avisos** | Avisos del servidor (solicitudes, bajas, inactividad…) |
| **Estadísticas** | Las que le corresponden por su rol. Selector de periodo (rango, fechas explícitas o relativo), gráfico + tabla. No se exportan |
| **Compartir la app** | En **Más**: envía el APK eligiendo el tipo de teléfono (64 bits por defecto o 32 bits) |
| **Ajustes** | Ver 5.4 |

## 5.3 Pantallas por rol

### Chofer

- **Mis viajes como chofer:** viajes asignados, con fecha, itinerario, vehículo y pasajeros esperados.
- **Recorrido:** botones *Iniciar recorrido* y *Finalizar recorrido*, voz, lista de la próxima parada, escanear QR, marcar subidas a mano, marcar el viaje como realizado.

### Jefe de itinerario (en sus itinerarios)

- **Bandeja de solicitudes:** pertenencia (viendo el Pase de quien la pide), hijos (con aviso de posible duplicado) y ausencias.
- **Miembros del itinerario:** asignar o quitar itinerario y parada, y **registrar trabajadores sin teléfono** (con su código de activación, también como QR).
- **Planificación de viajes** de su itinerario.
- **Viajes del itinerario:** con la ocupación en color: naranja si van de pie (saturado), rojo si no caben (sobresaturado).
- **Recorrido:** igual que el chofer.
- **Conversaciones recibidas,** agrupadas por motivo.

### Jefe de Transporte

Además de todo lo del Jefe de itinerario, en cualquier itinerario de **su Entidad**:

- **Vehículos:** alta, edición y asignación del chofer habitual.
- **Choferes:** lista y asignación de vehículo.
- **Itinerarios y paradas:** alta y edición, orden de paradas arrastrando, y ubicación de las paradas tocando en el mapa.
- **Planificación de viajes:**
  - **Calendario y lista** de viajes, con filtros por itinerario, vehículo, chofer, estado y fechas.
  - **Nuevo viaje:** itinerario, vehículo (propone su chofer habitual), chofer, salida y regreso.
  - **Copiar a un rango de fechas:** desde, hasta, y si las copias se crean confirmadas o no.
  - **Selección múltiple** para confirmar, desconfirmar o cancelar.
  - **Avisos** de saturación y de viajes **para reasignar**.
- **Bandeja de solicitudes:** Jefe de itinerario y chofer.
- **Trabajadores:** registrar sin teléfono, regenerar códigos, hacer o quitar chofer y Jefe de itinerario, asignar itinerario y parada.
- **Ajustes de la Entidad**, incluidos los valores por defecto de los ajustes de cada usuario.

### Administrador

Todo lo anterior y, además:

- **Selector de Entidad** en Gestión: con qué Entidad trabaja (o todas).
- **Entidades:** crear, editar, desactivar y reactivar.
- **Bandeja de solicitudes** de Jefe de Transporte; hacer o quitar Jefe de Transporte.
- **No puedo entrar:** ver con quién coinciden los datos, llamar, aprobar, rechazar y bloquear el teléfono.
- **Trabajadores:** buscar, ver datos privados, activar y desactivar.
- **Nomencladores:** jerarquías (con su icono y orden), tipos de vehículo, tipos de ausencia, motivos de conversación y palabras no permitidas en los usuarios.
- **Ajustes de la app** (caducidades, contraseñas, límites, mínimos de frecuencia) y los de cualquier Entidad.
- **Actualizaciones de la app:** publicar los APK de 64 y 32 bits (versión, código, novedades, obligatoria o no), ver cuántas cuentas tienen cada versión y retirar versiones.
- **Conversaciones con el desarrollador**, también las de quien aún no tiene cuenta (marcadas "sin cuenta"); cerrarlas.

## 5.4 Ajustes del usuario

Los valores por defecto y los límites están en [06-ajustes.md](06-ajustes.md).

| Grupo | Ajustes |
|---|---|
| **Avisos de salida** | Modo (tiempo antes u hora fija), minutos antes, hora fija, días antes, qué hacer si la hora fija no sirve, texto |
| **Avisos de regreso** | Igual que la salida |
| **Avisos de paso por paradas** | Alcance (ninguna, la anterior o todas las anteriores), seguir después de subir, texto |
| **Avisos de cambios y cancelaciones** | Texto |
| **Saturación del transporte** | Recibirlos, nivel (solo sobresaturado o también saturado), de qué viajes (los míos o los que gestiono), cuándo (al cambiar, antes de la salida o las dos) y minutos antes |
| **Ausencias** | Recibir avisos de viaje durante una ausencia |
| **Recorrido** | Vista (mapa o línea con hitos), voz (según rol), compartir ubicación, frecuencia de envío |
| **Frecuencias** | Para cada funcionalidad, con la app abierta y en segundo plano: viajes, recorrido, chat del viaje, conversaciones, solicitudes y avisos. Activar o desactivar la sincronización en segundo plano |
| **Seguridad** (solo en el teléfono) | PIN propio de la app, recordar el usuario |
| **Actualizaciones** (solo en el teléfono) | Descargar solo con Wi-Fi (desactivado por defecto); buscar actualizaciones |

Cada ajuste vale lo que elija el usuario; si no eligió nada, lo que fije su Entidad; y si tampoco, el valor de la app.
