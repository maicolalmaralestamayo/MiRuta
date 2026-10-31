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
| PIN propio | Guardado como huella SHA-256 con sal en `flutter_secure_storage`; no depende de la huella ni del bloqueo del teléfono |
| Actualizaciones | `ota_update` (descarga con verificación SHA-256 e instalación), `package_info_plus`, `file_picker` (publicar el APK) |
| Gráficos | `fl_chart` |
| Exportación | `pdf` y `share_plus` para compartir el archivo |

## 5.2 Pantallas comunes

| Pantalla | Contenido |
|---|---|
| **Bienvenida / inicio de sesión** | Usuario (recordado en el teléfono; también admite el carné) y contraseña. Enlaces a registro y a contraseña olvidada. Quien entra con el carné ve cuál es su usuario |
| **Registro** | Carné, nombre, apellidos, usuario (propuesto a partir del nombre), jerarquía y contraseña |
| **PIN** | PIN propio de la app (4 a 6 dígitos), si el usuario lo activó. Se pide al abrir la app y al volver tras 5 minutos fuera. Tras 5 intentos fallidos, o si se olvida, se cierra la sesión |
| **Actualización** | Al abrir la app se comprueba si hay una versión nueva. Si es obligatoria, no se puede seguir sin instalarla |
| **Inicio** | Próximo viaje: tipo, matrícula, chofer, capacidad, salida y regreso. Estado de las solicitudes. Avisos sin leer |
| **Mis viajes** | Lista de viajes confirmados de su itinerario, con su estado. Indicador de cambios |
| **Detalle del viaje** | Datos completos, chat del viaje, botón **"Ya subí"**, botón **"Mi QR"**, botón **"Seguir recorrido"** |
| **Seguir recorrido** | Mapa o línea con hitos (según su ajuste), sensores activos, estadísticas del viaje en marcha |
| **Mi perfil** | Foto, nombre, apellidos, usuario (se puede cambiar), carné (solo él lo ve), jerarquía con su icono, itinerario y parada, roles, hijos |
| **Solicitudes** | Una sección por tipo: itinerario y parada, Jefe de itinerario, chofer, Jefe de Transporte, cambio de jerarquía, hijos, ausencia temporal. Historial de las propias. Cancelar las pendientes |
| **Bajas** | Darse de baja del itinerario, como Jefe de itinerario, como chofer o como Jefe de Transporte, con confirmación |
| **Hijos** | Lista de hijos declarados con su fecha límite de viaje. Declarar uno nuevo (la app comprueba la edad antes de enviar). Incluye la nota para parejas |
| **Conversaciones** | Con los Jefes de mi itinerario, con los Jefes de Transporte y con el desarrollador. Al abrir una se elige el motivo |
| **Avisos** | Avisos del servidor (solicitudes, bajas, inactividad…) |
| **Estadísticas** | Las que le corresponden por su rol. Selector de periodo (rango, fechas explícitas o relativo), gráfico + tabla, exportar a PDF |
| **Ajustes** | Ver 5.4 |

## 5.3 Pantallas por rol

### Chofer

- **Mis viajes como chofer:** viajes asignados, con fecha, itinerario, vehículo y pasajeros esperados.
- **Recorrido:** botones *Iniciar recorrido* y *Finalizar recorrido*, voz, lista de la próxima parada, escanear QR, marcar subidas a mano, marcar el viaje como realizado.

### Jefe de itinerario (en sus itinerarios)

- **Bandeja de solicitudes:** pertenencia, cambio de jerarquía, hijos (sin ver la fecha de nacimiento) y ausencias.
- **Miembros del itinerario:** por parada, en orden de subida.
- **Viajes del itinerario:** con el aviso de **sobresaturación** en color llamativo.
- **Recorrido:** igual que el chofer.
- **Conversaciones recibidas,** agrupadas por motivo.

### Jefe de Transporte

Además de todo lo del Jefe de itinerario, en cualquier itinerario:

- **Vehículos:** alta, edición y asignación del chofer habitual.
- **Choferes:** lista y asignación de vehículo.
- **Itinerarios y paradas:** alta y edición, orden de paradas arrastrando, y ubicación de las paradas tocando en el mapa.
- **Planificación de viajes:**
  - **Calendario y lista** de viajes, con filtros por itinerario, vehículo, chofer, estado y fechas.
  - **Nuevo viaje:** itinerario, vehículo (propone su chofer habitual), chofer, salida y regreso.
  - **Copiar a un rango de fechas:** desde, hasta, y si las copias se crean confirmadas o no.
  - **Selección múltiple** para confirmar, desconfirmar o cancelar.
  - **Avisos** de sobresaturación y de viajes **para reasignar**.
- **Bandeja de solicitudes:** Jefe de itinerario y chofer.
- **Ajustes globales** que le corresponden.
- **Nomencladores:** tipos de vehículo y tipos de ausencia.

### Administrador

Todo lo anterior y, además:

- **Bandeja de solicitudes** de Jefe de Transporte.
- **Trabajadores:** buscar, ver datos privados, activar y desactivar.
- **Nomencladores:** jerarquías (con su icono) y motivos de conversación.
- **Todos los ajustes globales**, incluidos los mínimos de frecuencia.
- **Actualizaciones de la app:** publicar un APK (versión, código, novedades, obligatoria o no), ver cuántos trabajadores tienen cada versión y retirar versiones.
- **Conversaciones con el desarrollador.**

## 5.4 Ajustes del usuario

Los valores por defecto y los límites están en [06-ajustes.md](06-ajustes.md).

| Grupo | Ajustes |
|---|---|
| **Avisos de salida** | Modo (tiempo antes u hora fija), minutos antes, hora fija, días antes, qué hacer si la hora fija no sirve, texto |
| **Avisos de regreso** | Igual que la salida |
| **Avisos de paso por paradas** | Alcance (ninguna, la anterior o todas las anteriores), seguir después de subir, texto |
| **Avisos de cambios y cancelaciones** | Texto |
| **Ausencias** | Recibir avisos de viaje durante una ausencia |
| **Recorrido** | Vista (mapa o línea con hitos), voz (según rol), compartir ubicación, frecuencia de envío |
| **Frecuencias** | Para cada funcionalidad, con la app abierta y en segundo plano: viajes, recorrido, chat del viaje, conversaciones, solicitudes y avisos. Activar o desactivar la sincronización en segundo plano |
| **Seguridad** (solo en el teléfono) | PIN propio de la app, recordar el usuario; buscar actualizaciones |
