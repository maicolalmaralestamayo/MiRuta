# 6. Ajustes

Todos los ajustes están en `setting_definitions` con su tipo, su valor por defecto, sus límites y su **nivel** (`level`). Hay tres niveles (docs/08-version-2.md §8.2):

| Nivel | Dónde se guarda | Quién lo cambia |
|---|---|---|
| **App** | `settings` | Solo el Administrador |
| **Entidad** | `entity_settings` | El Jefe de Transporte de cada Entidad (y el Administrador). El Administrador fija además el valor de la app, que usan las Entidades que no ponen el suyo |
| **Usuario** | `user_settings` | Cada usuario, en los ajustes marcados como personalizables |

**Valor efectivo** = el del usuario → si no hay, el de su Entidad → si no hay, el de la app → si no hay, el valor por defecto. Un ajuste con mínimo (`min_setting_definition_id`) nunca baja del valor de ese otro ajuste, y uno con máximo (`max_setting_definition_id`) nunca lo supera (ver [07-algoritmos.md §7.5](07-algoritmos.md#75-valor-efectivo-de-un-ajuste)).

Cada ajuste tiene un **nombre** y una **explicación de una línea** (`description`), que la app muestra debajo del nombre (docs/09-repaso-pantallas.md §17). Esta lista sale de `api/database/seeders/SettingDefinitionSeeder.php`.

**Ajustes retirados en la versión 2.1:** `password_forbid_personal_data` y `password_forbid_common` (ya no hay regla de datos personales ni lista de contraseñas comunes) y `password_expiry_warning_days`, que pasa a ser el ajuste de usuario `password_expiry_notice_days`. El seeder los borra si existen.

## 6.1 Ajustes de la app (solo el Administrador)

| Clave | Nombre | Explicación | Tipo | Defecto | Límites |
|---|---|---|---|---|---|
| **Caducidades** | | | | | |
| `conversation_retention_days` | Días de conservación de las conversaciones | Se cuentan desde el último mensaje. | entero | `30` | 1–365 |
| `guest_conversation_retention_days` | Días de conservación de las conversaciones sin cuenta | Se cuentan desde el último mensaje. | entero | `30` | 1–365 |
| `trip_chat_retention_days` | Días de conservación del chat de un viaje | Desde el regreso; 0 = se borra en cuanto el viaje termina. | entero | `0` | 0–365 |
| `read_notice_retention_days` | Días de conservación de los avisos leídos | Pasado ese plazo los avisos leídos se borran. | entero | `90` | 1–3650 |
| `activation_code_ttl_days` | Validez del código de activación (días) | Plazo para activar una cuenta registrada por un superior. | entero | `7` | 1–90 |
| `access_recovery_ttl_hours` | Validez de una solicitud "Olvidé algo" (horas) | Pasado ese plazo sin aprobarse, la solicitud caduca. | entero | `72` | 1–720 |
| `access_token_ttl_minutes` | Validez del token de acceso (min) | La app lo renueva sola sin pedir la contraseña. | entero | `30` | 5–240 |
| `refresh_token_ttl_days` | Validez del token de renovación (días) | Tiempo máximo de una sesión sin volver a entrar. | entero | `90` | 1–365 |
| `username_reuse_block_days` | Días de reserva de un nombre de usuario abandonado | Nadie más puede usarlo durante ese tiempo. | entero | `30` | 0–365 |
| **Contraseñas** | | | | | |
| `password_min_length` | Longitud mínima de la contraseña | Cantidad mínima de caracteres. | entero | `8` | 6–64 |
| `password_required_classes` | Tipos de carácter exigidos en la contraseña | De mayúsculas, minúsculas, números y símbolos. | entero | `3` | 1–4 |
| `password_expiry_days` | Caducidad de la contraseña (días) | Al caducar, hay que cambiarla para seguir. | entero | `365` | 30–1095 |
| `password_history_count` | Contraseñas anteriores que no se pueden repetir | Evita volver a poner las últimas contraseñas. | entero | `5` | 0–24 |
| `remember_password_max_days` | Máximo de días para recordar la contraseña | Límite del ajuste "Días para recordar la contraseña". | entero | `30` | 1–365 |
| **Límites contra el abuso** | | | | | |
| `access_recovery_max_per_hour` | Solicitudes "Olvidé algo" por hora desde un teléfono | Evita el abuso desde un mismo teléfono. | entero | `3` | 1–20 |
| `guest_messages_max_per_hour` | Mensajes por hora sin cuenta desde un teléfono | Evita el abuso desde un mismo teléfono. | entero | `10` | 1–100 |
| **Vehículos** | | | | | |
| `plate_letters` | Letras permitidas en las matrículas | Separadas por comas; la matrícula es una letra y 6 dígitos. | texto | `B,P,T` | 1–500 caracteres |
| **Mapa** | | | | | |
| `map_tiles_url` | Dirección de las imágenes del mapa | Del servidor de mapas propio; relativa a la dirección del servidor. | texto | `/tiles/{z}/{x}/{y}.png` | 1–500 caracteres |
| **Recorrido** | | | | | |
| `trip_auto_complete_delay_minutes` | Minutos tras el regreso para dar el viaje por realizado | Si nadie lo marca antes como realizado. | entero | `0` | 0–1440 |
| `stop_detection_radius_m` | Radio de detección de paradas (m) | Distancia a la que se considera que el vehículo está en la parada. | entero | `100` | 20–1000 |
| `sensor_outlier_distance_m` | Distancia para descartar un sensor (m) | Un teléfono tan alejado de los demás no se tiene en cuenta. | entero | `300` | 50–5000 |
| `sensor_stale_seconds` | Segundos sin enviar para dejar de contar un sensor | Un teléfono que deja de enviar su ubicación deja de contar. | entero | `60` | 10–600 |
| `auto_boarding_distance_m` | Distancia al vehículo para la subida automática (m) | Cerca de esa distancia se registra la subida sola. | entero | `50` | 10–500 |
| `auto_boarding_samples` | Posiciones seguidas para la subida automática | Cuántas veces seguidas tiene que estar cerca. | entero | `3` | 2–20 |
| **Tamaños** | | | | | |
| `photo_max_kb` | Tamaño máximo de la foto de perfil (KB) | Las fotos más grandes se rechazan. | entero | `2048` | 100–10240 |
| `rank_icon_max_kb` | Tamaño máximo del ícono de jerarquía (KB) | Los íconos más grandes se rechazan. | entero | `512` | 50–2048 |
| `app_max_mb` | Tamaño máximo del APK de una actualización (MB) | Los APK más grandes se rechazan. | entero | `150` | 10–500 |
| `message_max_length` | Longitud máxima de un mensaje de chat | Cantidad máxima de caracteres por mensaje. | entero | `1000` | 50–5000 |
| **Mínimos de frecuencia** | | | | | |
| `min_foreground_poll_seconds` | Frecuencia mínima de consulta con la app abierta (s) | Ningún usuario puede consultar más a menudo. | entero | `5` | 1–60 |
| `min_background_poll_minutes` | Frecuencia mínima en segundo plano (min) | Ningún usuario puede sincronizar más a menudo. | entero | `30` | 15–1440 |
| `min_location_interval_seconds` | Frecuencia mínima de envío de ubicación (s) | Ningún sensor puede enviar más a menudo. | entero | `5` | 1–60 |
| `min_in_trip_background_poll_seconds` | Frecuencia mínima en segundo plano durante un recorrido (s) | Ningún usuario puede consultar más a menudo durante el recorrido. | entero | `30` | 10–600 |

## 6.2 Ajustes de la Entidad (Jefe de Transporte)

| Clave | Nombre | Explicación | Tipo | Defecto | Límites |
|---|---|---|---|---|---|
| `child_max_age` | Edad máxima de los hijos para viajar | Hasta el 31 de agosto siguiente al cumpleaños de esa edad. | entero | `16` | 0–25 |
| `inactivity_days` | Días sin viajar para la baja automática | Pasados esos días sin viajar, sale del itinerario. | entero | `30` | 1–365 |
| `inactivity_warning_days` | Días de aviso previo a la baja por inactividad | Se avisa antes de dar la baja. | entero | `5` | 0–30 |
| `trip_delay_tolerance_minutes` | Minutos de tolerancia antes de dar un viaje por atrasado | Si el viaje no ha comenzado pasado ese tiempo, está atrasado. | entero | `5` | 0–120 |
| `stop_min_dwell_seconds` | Segundos mínimos detenido en una parada | Si se detiene menos, se considera que no paró. | entero | `15` | 0–600 |
| `stop_pass_speed_kmh` | Velocidad a partir de la cual no se detuvo (km/h) | Si no baja de esa velocidad en la parada, no paró. | entero | `5` | 1–60 |
| `route_deviation_m` | Distancia al recorrido de referencia para un desvío (m) | Si se aleja más, se avisa del desvío. | entero | `300` | 50–5000 |

Los cuatro últimos son nuevos en la versión 2.1 (viajes atrasados, paradas donde no se detuvo y desvíos; ver [02-procesos.md §2.8](02-procesos.md#28-recorrido-en-tiempo-real) y [07-algoritmos.md §7.18](07-algoritmos.md#718-paso-por-paradas-paradas-no-realizadas-y-fin-del-trayecto)).

## 6.3 Ajustes del usuario

Cada usuario los personaliza en **Ajustes**. Su valor por defecto lo fija la Entidad (o, si no, la app).

| Clave | Nombre | Explicación | Tipo | Defecto | Límites u opciones |
|---|---|---|---|---|---|
| **Aviso de viaje de ida** | | | | | |
| `departure_notice_mode` | Forma del aviso de viaje de ida | Avisar un tiempo antes o a una hora fija. | opción | `relative` | relative = Tiempo antes<br>fixed = Hora fija |
| `departure_notice_minutes_before` | Minutos antes del aviso de viaje de ida | Con la forma "Tiempo antes". | entero | `60` | 0–1440 |
| `departure_notice_fixed_time` | Hora fija del aviso de viaje de ida | Con la forma "Hora fija". | hora | `14:00` |  |
| `departure_notice_fixed_days_before` | Días antes de la hora fija del aviso de viaje de ida | 0 = el mismo día del viaje. | entero | `0` | 0–7 |
| `departure_notice_fallback` | Si la hora fija del aviso de viaje de ida ya pasó | Qué hacer si el viaje se planifica después de esa hora. | opción | `default` | default = Avisar 1 hora antes<br>none = No avisar |
| `departure_notice_template` | Texto del aviso de viaje de ida | Las palabras entre llaves se sustituyen por los datos del viaje. | texto | ver 6.4 | 1–500 caracteres |
| **Aviso de viaje de regreso** | | | | | |
| `return_notice_mode` | Forma del aviso de viaje de regreso | Avisar un tiempo antes o a una hora fija. | opción | `relative` | relative = Tiempo antes<br>fixed = Hora fija |
| `return_notice_minutes_before` | Minutos antes del aviso de viaje de regreso | Con la forma "Tiempo antes". | entero | `60` | 0–1440 |
| `return_notice_fixed_time` | Hora fija del aviso de viaje de regreso | Con la forma "Hora fija". | hora | `23:00` |  |
| `return_notice_fixed_days_before` | Días antes de la hora fija del aviso de viaje de regreso | 0 = el mismo día del viaje. | entero | `1` | 0–7 |
| `return_notice_fallback` | Si la hora fija del aviso de viaje de regreso ya pasó | Qué hacer si el viaje se planifica después de esa hora. | opción | `default` | default = Avisar 1 hora antes<br>none = No avisar |
| `return_notice_template` | Texto del aviso de viaje de regreso | Las palabras entre llaves se sustituyen por los datos del viaje. | texto | ver 6.4 | 1–500 caracteres |
| **Paradas, cambios y ausencias** | | | | | |
| `stop_notice_scope` | Avisos de paso por paradas | De qué paradas anteriores a la suya avisar. | opción | `previous` | none = Ninguna<br>previous = Solo la anterior a la mía<br>all = Todas las anteriores |
| `stop_notice_after_boarding` | Seguir avisando después de subir | Avisos de paradas aunque ya haya subido. | sí/no | no |  |
| `stop_notice_template` | Texto del aviso de paso por parada | Las palabras entre llaves se sustituyen por los datos. | texto | ver 6.4 | 1–500 caracteres |
| `change_notice_template` | Texto del aviso de cambio | Las palabras entre llaves se sustituyen por los datos. | texto | ver 6.4 | 1–500 caracteres |
| `cancel_notice_template` | Texto del aviso de cancelación | Las palabras entre llaves se sustituyen por los datos. | texto | ver 6.4 | 1–500 caracteres |
| `notify_during_absence` | Avisos de viaje durante una ausencia | Recibirlos aunque tenga una ausencia aprobada. | sí/no | no |  |
| **Comienzo y atrasos** | | | | | |
| `trip_start_notice_enabled` | Aviso de comienzo del viaje | Cuando comienza el viaje de ida o de regreso, a tiempo o con atraso. | sí/no | sí |  |
| `trip_delay_notice_enabled` | Aviso de viaje atrasado | Cuando el viaje no comienza a su hora. | sí/no | sí |  |
| **Saturación** | | | | | |
| `saturation_notice_enabled` | Avisos de saturación del transporte | Cuando los trabajadores esperados superan la capacidad. | sí/no | sí |  |
| `saturation_notice_level` | Avisar cuando el transporte esté | A partir de qué nivel avisar. | opción | `overloaded` | overloaded = Sobresaturado (no caben)<br>saturated = Saturado (van de pie) o sobresaturado |
| `saturation_notice_scope` | Avisos de saturación de | Qué viajes vigilar. | opción | `managed` | own = Mis viajes<br>managed = Los viajes que gestiono (mi itinerario o mi Entidad) |
| `saturation_notice_when` | Cuándo avisar de la saturación | Al cambiar la ocupación, antes de salir o en los dos casos. | opción | `change` | change = Cuando cambia<br>before = Antes de la salida<br>both = Las dos |
| `saturation_notice_minutes_before` | Minutos antes de la salida para el aviso de saturación | Con "Antes de la salida". | entero | `120` | 0–1440 |
| **Mensajes** | | | | | |
| `trip_chat_notice_enabled` | Avisos de mensajes nuevos en el chat del viaje | Notificación al llegar un mensaje. | sí/no | sí |  |
| `conversation_notice_enabled` | Avisos de mensajes nuevos en las conversaciones | Notificación al llegar una respuesta. | sí/no | sí |  |
| **Seguridad** | | | | | |
| `password_expiry_notice_days` | Días de aviso antes de que caduque la contraseña | Un aviso cada día durante esos días; 0 = sin avisos. | entero | `15` | 0–60 |
| `remember_password` | Recordar contraseña | No pedirla al abrir la app durante los días indicados. | sí/no | sí |  |
| `remember_password_days` | Días para recordar la contraseña | Pasado ese plazo se vuelve a pedir. | entero | `7` | 1–365, máximo: `remember_password_max_days` |
| **Recorrido** | | | | | |
| `trip_view` | Vista del recorrido | Cómo se abre el recorrido en tiempo real. | opción | `timeline` | map = Mapa<br>timeline = Línea con hitos |
| `tts_enabled` | Voz durante el recorrido | Anuncia las paradas en voz alta. | sí/no | sí |  |
| `share_location` | Compartir ubicación como sensor | Ayuda a saber dónde va el vehículo. | sí/no | no |  |
| `location_interval_seconds` | Frecuencia de envío de ubicación (s) | Cada cuánto se envía la ubicación durante el recorrido. | entero | `10` | —–600, mínimo: `min_location_interval_seconds` |
| **Frecuencias** | | | | | |
| `background_sync_enabled` | Sincronización en segundo plano | Consultar viajes, avisos y mensajes con la app cerrada. | sí/no | sí |  |
| `update_check_hours` | Comprobar actualizaciones de la app (h) | Cada cuánto se busca una versión nueva. | entero | `24` | 1–168 |
| `trips_poll_foreground_seconds` | Viajes: consulta con la app abierta (s) | Cada cuánto se actualizan los viajes. | entero | `60` | —–3600, mínimo: `min_foreground_poll_seconds` |
| `trips_poll_background_minutes` | Viajes: consulta en segundo plano (min) | Cada cuánto se actualizan con la app cerrada. | entero | `30` | —–1440, mínimo: `min_background_poll_minutes` |
| `tracking_poll_foreground_seconds` | Recorrido: consulta con la app abierta (s) | Cada cuánto se actualiza la posición del vehículo. | entero | `10` | —–600, mínimo: `min_foreground_poll_seconds` |
| `tracking_poll_background_seconds` | Recorrido: consulta en segundo plano (s) | Con la app cerrada durante el recorrido. | entero | `60` | —–3600, mínimo: `min_in_trip_background_poll_seconds` |
| `trip_chat_poll_foreground_seconds` | Chat del viaje: consulta con la app abierta (s) | Cada cuánto se buscan mensajes nuevos. | entero | `5` | —–600, mínimo: `min_foreground_poll_seconds` |
| `trip_chat_poll_background_minutes` | Chat del viaje: consulta en segundo plano (min) | Con la app cerrada. | entero | `30` | —–1440, mínimo: `min_background_poll_minutes` |
| `conversations_poll_foreground_seconds` | Conversaciones: consulta con la app abierta (s) | Cada cuánto se buscan respuestas nuevas. | entero | `10` | —–600, mínimo: `min_foreground_poll_seconds` |
| `conversations_poll_background_minutes` | Conversaciones: consulta en segundo plano (min) | Con la app cerrada. | entero | `30` | —–1440, mínimo: `min_background_poll_minutes` |
| `notices_poll_foreground_seconds` | Solicitudes y avisos: consulta con la app abierta (s) | Cada cuánto se buscan avisos nuevos. | entero | `60` | —–3600, mínimo: `min_foreground_poll_seconds` |
| `notices_poll_background_minutes` | Solicitudes y avisos: consulta en segundo plano (min) | Con la app cerrada. | entero | `30` | —–1440, mínimo: `min_background_poll_minutes` |

**Ajustes que solo están en el teléfono** (no van al servidor): recordar el último usuario, descargar actualizaciones solo con Wi-Fi (desactivado por defecto) y la descarga del mapa sin conexión de la zona de la Entidad ([05-app.md §5.4](05-app.md#54-ajustes-del-usuario)).

## 6.4 Textos de aviso por defecto

| Aviso | Texto |
|---|---|
| Viaje de ida | `Viaje de ida: {fecha_salida} a las {hora_salida} desde {punto_salida}. {tipo} {matricula}, chofer {chofer}, capacidad {capacidad}. Viaje de regreso: {fecha_regreso} a las {hora_regreso} desde {punto_regreso}.` |
| Viaje de regreso | `Viaje de regreso: {fecha_regreso} a las {hora_regreso} desde {punto_regreso}. {tipo} {matricula}, chofer {chofer}, capacidad {capacidad}.` |
| Paso por parada | `El transporte pasó por {parada} a las {hora}. Faltan {paradas_restantes} paradas para la suya.` |
| Cambio | `Cambió su viaje de {itinerario} del {fecha_salida}: {cambios}.` |
| Cancelación | `Se canceló su viaje de {itinerario} del {fecha_salida}.` |

Las variables disponibles están en [02-procesos.md §2.7](02-procesos.md#27-notificaciones). Los avisos que genera el servidor (solicitudes, comienzo, atrasos, incidencias del recorrido, caducidad de la contraseña) no se personalizan: su texto lo da la API en `notices.message` ([02-procesos.md §2.7](02-procesos.md#avisos-del-servidor)).
