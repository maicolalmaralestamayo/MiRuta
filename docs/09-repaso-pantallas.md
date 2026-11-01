# 9. Repaso de pantallas (versión 2.1)

Acuerdos del repaso de las pantallas de la app, una a una, con el Product Owner. Prevalecen sobre los documentos anteriores donde los contradigan. La numeración de las secciones es la de las pantallas revisadas.

## Generales
- Nombre de la app: MiRuta en todas partes (lanzador, textos, avisos, APK).
- Versión y arquitectura visibles en el inicio de sesión (pie) y en una sección de la app.
- Trato de usted en todos los textos.
- Textos de ayuda de los campos: solo cuando el campo se ha tocado e incumple sus reglas (validación por campo). Al pulsar el botón principal se marcan los obligatorios vacíos.
- "Hablar con el desarrollador": botón tonal (color de los de registro), igual en todas las pantallas, al final.
- Segundo nombre opcional (cuentas e hijos) — también en la API.
- Campos de contraseña y su repetición: ambos con el ojo para ver.
- Certificados: opción A (network_security_config con certificados del sistema y del usuario) + al seguir una redirección http→https guardar la dirección https.
- Corregir plurales (1 asientos, 1 plazas, 1 pasadas, 1 niños, 1 trabajadores esperados).
- Quitar suposiciones de lugar: ejemplo de teléfono "+53…" y coordenadas de los datos de prueba (tools/fixtures).

## 1 · Inicio de sesión
- Grupo 1 (debajo de usuario/contraseña), misma línea, mismo tamaño: [Entrar (ícono login, azul)] [Olvidé algo (ícono advertencia, naranja énfasis)].
- Separador. Registrarme por primera vez / Me registró un superior (uno debajo del otro, tonales, con ícono).
- Separador. Botón de servidor: "Indicar servidor" (naranja) si no hay dirección; "Conectado al servidor" (verde) si responde; "Desconectado del servidor" (rojo) si no. Comprobar al abrir y al volver de Servidor.
- Hablar con el desarrollador al final. Debajo, versión · arquitectura.
- Títulos de destino: "Olvidé algo", "Me registró un superior", "Registrarme por primera vez".

## 2 · Servidor
- Texto: "Elija el protocolo de conexión e indique la dirección del servidor que le facilitó el administrador de la aplicación."
- Selector de protocolo (https por defecto / http) y dirección en la misma línea. Sin prueba automática de protocolos. Si se pega una URL completa, el selector toma su protocolo.
- Error: "Fue imposible conectarse al servidor. Revise el protocolo de conexión que seleccionó, la dirección del servidor que indicó y asegúrese de tener conexión a Internet."

## 3 · Registrarme por primera vez
- Título "Registrarme por primera vez"; "Nombre de usuario"; segundo nombre opcional; botón "Registrarme"; sin ayudas permanentes; ojo también en "Repita la contraseña".

## 4 · Otros datos del registro (paso 2)
- Título "Otros datos del registro"; sin saludo ni "Para usar la app…"; campo "Entidad" sin ayuda; sexo Masculino por defecto.
- Segundo nombre de los hijos también opcional.

## 5 · Me registró un superior
- Título "Me registró un superior". Campos iguales a los ya revisados (Entidad sin ayuda, Pase, Código de activación, Nombre de usuario, Contraseña y Repita con ojo, sin ayudas permanentes). Texto superior en usted.

## Regla general de campos
- Vacío: el placeholder dice el dato que pide (labelText). Al tocarlo: el nombre sube al borde y dentro aparece un ejemplo (hintText). Sin ayudas fijas debajo; solo error en rojo si incumple.

## 6 · Olvidé algo
- Título "Olvidé algo". Arriba el texto "El Administrador comprobará sus datos…", luego separador, luego el resto.
- Campos de teléfono (todas las pantallas): vienen rellenos con "+53 " por defecto (editable).

## 7 · Hablar con el desarrollador (sin cuenta)
- Trato de usted; regla general de campos; teléfono con +53 por defecto.
- Usted sin exagerar: etiquetas de campo con el dato a secas ("Nombre", "Teléfono"); usted solo en frases.
- Escribir al desarrollador: campo "Nombre y apellidos".

## 8 · Inicio
- Tarjeta del itinerario con etiquetas: Itinerario / Parada / Dirección.
- Tarjetas de viajes con el estado del recorrido: mientras la salida está en curso, etiqueta "Viaje de ida"; mientras el regreso, "Viaje de regreso"; tramo terminado: "Ida completada" / "Regreso completado".

## Funcionalidad nueva: paradas no realizadas y desvíos
- No paró: (a) pasó de largo — entró en el radio sin detenerse (menos de N s o sin bajar de V km/h); (b) se la saltó — llegó a la siguiente sin pasar por esta.
- Desvío: opción B — el Jefe de itinerario marca un viaje realizado como "recorrido de referencia"; se avisa si otro se aleja de ese trazado más de X m.
- Avisos: Jefe de itinerario y Jefe de Transporte; queda registrado en el viaje para estadísticas. Umbrales en ajustes de la Entidad con valores por defecto. A los pasajeros no se les avisa.
- Fechas de viajes en toda la app con el día de la semana (p. ej. "sáb. 31/10/2026 13:51").
- Matrícula: nomenclatura cubana (una letra y 6 dígitos).
- Quitar en toda la app la aclaración "van cargados / no ocupan plaza" de los niños.

## 9 · Viajes
- Tarjetas con etiqueta de recorrido y estado de cada tramo.
- Matrícula: se escribe junta (B123456) y se muestra con los dígitos separados (B 123 456). Letras permitidas en un ajuste de la app (lo edita el Administrador).
- En todas las interfaces de viajes: sustituir "Salida"/"Regreso" por "Viaje de ida"/"Viaje de regreso" (fecha, hora y lugar = punto de salida de cada tramo).

## 10 · Detalle del viaje
- "Viaje de ida" / "Viaje de regreso" en lugar de Salida/Regreso.

## 11 · Solicitudes
- "Resuelta" → "Aprobada <fecha> por X" (y "Rechazada <fecha> por X" si se rechaza). Fechas con día de la semana.
- Menú de nueva solicitud: "Rol de Jefe de itinerario", "Rol de Jefe de Transporte", "Rol de Chofer"; "Declarar hijos": varios hijos en una misma solicitud; el jefe aprueba o rechaza cada hijo por separado.

## 13 · Más
- Quitar el texto de ayuda de "Compartir la app". Versión y arquitectura al pie ("MiRuta · Versión x · 64 bits").
- Ícono de la jerarquía en toda la app: estrella.

## 14 · Mi perfil
- Sin "Cambiar nombres y apellidos" (se edita tocando el nombre). Sin lápices: tocar cualquier dato editable lo edita.
- Sin textos de explicación/ayuda: solo nombre del dato y valor.
- Quitar "Darme de baja del itinerario" del perfil. En Solicitudes → Nueva: "Itinerario y parada" (solicitar) y "Darme de baja del itinerario" (del aprobado; inmediata con confirmación, como hoy).
- Fila Contraseña: muestra "caduca el <día> dd/mm/aaaa".
- Caducidad de la contraseña: notificación diaria durante los últimos N días (hoy es un único aviso a los 15 días). N configurable: valor de la app (15) que cada usuario puede cambiar en sus Ajustes.
- Fechas en toda la app con año de 2 dígitos (sáb. 16/07/92).
- Eliminar en toda la app: ícono de cesto de basura en rojo, y siempre con confirmación.

## 15 · Mis hijos
- Formato: "Pepito Pérez García" / "Fecha Nac.: sáb. 16/07/92" / "Derecho a viajar: sáb. 14/03/26" (el segundo nombre se muestra si lo tiene).

## 16 · Avisos
- Texto concreto: "Se aprobó su solicitud de <tipo> (<detalle>) por <nombre>". Si se rechazó: "Se rechazó … por <nombre>. Motivo: <motivo>" (motivo obligatorio al rechazar).

## 17 · Ajustes del usuario
- Excepción a la regla de ayudas: cada ajuste lleva una explicación breve de UNA línea.
- Secciones "Aviso de viaje de ida" / "Aviso de viaje de regreso".
- Eliminar el PIN de la app por completo.
- Nuevo: "Recordar contraseña" + "Días para recordar la contraseña" (N). Propuesta técnica: no guardar la contraseña; mantener la sesión N días; pasado N (o si está desactivado, cada vez que se abre la app) se pide la contraseña.
- Recordar contraseña: activado por defecto, 7 días; máximo fijado por el Administrador (p. ej. 30).

## 18 · Estadísticas
- Periodo: "Últimos" y "Rango de fechas" (un día = rango con inicio y fin iguales). Quitar "Fechas" sueltas.
- Eje del gráfico en enteros; títulos que digan qué se mide.

## 19 · Recorrido en tiempo real
- Títulos "Viaje de ida · X" / "Viaje de regreso · X".
- Línea con hitos: línea centrada en la pantalla; paradas como puntos gruesos ENCIMA de la línea; distancias proporcionales pero la línea ocupa siempre el mismo alto; hora de paso y km al lado del nombre de la parada.
- Cabecera: añadir paradas donde no paró / que se saltó.
- Botón "Pasajeros" → "Trabajadores".
- Mapa: nada de líneas rectas entre paradas; dibujar el recorrido de referencia (opción B) cuando exista y el trazado real recorrido.

## 20 · Trabajadores del viaje (antes Pasajeros)
- Quitar el número de posición; poner la foto de perfil (si no tiene foto, ícono genérico de persona).
- Selector Viaje de ida / Viaje de regreso; estrella de jerarquía; plurales.

## 23 · Nuevo viaje
- El campo Itinerario es de selección múltiple (sin opción aparte de "repetir por itinerario").
- Fechas: un almanaque (calendario) en el que se marcan uno o varios días; las horas de ida y regreso se aplican a cada día marcado (los campos de ida/regreso pasan a ser solo hora; regreso puede caer al día siguiente).
- Se crean los viajes días × itinerarios. Cada itinerario seleccionado con su fila de vehículo y chofer (habituales por defecto); solapes o faltantes señalados en su fila; resumen "Se crearán N viajes" antes de crear.

## 24 · Vehículos y choferes
- Ficha: "Capacidad sentados" (sin "sin el del chofer"), "Capacidad de pie", y un campo de solo lectura "Capacidad total" (se quita el texto "Capacidad total: N pasajeros").
- Tarjeta del vehículo: "Cap. total 60 • Cap. sentados 45 • Cap. de pie 15".
- 25 Itinerarios: sin cambios adicionales; recorrido de referencia en la ficha.

## Mapas
- La app no debe crecer. El servidor propio guarda los datos de Cuba y genera las imágenes del mapa con estilo sencillo (calles con nombres, edificios, PDI); la app las pide a ese servidor con el componente de mapa actual.
- Vista limitada a Cuba. Las zonas vistas se guardan en el teléfono (sin Internet funcionan).
- Descarga sin conexión de la zona de la Entidad (área de sus itinerarios + margen), cuando el usuario quiera (respetando "solo con Wi-Fi").
- Script en el repositorio para preparar los datos del mapa en el servidor.
- Sin foto de perfil: ícono genérico de persona (en toda la app, en lugar de iniciales).

## 27 · Trabajadores
- Ficha "Trabajador": cada dato en su propio control (Nombre, Entidad, Pase, Sexo, Jerarquía…), debajo Itinerario y Roles.
- "Registrar trabajador": quitar el texto de ayuda.
- Controles de estado en toda la app: lista desplegable (p. ej. Estado: Activada / Desactivada), no botones/íconos.

## 29 · Entidades
- Estado en la ficha como lista (Activada/Desactivada); se quita el botón de desactivar de la fila. Filtro de la lista con lista "Activadas / Desactivadas / Todas" en lugar del ojo.

## 30 · Olvidé algo (Administrador)
- Botón de WhatsApp (abre el chat con ese número) además del de llamar.
- Quitar "Comprueba por tu cuenta…". "Pedida" → "Solicitada".
- Entidad, Pase y Teléfono en controles independientes de solo lectura; quitar esa información de los otros lugares de la tarjeta.
- Todos los botones de la app: ícono + texto con acción y objeto (p. ej. "Guardar vehículo", "Crear viaje").

## 32 · Nomencladores y otros
- Itinerarios y paradas se gestionan juntos (una sola gestión "Itinerarios y paradas"; sin pantalla aparte de Paradas). Propuesta: desde la ficha del itinerario se añaden paradas existentes o se crean nuevas (con mapa), y se editan ahí.
- Eliminar por completo las palabras no permitidas (pantalla, API, tabla, seeder).
- Usuario y contraseña: reglas de formación + palabras reservadas (usuario) + distinta de las 5 anteriores (contraseña). Se quitan: lista de contraseñas comunes y "no contener usuario ni nombres".

## 33 · Actualizaciones de la app
- El servidor lee versión y código del APK subido (se muestran de solo lectura). "APK de Universal" → "APK universal". Obligatoria/Opcional como lista. Sin ayudas.
- Actualizaciones: comprobación periódica en segundo plano con la frecuencia de un ajuste (por defecto cada 24 h; ajustable por el usuario) y notificación cuando hay versión nueva.

## 34 · Detalle del viaje (jefes y chofer)
- Aceptado tal como se propuso: "Iniciar viaje de ida/regreso", "Trabajadores por parada", formato de capacidades, sin duplicar el estado (solo la etiqueta).
- Notificaciones de mensajes nuevos (chat del viaje y conversaciones), activables/desactivables en los Ajustes del usuario.

## 36 · Mi código QR
- Se mantienen los textos de ayuda.
- Defecto corregido: pestañas (TabBar) sobre la barra azul marino casi ilegibles (texto oscuro sobre azul). Corregir colores en el tema.

## Viajes atrasados e inicio de viaje (nuevo)
- Si un tramo no ha comenzado a su hora (+ tolerancia en ajustes de la Entidad), el servidor lo marca "Atrasado"; la app lo muestra en tarjetas, detalle y recorrido.
- Aviso al usuario cuando un viaje se atrasa (configurable) y cuando comienza, atrasado o no (configurable). Ajustes en Ajustes del usuario con valores por defecto.

## 38 · Formularios de solicitud
- Ausencia temporal: opción "Ausencia indefinida" (sin fechas), vigente hasta que el usuario le ponga fechas de inicio y fin o la quite.
- Se mantiene el aviso "Si son pareja y viajan…".
- Controles de fecha en toda la app: mismo aspecto que los demás campos (contorno y etiqueta), con ícono de calendario que abre el almanaque.

## 39 · Solicitudes por resolver
- Corregir colores de pestañas; motivo obligatorio al rechazar; aprobar/rechazar por hijo.
