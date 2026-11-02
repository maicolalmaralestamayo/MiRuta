# 5. App móvil (Flutter, Android)

La app se llama **MiRuta** en todas partes (lanzador, textos, avisos y APK). Interfaz en **español**, con **trato de usted** en todos los textos (sin exagerar: las etiquetas de los campos dicen el dato a secas, "Nombre", "Teléfono"; el usted va en las frases). Las opciones de menú solo aparecen si el rol del usuario las permite. Los acuerdos de detalle de cada pantalla están en [09-repaso-pantallas.md](09-repaso-pantallas.md).

## 5.1 Arquitectura

| Aspecto | Decisión |
|---|---|
| Estructura | Por funcionalidad (`lib/features/<funcionalidad>/{data,domain,presentation}`) |
| Cliente HTTP | `dio`, con un interceptor que añade el JWT y renueva el token automáticamente al recibir 401 |
| JSON:API | Parser propio para `data`, `included`, `relationships` y `errors` |
| Almacenamiento seguro | `flutter_secure_storage`: token de renovación, último usuario y cuándo se escribió la contraseña por última vez. **Nunca la contraseña** |
| Base local | `sqflite`: copia de los viajes para comparar cambios y trabajar sin conexión |
| Tareas en segundo plano | `workmanager` (sincronización y comprobación de actualizaciones) y servicio en primer plano para compartir ubicación |
| Notificaciones | `flutter_local_notifications` |
| Mapa | `flutter_map` con las imágenes del **servidor de mapas propio** (`GET /map`, `tools/maps`). La vista no sale de Cuba; cada imagen vista se guarda en el teléfono y se puede descargar la zona de la Entidad para usarla sin conexión. La app no crece: no lleva mapas dentro |
| Ubicación | `geolocator` |
| QR | `qr_flutter` (mostrar) y `mobile_scanner` (escanear) |
| Voz | `flutter_tts` |
| Recordar contraseña | Sustituye al PIN propio de la app, que **se eliminó**. No se guarda la contraseña: se mantiene la sesión `remember_password_days` días (7 por defecto, con el máximo que fija el Administrador); pasado ese plazo, o si el ajuste está desactivado, se pide la contraseña al abrir la app (ver [07-algoritmos.md §7.32](07-algoritmos.md#732-recordar-contraseña-app)) |
| Servidor | La dirección **no se pide al abrir la app**: puede venir puesta al compilar (`./build_release.sh <dirección>`, opcional) y el usuario la indica en la pantalla **Servidor**, con un **selector de protocolo** (`https` por defecto o `http`). Se guarda en el teléfono. Si el servidor redirige de `http` a `https`, se guarda la dirección `https` |
| Certificados | `network_security_config`: confía en los certificados **del sistema y del usuario** (opción A del repaso), para servidores con certificados propios. Admite `http` (`usesCleartextTraffic`) |
| Ícono | El del inicio de sesión se dibuja con las mismas formas y colores que el ícono adaptable de Android (`AppIcon`), así siempre coinciden |
| Instalación | `device_info_plus`: modelo del teléfono y tipos de procesador admitidos. La instalación se registra en el servidor la primera vez que hace falta (cabecera `X-Installation`) |
| Actualizaciones | `ota_update` (descarga con verificación SHA-256 e instalación), `package_info_plus`, `file_picker` (publicar los APK), `connectivity_plus` (solo con Wi-Fi), `share_plus` (compartir la app). Comprobación periódica en segundo plano cada `update_check_hours` horas |
| Gráficos | `fl_chart` (las estadísticas no se exportan) |
| Indicador de carga | Componentes comunes (`BusyButton`, `BusyIconButton`, `BusyListTile`, `BusySwitchListTile`): mientras se espera al servidor, el control que lanzó la acción muestra el indicador y queda desactivado |

### Reglas comunes de la interfaz

| Regla | Detalle |
|---|---|
| Campos | Vacío, el campo dice el dato que pide; al tocarlo, el nombre sube al borde y dentro aparece un ejemplo. Sin ayudas fijas debajo: solo el error en rojo si incumple sus reglas (validación por campo, cuando se ha tocado). Al pulsar el botón principal se marcan los obligatorios vacíos |
| Contraseñas | La contraseña y su repetición llevan las dos el ojo para verla |
| Teléfono | Viene relleno con `+53 ` (editable) |
| Fechas | Con el día de la semana y el año de 2 dígitos: "sáb. 31/10/26 13:51". Los controles de fecha tienen el mismo aspecto que los demás campos, con ícono de calendario que abre el almanaque |
| Viajes | "Viaje de ida" / "Viaje de regreso" en lugar de "Salida" / "Regreso" en todas las interfaces |
| Botones | Ícono + texto con acción y objeto ("Guardar vehículo", "Crear viaje") |
| Eliminar | Ícono de cesto de basura en rojo, siempre con confirmación |
| Estados | Lista desplegable (p. ej. Estado: Activada / Desactivada), no botones ni íconos |
| Foto de perfil | Si no hay foto, ícono genérico de persona (no iniciales) |
| Jerarquía | Ícono de estrella en toda la app |
| Plurales | Corregidos ("1 asiento", "1 niño", "1 trabajador esperado") |
| Hablar con el desarrollador | Botón tonal, igual en todas las pantallas donde aparece, al final |

## 5.2 Pantallas comunes

| Pantalla | Contenido |
|---|---|
| **Inicio de sesión** | Ícono, usuario (recordado en el teléfono) y contraseña. Debajo, en una línea y del mismo tamaño: **Entrar** (azul) y **Olvidé algo** (naranja). Separador; **Registrarme por primera vez** y **Me registró un superior** (tonales, uno debajo del otro). Separador; **botón de servidor** de tres estados: "Indicar servidor" (naranja, sin dirección), "Conectado al servidor" (verde) o "Desconectado del servidor" (rojo); se comprueba al abrir y al volver de Servidor. Al final, **Hablar con el desarrollador** y, al pie, versión · arquitectura |
| **Servidor** | "Elija el protocolo de conexión e indique la dirección del servidor que le facilitó el administrador de la aplicación." Selector de protocolo (`https`/`http`) y dirección en la misma línea; si se pega una URL completa, el selector toma su protocolo. La app añade `/api/v1`, comprueba que responde MiRuta y la guarda. Si falla: "Fue imposible conectarse al servidor. Revise el protocolo de conexión que seleccionó, la dirección del servidor que indicó y asegúrese de tener conexión a Internet." Si la dirección cambia, la instalación se vuelve a registrar |
| **Registrarme por primera vez** | Primer nombre, segundo nombre (opcional), apellidos, nombre de usuario, contraseña y "Repita la contraseña". Botón **Registrarme** |
| **Otros datos del registro** | Entidad (abreviatura; la app muestra su nombre para confirmar), Pase, sexo (Masculino por defecto) y jerarquía. Obligatoria salvo para el Administrador |
| **Me registró un superior** | Entidad, Pase, código de activación, nombre de usuario, contraseña y su repetición |
| **Olvidé algo** | Arriba, "El Administrador comprobará sus datos…"; después, qué olvidó (usuario, contraseña o los dos), Entidad, Pase y teléfono. Luego muestra el estado; al aprobarse, el usuario o la contraseña nueva |
| **Hablar con el desarrollador (sin cuenta)** | Nombre y apellidos, teléfono, motivo y mensaje; las respuestas llegan a ese teléfono |
| **Contraseña nueva obligatoria** | Cuando caduca la contraseña (pide también la actual) o tras recuperar el acceso |
| **Contraseña** (al abrir) | Si "Recordar contraseña" está desactivado o pasaron sus días, se pide la contraseña del usuario de la sesión. Sustituye a la antigua pantalla de PIN |
| **Actualización** | Al abrir la app y periódicamente se comprueba si hay una versión nueva (notificación). Si es obligatoria, no se puede seguir sin instalarla |
| **Inicio** | Tarjeta del itinerario (Itinerario / Parada / Dirección). Tarjetas de viajes con el estado del recorrido: "Viaje de ida" o "Viaje de regreso" mientras está en curso, "Ida completada" / "Regreso completado" al terminar, y "Atrasado" si no comenzó a su hora. Estado de las solicitudes y avisos sin leer |
| **Viajes** | Viajes confirmados de su itinerario con la etiqueta del recorrido y el estado de cada tramo; indicador de cambios |
| **Detalle del viaje** | Viaje de ida y viaje de regreso (fecha, hora y punto de salida de cada uno), vehículo (matrícula `B 123 456`, "Cap. total · Cap. sentados · Cap. de pie"), chofer, atraso, chat del viaje, **"Ya subí"**, **"Mi QR"**, **"Seguir recorrido"** |
| **Recorrido en tiempo real** | Título "Viaje de ida · X" / "Viaje de regreso · X". Cabecera con paradas pasadas, **paradas donde no se detuvo y saltadas**, atraso y sensores activos. **Línea con hitos** (línea centrada del mismo alto siempre, paradas como puntos gruesos encima, distancias proporcionales, hora de paso y km junto al nombre) o **mapa** (recorrido de referencia, si existe, y trazado real; nunca líneas rectas entre paradas). Botón **Trabajadores** |
| **Trabajadores del viaje** | Selector Viaje de ida / Viaje de regreso; por parada y alfabéticamente, con foto (o ícono de persona), estrella de jerarquía y niños; sin número de posición |
| **Mi código QR** | Pestañas con colores legibles sobre la barra azul marino; se mantienen los textos de ayuda |
| **Mi perfil** | Foto, nombre (se edita tocándolo), usuario, Entidad, Pase, jerarquía, contraseña ("caduca el <día> dd/mm/aa"), itinerario y parada, roles, hijos. Sin lápices ni textos de ayuda: tocar un dato editable lo edita. Ya no tiene "Darme de baja del itinerario" |
| **Mis hijos** | "Pepito Pérez García" / "Fecha Nac.: sáb. 16/07/92" / "Derecho a viajar: sáb. 14/03/26" |
| **Solicitudes** | Historial de las propias, con "Aprobada <fecha> por X" o "Rechazada <fecha> por X". **Nueva:** "Itinerario y parada", "Darme de baja del itinerario" (inmediata, con confirmación), "Rol de Jefe de itinerario", "Rol de Jefe de Transporte", "Rol de Chofer", "Declarar hijos" (varios en una misma solicitud, con la nota para parejas) y "Ausencia temporal" (con la opción **"Ausencia indefinida"**; después se le ponen fechas o se quita). Cancelar las pendientes |
| **Bajas de roles** | Darse de baja como Jefe de itinerario, como chofer o como Jefe de Transporte, con confirmación |
| **Conversaciones** | Con los Jefes de mi itinerario, con los Jefes de Transporte de mi Entidad y con el desarrollador. Al abrir una se elige el motivo |
| **Avisos** | Avisos del servidor con su texto concreto (`message`): "Se aprobó su solicitud de <tipo> (<detalle>). La aprobó <nombre>", "Se rechazó … Motivo: <motivo>", comienzo y atraso de viajes, caducidad de la contraseña, incidencias del recorrido (jefes) |
| **Estadísticas** | Las que le corresponden por su rol. Periodo "Últimos" o "Rango de fechas" (un día = inicio y fin iguales). Gráfico con eje en enteros y título que dice qué se mide, más tabla. No se exportan |
| **Más** | Compartir la app (sin texto de ayuda; 64 bits por defecto o 32 bits). Al pie, "MiRuta · Versión x · 64 bits" |
| **Ajustes** | Ver 5.4 |

## 5.3 Pantallas por rol

### Chofer

- **Mis viajes como chofer:** viajes asignados, con fecha, itinerario, vehículo y trabajadores esperados.
- **Detalle y recorrido:** "Iniciar viaje de ida" / "Iniciar viaje de regreso", "Finalizar", voz, lista de la próxima parada, "Trabajadores por parada", escanear QR, marcar subidas a mano, marcar el viaje como realizado. El estado se muestra solo con la etiqueta, sin duplicarlo.

### Jefe de itinerario (en sus itinerarios)

- **Solicitudes por resolver:** pertenencia (viendo el Pase de quien la pide), hijos (**cada hijo se aprueba o rechaza por separado**, con aviso de posible duplicado) y ausencias. **Al rechazar, el motivo es obligatorio.**
- **Miembros del itinerario:** asignar o quitar itinerario y parada, y **registrar trabajadores sin teléfono** (con su código de activación, también como QR).
- **Planificación de viajes** de su itinerario.
- **Viajes del itinerario:** con la ocupación en color (naranja si van de pie, rojo si no caben) y el atraso.
- **Recorrido de referencia:** en la ficha de su itinerario, marca un viaje de ida y otro de regreso ya realizados como trazado habitual.
- **Avisos de incidencias:** paradas donde no se detuvo, saltadas y desvíos de los viajes de su itinerario.
- **Recorrido:** igual que el chofer.
- **Conversaciones recibidas,** agrupadas por motivo.

### Jefe de Transporte

Además de todo lo del Jefe de itinerario, en cualquier itinerario de **su Entidad**:

- **Vehículos y choferes:** ficha con matrícula (se escribe junta, `B123456`; se muestra `B 123 456`), "Capacidad sentados", "Capacidad de pie" y "Capacidad total" de solo lectura; tarjeta "Cap. total 60 • Cap. sentados 45 • Cap. de pie 15"; chofer habitual.
- **Itinerarios y paradas** (una sola gestión): alta y edición; desde la ficha del itinerario se añaden paradas existentes o se crean nuevas con el mapa, se ordenan arrastrando y se marca el recorrido de referencia.
- **Planificación de viajes:**
  - **Calendario y lista** de viajes, con filtros por itinerario, vehículo, chofer, estado y fechas.
  - **Nuevo viaje:** itinerarios (selección múltiple), días marcados en un almanaque, hora del viaje de ida y del de regreso, y una fila por itinerario con su vehículo y su chofer (los habituales por defecto; solapes o faltantes señalados). Resumen "Se crearán N viajes".
  - **Selección múltiple** para confirmar, desconfirmar o cancelar.
  - **Avisos** de saturación, atrasos, incidencias y viajes **para reasignar**.
- **Solicitudes por resolver:** Jefe de itinerario y chofer.
- **Trabajadores:** ficha con cada dato en su control (Nombre, Entidad, Pase, Sexo, Jerarquía…), debajo itinerario y roles; registrar sin teléfono, regenerar códigos, hacer o quitar chofer y Jefe de itinerario, asignar itinerario y parada.
- **Ajustes de la Entidad**, incluidos la tolerancia de atraso, los umbrales de paradas no realizadas y desvíos, y los valores por defecto de los ajustes de cada usuario.

### Administrador

Todo lo anterior y, además:

- **Selector de Entidad** en Gestión: con qué Entidad trabaja (o todas).
- **Entidades:** crear y editar; el estado (Activada/Desactivada) es una lista en la ficha; la lista se filtra con "Activadas / Desactivadas / Todas".
- **Solicitudes por resolver** de Jefe de Transporte; hacer o quitar Jefe de Transporte.
- **Olvidé algo:** Entidad, Pase y teléfono en controles de solo lectura; ver con quién coinciden los datos, llamar, abrir el chat de WhatsApp con ese número, aprobar, rechazar y bloquear el teléfono. Estado "Solicitada".
- **Trabajadores:** buscar, ver datos privados, activar y desactivar.
- **Nomencladores:** jerarquías (con su icono y orden), tipos de vehículo, tipos de ausencia y motivos de conversación. (Las palabras no admitidas en los usuarios se eliminaron.)
- **Ajustes de la app** (caducidades, contraseñas, máximo de días para recordar la contraseña, letras de matrícula, dirección de las imágenes del mapa, límites, mínimos de frecuencia) y los de cualquier Entidad.
- **Actualizaciones de la app:** publicar los APK (64 bits, 32 bits y "APK universal"); la versión y el código se leen del APK y se muestran de solo lectura; novedades; "Obligatoria/Opcional" como lista. Ver cuántas cuentas tienen cada versión y retirar versiones.
- **Mantenimiento del servidor:** estado del servidor (PHP, base de datos, carpetas, tareas programadas) y órdenes: instalar o actualizar la base de datos, ejecutar las tareas pendientes, limpiar la caché y ver el registro de errores (docs/02-procesos.md §2.15). Sin sesión, desde la pantalla *Servidor* con la clave de mantenimiento.
- **Conversaciones con el desarrollador**, también las de quien aún no tiene cuenta (marcadas "sin cuenta"); cerrarlas.

## 5.4 Ajustes del usuario

Cada ajuste lleva debajo una explicación breve de **una línea** (excepción a la regla de no poner ayudas). Los valores por defecto y los límites están en [06-ajustes.md](06-ajustes.md).

| Grupo | Ajustes |
|---|---|
| **Aviso de viaje de ida** | Forma (tiempo antes u hora fija), minutos antes, hora fija, días antes, qué hacer si la hora fija ya pasó, texto |
| **Aviso de viaje de regreso** | Igual que el de ida |
| **Avisos de paso por paradas** | Alcance (ninguna, la anterior o todas las anteriores), seguir después de subir, texto |
| **Avisos de cambios y cancelaciones** | Texto |
| **Comienzo y atrasos** | Aviso de comienzo del viaje; aviso de viaje atrasado |
| **Saturación del transporte** | Recibirlos, nivel (solo sobresaturado o también saturado), de qué viajes (los míos o los que gestiono), cuándo (al cambiar, antes de la salida o las dos) y minutos antes |
| **Mensajes** | Avisos de mensajes nuevos en el chat del viaje y en las conversaciones |
| **Ausencias** | Recibir avisos de viaje durante una ausencia |
| **Seguridad** | Recordar contraseña y días para recordarla; días de aviso antes de que caduque la contraseña; recordar el usuario (solo en el teléfono) |
| **Recorrido** | Vista (mapa o línea con hitos), voz (según rol), compartir ubicación, frecuencia de envío |
| **Frecuencias** | Para cada funcionalidad, con la app abierta y en segundo plano: viajes, recorrido, chat del viaje, conversaciones, solicitudes y avisos. Activar o desactivar la sincronización en segundo plano |
| **Actualizaciones** | Cada cuántas horas comprobar si hay versión nueva; descargar solo con Wi-Fi (solo en el teléfono, desactivado por defecto); buscar ahora |
| **Mapa sin conexión** (solo en el teléfono) | Descargar la zona de la Entidad (sus paradas con unos 2 km de margen), respetando "solo con Wi-Fi"; fecha de la última descarga |

Cada ajuste vale lo que elija el usuario; si no eligió nada, lo que fije su Entidad; y si tampoco, el valor de la app.
