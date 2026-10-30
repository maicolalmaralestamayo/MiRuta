# 6. Ajustes

Todos los ajustes están en `setting_definitions` con su tipo, su valor por defecto y sus límites.

- **Valor global:** si existe, está en `settings`.
- **Valor del usuario:** si existe, está en `user_settings`.
- **Valor efectivo** = valor del usuario → si no hay, valor global → si no hay, valor por defecto.

**Columnas de las tablas:**
- **Editable por:** quién cambia el valor global. El Administrador siempre puede.
- **Usuario:** si cada usuario puede personalizarlo.

## 6.1 Ajustes globales

| Clave | Descripción | Tipo | Defecto | Límites | Editable por |
|---|---|---|---|---|---|
| `child_max_age` | Edad hasta la que un hijo tiene derecho a viajar (hasta el 31 de agosto siguiente) | entero | 16 | 0–25 | Jefe de Transporte |
| `inactivity_days` | Días sin viajar para la baja automática del itinerario | entero | 30 | 1–365 | Jefe de Transporte |
| `inactivity_warning_days` | Días de antelación del aviso de baja por inactividad | entero | 5 | 0–30 | Jefe de Transporte |
| `conversation_retention_days` | Días tras el último mensaje en que se borra una conversación | entero | 30 | 1–365 | Administrador |
| `trip_auto_complete_delay_minutes` | Minutos después del regreso en que el servidor marca el viaje como realizado | entero | 0 | 0–1440 | Administrador |
| `stop_detection_radius_m` | Radio para detectar el paso por una parada | entero | 100 | 20–1000 | Administrador |
| `sensor_outlier_distance_m` | Distancia a partir de la cual se descarta un sensor | entero | 300 | 50–5000 | Administrador |
| `sensor_stale_seconds` | Segundos sin enviar tras los que un sensor deja de contar como activo | entero | 60 | 10–600 | Administrador |
| `boarding_pass_ttl_seconds` | Validez del token del QR de subida | entero | 120 | 30–3600 | Administrador |
| `access_token_ttl_minutes` | Validez del token de acceso | entero | 30 | 5–240 | Administrador |
| `refresh_token_ttl_days` | Validez del token de renovación | entero | 90 | 1–365 | Administrador |
| `photo_max_kb` | Tamaño máximo de la foto de perfil | entero | 2048 | 100–10240 | Administrador |
| `rank_icon_max_kb` | Tamaño máximo del icono de jerarquía | entero | 512 | 50–2048 | Administrador |
| `message_max_length` | Longitud máxima de un mensaje de chat | entero | 1000 | 50–5000 | Administrador |
| `min_foreground_poll_seconds` | Frecuencia mínima de consulta con la app abierta | entero | 5 | 1–60 | Administrador |
| `min_background_poll_minutes` | Frecuencia mínima de sincronización en segundo plano | entero | 30 | 15–1440 | Administrador |
| `min_location_interval_seconds` | Frecuencia mínima de envío de ubicación | entero | 5 | 1–60 | Administrador |
| `min_in_trip_background_poll_seconds` | Frecuencia mínima de consulta en segundo plano **durante un recorrido** | entero | 30 | 10–600 | Administrador |

## 6.2 Ajustes del usuario

Todos son personalizables por el usuario. Su valor global por defecto lo puede cambiar el Administrador.

### Avisos de salida y regreso

Existen dos juegos idénticos, uno con prefijo `departure_` y otro con `return_`:

| Clave | Descripción | Tipo | Defecto | Límites u opciones |
|---|---|---|---|---|
| `*_notice_mode` | Forma del aviso | opción | `relative` | `relative` (tiempo antes), `fixed` (hora fija) |
| `*_notice_minutes_before` | Minutos antes | entero | 60 | 0–1440 |
| `*_notice_fixed_time` | Hora fija | hora | 14:00 (salida), 23:00 (regreso) | — |
| `*_notice_fixed_days_before` | Días antes de la hora fija (0 = el mismo día) | entero | 0 (salida), 1 (regreso) | 0–7 |
| `*_notice_fallback` | Si la hora fija cae después del viaje | opción | `default` | `default` (avisar 1 h antes), `none` (no avisar) |
| `*_notice_template` | Texto del aviso | texto | Ver 6.3 | Hasta 500 caracteres |

### Otros avisos

| Clave | Descripción | Tipo | Defecto | Límites u opciones |
|---|---|---|---|---|
| `stop_notice_scope` | Avisos de paso por paradas | opción | `previous` | `none`, `previous` (solo la anterior), `all` (todas las anteriores) |
| `stop_notice_after_boarding` | Seguir avisando después de subir | booleano | falso | — |
| `stop_notice_template` | Texto del aviso de paso por parada | texto | Ver 6.3 | Hasta 500 caracteres |
| `change_notice_template` | Texto del aviso de cambio | texto | Ver 6.3 | Hasta 500 caracteres |
| `cancel_notice_template` | Texto del aviso de cancelación | texto | Ver 6.3 | Hasta 500 caracteres |
| `notify_during_absence` | Recibir avisos de viaje durante una ausencia | booleano | falso | — |

### Recorrido

| Clave | Descripción | Tipo | Defecto | Límites u opciones |
|---|---|---|---|---|
| `trip_view` | Vista del recorrido | opción | `timeline` | `map`, `timeline` |
| `tts_enabled` | Voz durante el recorrido (solo chofer y jefes) | booleano | verdadero | — |
| `share_location` | Compartir ubicación como sensor | booleano | falso (verdadero para el chofer) | — |
| `location_interval_seconds` | Frecuencia de envío de ubicación | entero | 10 | ≥ `min_location_interval_seconds` |

### Frecuencias de consulta

| Clave | Descripción | Tipo | Defecto | Límites |
|---|---|---|---|---|
| `background_sync_enabled` | Sincronización en segundo plano | booleano | verdadero | — |
| `trips_poll_foreground_seconds` | Viajes, con la app abierta | entero | 60 | ≥ mínimo global |
| `trips_poll_background_minutes` | Viajes, en segundo plano | entero | 30 | ≥ mínimo global |
| `tracking_poll_foreground_seconds` | Recorrido, con la app abierta | entero | 10 | ≥ mínimo global |
| `tracking_poll_background_seconds` | Recorrido, en segundo plano (solo durante un recorrido) | entero | 60 | ≥ mínimo global |
| `trip_chat_poll_foreground_seconds` | Chat del viaje, con la app abierta | entero | 5 | ≥ mínimo global |
| `trip_chat_poll_background_minutes` | Chat del viaje, en segundo plano | entero | 30 | ≥ mínimo global |
| `conversations_poll_foreground_seconds` | Conversaciones, con la app abierta | entero | 10 | ≥ mínimo global |
| `conversations_poll_background_minutes` | Conversaciones, en segundo plano | entero | 30 | ≥ mínimo global |
| `notices_poll_foreground_seconds` | Solicitudes y avisos, con la app abierta | entero | 60 | ≥ mínimo global |
| `notices_poll_background_minutes` | Solicitudes y avisos, en segundo plano | entero | 30 | ≥ mínimo global |

## 6.3 Textos de aviso por defecto

| Aviso | Texto |
|---|---|
| Salida | `Salida {fecha_salida} a las {hora_salida} desde {punto_salida}. {tipo} {matricula}, chofer {chofer}, capacidad {capacidad}. Regreso {fecha_regreso} a las {hora_regreso} desde {punto_regreso}.` |
| Regreso | `Regreso {fecha_regreso} a las {hora_regreso} desde {punto_regreso}. {tipo} {matricula}, chofer {chofer}, capacidad {capacidad}.` |
| Paso por parada | `El transporte pasó por {parada} a las {hora}. Faltan {paradas_restantes} paradas para la tuya.` |
| Cambio | `Cambió tu viaje de {itinerario} del {fecha_salida}: {cambios}.` |
| Cancelación | `Se canceló tu viaje de {itinerario} del {fecha_salida}.` |

Las variables disponibles están en [02-procesos.md §2.7](02-procesos.md#27-notificaciones).
