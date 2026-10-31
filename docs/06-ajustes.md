# 6. Ajustes

Todos los ajustes están en `setting_definitions` con su tipo, su valor por defecto, sus límites y su **nivel** (`level`). Hay tres niveles (docs/08-version-2.md §8.2):

| Nivel | Dónde se guarda | Quién lo cambia |
|---|---|---|
| **App** | `settings` | Solo el Administrador |
| **Entidad** | `entity_settings` | El Jefe de Transporte de cada Entidad (y el Administrador). El Administrador fija además el valor de la app, que usan las Entidades que no ponen el suyo |
| **Usuario** | `user_settings` | Cada usuario, en los ajustes marcados como personalizables |

**Valor efectivo** = el del usuario → si no hay, el de su Entidad → si no hay, el de la app → si no hay, el valor por defecto. Un ajuste con mínimo (`min_setting_definition_id`) nunca baja del valor de ese otro ajuste.

Esta lista sale de `api/database/seeders/SettingDefinitionSeeder.php`.

## 6.1 Ajustes de la app (solo el Administrador)

| Clave | Descripción | Tipo | Defecto | Límites u opciones |
|---|---|---|---|---|
| `conversation_retention_days` | Días de conservación de las conversaciones. Se cuentan desde el último mensaje. | entero | `30` | 1–365 |
| `guest_conversation_retention_days` | Días de conservación de las conversaciones sin cuenta. Se cuentan desde el último mensaje. | entero | `30` | 1–365 |
| `trip_chat_retention_days` | Días de conservación del chat de un viaje tras su regreso. 0 = se borra en cuanto el viaje deja de estar confirmado. | entero | `0` | 0–365 |
| `read_notice_retention_days` | Días de conservación de los avisos leídos | entero | `90` | 1–3650 |
| `activation_code_ttl_days` | Validez del código de activación (días) | entero | `7` | 1–90 |
| `access_recovery_ttl_hours` | Validez de una solicitud "No puedo entrar" (horas) | entero | `72` | 1–720 |
| `boarding_pass_ttl_seconds` | Validez del código QR de subida (s) | entero | `120` | 30–3600 |
| `access_token_ttl_minutes` | Validez del token de acceso (min) | entero | `30` | 5–240 |
| `refresh_token_ttl_days` | Validez del token de renovación (días) | entero | `90` | 1–365 |
| `username_reuse_block_days` | Días que un usuario abandonado queda bloqueado para los demás | entero | `30` | 0–365 |
| `password_min_length` | Longitud mínima de la contraseña | entero | `8` | 6–64 |
| `password_required_classes` | Tipos de carácter exigidos en la contraseña (de mayúscula, minúscula, número y símbolo) | entero | `3` | 1–4 |
| `password_forbid_personal_data` | La contraseña no puede contener el usuario ni los nombres | sí/no | sí |  |
| `password_forbid_common` | La contraseña no puede ser una de las más comunes | sí/no | sí |  |
| `password_expiry_days` | Caducidad de la contraseña (días) | entero | `365` | 30–1095 |
| `password_expiry_warning_days` | Aviso antes de que caduque la contraseña (días) | entero | `15` | 0–60 |
| `password_history_count` | Contraseñas anteriores que no se pueden repetir | entero | `5` | 0–24 |
| `access_recovery_max_per_hour` | Solicitudes "No puedo entrar" por hora desde un teléfono | entero | `3` | 1–20 |
| `guest_messages_max_per_hour` | Mensajes por hora sin cuenta desde un teléfono | entero | `10` | 1–100 |
| `trip_auto_complete_delay_minutes` | Minutos tras el regreso para marcar el viaje como realizado | entero | `0` | 0–1440 |
| `stop_detection_radius_m` | Radio de detección de paradas (m) | entero | `100` | 20–1000 |
| `sensor_outlier_distance_m` | Distancia para descartar un sensor (m) | entero | `300` | 50–5000 |
| `sensor_stale_seconds` | Segundos sin enviar para dejar de contar un sensor | entero | `60` | 10–600 |
| `auto_boarding_distance_m` | Distancia máxima al vehículo para la subida automática (m) | entero | `50` | 10–500 |
| `auto_boarding_samples` | Posiciones seguidas necesarias para la subida automática | entero | `3` | 2–20 |
| `photo_max_kb` | Tamaño máximo de la foto de perfil (KB) | entero | `2048` | 100–10240 |
| `rank_icon_max_kb` | Tamaño máximo del icono de jerarquía (KB) | entero | `512` | 50–2048 |
| `app_max_mb` | Tamaño máximo del APK de una actualización (MB) | entero | `150` | 10–500 |
| `message_max_length` | Longitud máxima de un mensaje de chat | entero | `1000` | 50–5000 |
| `min_foreground_poll_seconds` | Frecuencia mínima de consulta con la app abierta (s) | entero | `5` | 1–60 |
| `min_background_poll_minutes` | Frecuencia mínima de sincronización en segundo plano (min) | entero | `30` | 15–1440 |
| `min_location_interval_seconds` | Frecuencia mínima de envío de ubicación (s) | entero | `5` | 1–60 |
| `min_in_trip_background_poll_seconds` | Frecuencia mínima en segundo plano durante un recorrido (s) | entero | `30` | 10–600 |

## 6.2 Ajustes de la Entidad (Jefe de Transporte)

| Clave | Descripción | Tipo | Defecto | Límites u opciones |
|---|---|---|---|---|
| `child_max_age` | Edad máxima de los hijos para viajar. Tienen derecho hasta el 31 de agosto siguiente al cumpleaños de esta edad. | entero | `16` | 0–25 |
| `inactivity_days` | Días sin viajar para la baja automática | entero | `30` | 1–365 |
| `inactivity_warning_days` | Días de aviso previo a la baja por inactividad | entero | `5` | 0–30 |

## 6.3 Ajustes del usuario

Cada usuario los personaliza. Su valor por defecto lo fija la Entidad (o, si no, la app).

| Clave | Descripción | Tipo | Defecto | Límites u opciones |
|---|---|---|---|---|
| `departure_notice_mode` | Forma del aviso de salida | opción | `relative` | fixed = Hora fija<br>relative = Tiempo antes |
| `departure_notice_minutes_before` | Minutos antes del aviso de salida | entero | `60` | 0–1440 |
| `departure_notice_fixed_time` | Hora fija del aviso de salida | hora | `14:00` |  |
| `departure_notice_fixed_days_before` | Días antes de la hora fija del aviso de salida | entero | `0` | 0–7 |
| `departure_notice_fallback` | Si la hora fija del aviso de salida no sirve | opción | `default` | default = Avisar 1 hora antes<br>none = No avisar |
| `departure_notice_template` | Texto del aviso de salida | texto | ver 6.4 | 1–500 caracteres |
| `return_notice_mode` | Forma del aviso de regreso | opción | `relative` | fixed = Hora fija<br>relative = Tiempo antes |
| `return_notice_minutes_before` | Minutos antes del aviso de regreso | entero | `60` | 0–1440 |
| `return_notice_fixed_time` | Hora fija del aviso de regreso | hora | `23:00` |  |
| `return_notice_fixed_days_before` | Días antes de la hora fija del aviso de regreso | entero | `1` | 0–7 |
| `return_notice_fallback` | Si la hora fija del aviso de regreso no sirve | opción | `default` | default = Avisar 1 hora antes<br>none = No avisar |
| `return_notice_template` | Texto del aviso de regreso | texto | ver 6.4 | 1–500 caracteres |
| `stop_notice_scope` | Avisos de paso por paradas | opción | `previous` | all = Todas las anteriores<br>none = Ninguna<br>previous = Solo la anterior a la mía |
| `stop_notice_after_boarding` | Seguir avisando después de subir | sí/no | no |  |
| `stop_notice_template` | Texto del aviso de paso por parada | texto | ver 6.4 | 1–500 caracteres |
| `change_notice_template` | Texto del aviso de cambio | texto | ver 6.4 | 1–500 caracteres |
| `cancel_notice_template` | Texto del aviso de cancelación | texto | ver 6.4 | 1–500 caracteres |
| `notify_during_absence` | Recibir avisos de viaje durante una ausencia | sí/no | no |  |
| `saturation_notice_enabled` | Avisos de saturación del transporte | sí/no | sí |  |
| `saturation_notice_level` | Avisar cuando el transporte esté | opción | `overloaded` | overloaded = Sobresaturado (no caben)<br>saturated = Saturado (van de pie) o sobresaturado |
| `saturation_notice_scope` | Avisos de saturación de | opción | `managed` | managed = Los viajes que gestiono (mi itinerario o mi Entidad)<br>own = Mis viajes |
| `saturation_notice_when` | Cuándo avisar de la saturación | opción | `change` | before = Antes de la salida<br>both = Las dos<br>change = Cuando cambia |
| `saturation_notice_minutes_before` | Minutos antes de la salida para el aviso de saturación | entero | `120` | 0–1440 |
| `trip_view` | Vista del recorrido | opción | `timeline` | map = Mapa<br>timeline = Línea con hitos |
| `tts_enabled` | Voz durante el recorrido | sí/no | sí |  |
| `share_location` | Compartir ubicación como sensor | sí/no | no |  |
| `location_interval_seconds` | Frecuencia de envío de ubicación (s) | entero | `10` | —–600, mínimo: `min_location_interval_seconds` |
| `background_sync_enabled` | Sincronización en segundo plano | sí/no | sí |  |
| `trips_poll_foreground_seconds` | Viajes: consulta con la app abierta (s) | entero | `60` | —–3600, mínimo: `min_foreground_poll_seconds` |
| `trips_poll_background_minutes` | Viajes: consulta en segundo plano (min) | entero | `30` | —–1440, mínimo: `min_background_poll_minutes` |
| `tracking_poll_foreground_seconds` | Recorrido: consulta con la app abierta (s) | entero | `10` | —–600, mínimo: `min_foreground_poll_seconds` |
| `tracking_poll_background_seconds` | Recorrido: consulta en segundo plano (s) | entero | `60` | —–3600, mínimo: `min_in_trip_background_poll_seconds` |
| `trip_chat_poll_foreground_seconds` | Chat del viaje: consulta con la app abierta (s) | entero | `5` | —–600, mínimo: `min_foreground_poll_seconds` |
| `trip_chat_poll_background_minutes` | Chat del viaje: consulta en segundo plano (min) | entero | `30` | —–1440, mínimo: `min_background_poll_minutes` |
| `conversations_poll_foreground_seconds` | Conversaciones: consulta con la app abierta (s) | entero | `10` | —–600, mínimo: `min_foreground_poll_seconds` |
| `conversations_poll_background_minutes` | Conversaciones: consulta en segundo plano (min) | entero | `30` | —–1440, mínimo: `min_background_poll_minutes` |
| `notices_poll_foreground_seconds` | Solicitudes y avisos: consulta con la app abierta (s) | entero | `60` | —–3600, mínimo: `min_foreground_poll_seconds` |
| `notices_poll_background_minutes` | Solicitudes y avisos: consulta en segundo plano (min) | entero | `30` | —–1440, mínimo: `min_background_poll_minutes` |

## 6.4 Textos de aviso por defecto

| Aviso | Texto |
|---|---|
| Salida | `Salida {fecha_salida} a las {hora_salida} desde {punto_salida}. {tipo} {matricula}, chofer {chofer}, capacidad {capacidad}. Regreso {fecha_regreso} a las {hora_regreso} desde {punto_regreso}.` |
| Regreso | `Regreso {fecha_regreso} a las {hora_regreso} desde {punto_regreso}. {tipo} {matricula}, chofer {chofer}, capacidad {capacidad}.` |
| Paso por parada | `El transporte pasó por {parada} a las {hora}. Faltan {paradas_restantes} paradas para la tuya.` |
| Cambio | `Cambió tu viaje de {itinerario} del {fecha_salida}: {cambios}.` |
| Cancelación | `Se canceló tu viaje de {itinerario} del {fecha_salida}.` |

Las variables disponibles están en [02-procesos.md §2.7](02-procesos.md#27-notificaciones).
