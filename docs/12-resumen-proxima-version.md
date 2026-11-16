# 12. Resumen de la próxima versión (07/11/2026)

Resumen **consolidado** de lo acordado en `docs/11-acuerdos-registro-qr.md` §11.19–§11.52, con la **última decisión**
de cada tema (lo sustituido no aparece). **Servidor implementado** (Laravel 12; API en `docs/13-api-proxima-version.md`);
**app implementada** (versión 4.4.0, `docs/05-app.md`).

## 1. Plataforma

- **Servidor:** **Laravel 12** con **PHP 8.2.35** (en lugar de Lumen 7). Misma API JSON:API. Pruebas con PHPUnit 11 en
  un contenedor `php:8.2`. Paquete de hospedaje e instrucciones actualizados.
- **Dependencias mínimas:** se quitan los paquetes que no se usen (servidor y app) y se instalan solo los necesarios.
- **Sin mapas** en ningún sitio.

## 2. Roles

- **Tres roles fijos:** **Administrador** (todo, todas las Entidades), **Jefe de itinerario** (su itinerario) y
  **Trabajador** (consulta y lo suyo). Desaparecen los roles configurables, las solicitudes de rol y la pantalla Roles.
- Un itinerario puede tener **varios Jefes**; cada persona es Jefe de **un solo** itinerario y **viaja en él**. Solo el
  Administrador asigna y quita el rol de Jefe.

## 3. Barra principal y pantallas

- Barra: **Inicio · Gestión · Viajes · Más**. Desaparecen Mensajes, Avisos y Estadísticas.
- Todas las pantallas: **botón Actualizar** junto al **indicador de conexión**; botón **Acciones** con menú según lo
  marcado.
- **Inicio de sesión:** botón **Servidor** en rojo si no hay servidor (y diálogo «Falta el servidor» al intentar
  operar sin él); botones **Entrar** (azul), **Olvidé usuario/contraseña** (naranja) y **Registrarme** (sin relleno).
- **Inicio:** tarjeta de la persona; botones **Perfil**, **Hijos**, **Mi QR**; Entidad, itinerario y parada, roles y
  viajes; avisos «Aún no tiene Entidad / itinerario / parada» con su botón.
- **Más:** Mi QR, Conversaciones, Compartir la app, Cerrar sesión. Administrador: Nomencladores, Ajustes de la app,
  Olvidé algo, Actualizaciones de la app, Mantenimiento del servidor.

## 4. Reglas de interfaz (toda la app)

- **Tocar** una tarjeta abre su formulario; **mantenerla** la marca (check naranja arriba a la derecha); **un solo
  tipo** marcado a la vez; con marcadas: Marcar todo / Desmarcar todo / Invertir selección; las acciones de un solo
  objeto solo con una marcada.
- **Selectores** con ícono ↕, solo despliegan, nunca se marcan.
- **Formularios** sin datos de otras tablas; el campo **Activado** es un interruptor del formulario.
- Lo **desactivado** se ve atenuado solo para Administrador y Jefe.
- **Botones** siempre con ícono y texto corto (acción y, si hace falta, objeto).
- **Fechas** «sáb. dd-mm-aa»; **horas** de 12 h con a. m. / p. m. (4.4.0).
- Secciones **plegables** con su cantidad, que **recuerdan** si estaban plegadas; **paginadas de 5 en 5** (salvo las
  paradas de un itinerario elegido).

## 5. Gestión (una sola pantalla)

- Selectores **Entidad → Itinerario → Parada** (con «Todos», «Sin Entidad» —solo Administrador—, «Sin itinerario»,
  «Sin parada»), recuerdan la última elección; **buscador de personas**; secciones **Entidades, Itinerarios, Paradas,
  Personas, Solicitudes**. Número en la pestaña con las solicitudes pendientes (o resueltas, para el trabajador).
- **Acciones** según lo marcado: crear, editar, eliminar (con confirmación y cascadas), asignar rol, cambiar de
  Entidad / itinerario / parada, añadir o quitar paradas, ordenar arrastrando, declarar ausencia, solicitar Entidad o
  itinerario, aprobar / rechazar (motivo del nomenclador), cancelar / eliminar solicitudes propias, mostrar u ocultar
  aprobadas y rechazadas, **Incluir por QR**.
- **Paradas compartidas** entre itinerarios y Entidades; el Jefe edita pero no elimina las que usan otros; ubicación
  por **«Usar mi ubicación actual»** o **compartida desde WhatsApp, Telegram, Google Maps u OsmAnd** (crear parada
  nueva o cambiar la de una existente).
- Itinerario y parada **opcionales**; quien no tiene Entidad, itinerario o parada **no ve viajes**.
- **Sin conexión:** solo consulta (salvo Incluir por QR).

## 6. QR

- **Mi QR** (Inicio y Más), cambia cada 15 s. **Incluir por QR** (Jefe y Administrador, en Gestión) incluye en
  Entidad, itinerario o parada, indicando dónde está ya la persona; funciona con y sin conexión.

## 7. Nomencladores (solo Administrador, una pantalla)

- **Tipos de vehículo** (asientos, de pie y total calculado), **Tipos de ausencia**, **Motivos de conversación** (para
  clasificar mensajes al desarrollador), **Motivos de denegación**, **Causas de detención**. Lo que está en uso no se
  elimina: se propone desactivar.
- **Se elimina el modelo Vehículo:** el viaje indica solo el **tipo de vehículo**.

## 8. Viajes

- **Dos viajes por día:** **ida** (todos suben en la primera parada y se van bajando) y **regreso** (suben por paradas
  y se bajan todos en la primera). Planificación **manual**, uno a uno (casillas Ida y Regreso).
- Se espera a **todos los del itinerario**; quien no va lo indica («No voy»). Los **niños** cuentan como pasajeros pero
  no ocupan plaza.
- **Estados:** **Planificado → En ejecución → Terminado**, o **Cancelado** (Administrador o Jefe que lo planificó). En
  ejecución ya no se edita.
- Secciones: **Planificados**, **En ejecución**, **Terminados** y **Cancelados**; Terminados y Cancelados se pueden
  mostrar u ocultar. No hay sección «Sin confirmar» (no existe el estado Confirmado).

## 9. Tiempo real (línea del recorrido, sin mapa)

- **Estados del trabajador**, calculados **en el teléfono** (envía solo cambios con su hora de captura, en cola sin
  conexión, con acuse y reintento), **iguales en la ida y en el regreso** (4.4.0): **De camino** ⇄ **En la parada** →
  **Viajando** → **Dejado**; **No recogido** (estaba en la parada y el vehículo pasó sin recogerle), **Retrasado**
  (el vehículo pasó por su parada antes de que llegara) o **No voy**. Se sube y se baja en **cualquier parada**,
  detectada por cercanía; la parada asignada es la **parada habitual** (opcional, solo para planificar).
  - Reglas: radio de parada, tolerancia del GPS, velocidad humana, 6 cálculos seguidos para Dejado, distancia de
    abandono, paso del vehículo por la parada.
- **Sensores:** los teléfonos Viajando calculan si el vehículo está **Detenido** o **En movimiento** y su
  **próxima parada**; el servidor decide por **mayoría** (mínimo 3). Detenido en una parada = **Dejando / Recogiendo**;
  en el trayecto, sin causa hasta que la indiquen.
- **Estado del viaje:** a mano (Administrador o Jefe), o automático (3 trabajadores Viajando en cualquier parada;
  llegada a la parada final; 2 h tras el último Dejado; 5 h de duración máxima; eliminación a las 5 h si nunca salió).
- **Lo calcula el servidor:** personas en el vehículo y por parada, hora de paso por cada parada, cantidad de sensores.
- **Línea:** siempre en el mismo sitio, orden de paradas según ida o regreso, en cada parada cuántos hay De camino, En
  la parada, Retrasados, No recogidos y Dejados (sin ceros), tarjetas de sensores y «Mi estado» (con su parada) del
  mismo tamaño. **Sin horas estimadas.**
- **Ubicación obligatoria** para ver el viaje en curso; los avisos de activar el GPS y de quitarlo van en «Mi estado».

## 10. Notificaciones (del teléfono, sin pantalla de avisos; 4.3.0)

Siempre en la cortina (con la app abierta o cerrada), cada una actualizada en su sitio, en seis canales:

1. **Viajes:** una por viaje (planificado, cambiado + «Cambió la …», en ejecución, cancelado, eliminado).
2. **Vehículo:** una por viaje en ejecución (tipo • en movimiento/detenido, Anterior/Próxima, Recogiendo/Dejando en,
   Primera/Última parada, Sin datos).
3. **Mi estado:** la fija del servicio de ubicación (estado, itinerario, Mi parada; avisos de GPS y de permiso).
4. **Solicitudes:** una de pendientes (Administrador / Jefe) y una por cada respuesta a las propias.
5. **Mensajes:** una de respuestas del desarrollador.
6. **Actualizaciones:** una de versión disponible/obligatoria.

## 10 bis. Actualizaciones de la app

- El Administrador sube desde la app los APK de **64 y 32 bits** (Más → Actualizaciones de la app) y marca la versión
  **Obligatoria** u Opcional. Notificación de actualización disponible.
- **Obligatoria:** la app lo detecta en cualquier consulta, **cierra la sesión** (también en el servidor) y desde la
  **pantalla de inicio de sesión** obliga a **descargar e instalar** antes de entrar (lo recuerda sin conexión). El
  servidor rechaza el inicio de sesión de versiones con una obligatoria pendiente.

## 11. Conversaciones

- **Sin chat del viaje** ni conversaciones con roles. Solo **conversación con el desarrollador**, estilo WhatsApp,
  solo texto, con motivo.

## 12. Ajustes de la app (un solo nivel, solo Administrador)

- Nombres cortos; agrupados en **generales** y **específicos**; tiempos con unidades `seg min hor dia sem mes ano`
  (mes = 30 días, año = 365) y distancias `m km`, combinables (`12hor30min`, `1km200m`); velocidades `10km/hor`.
- Generales: Radio parada `100m`, Anticipación viaje `10min`, Mínimo confirmaciones `3`.
- Estado trabajador: Velocidad humana `10km/hor`, Tolerancia GPS `20m`, Distancia abandono `1km`, Frecuencia cálculo
  `10seg`, Cálculos consecutivos `6`, Espera final `10min`.
- Estado viaje: Plazo eliminación `5hor`, Duración máxima `5hor`, Espera cierre `2hor`.
- Ventana viaje: Inicio ventana (X) `10min`, Fin ventana (Y) `5min`, **Frecuencia corta** `10seg` (app abierta, o
  cerrada dentro de la ventana) y **Frecuencia larga** `15min` (mínimo; app cerrada fuera de la ventana) (4.4.0,
  sustituyen a Frecuencia ventana y Frecuencia fuera ventana).
- Sincronización: Frecuencia chat `5seg`, Conservación cambios `1mes` (registro de cambios, 4.4.0).
- Notificaciones: Detención larga `5min`.
- Más los de contraseñas, acceso, «Olvidé algo», conversaciones y archivos.

## 13. Lo que se elimina

Chofer, Vehículo, roles configurables, pantallas Roles / Entidades / Itinerario sueltas, planificación por fechas y
copiar viajes, estadísticas, baja por inactividad, avisos en pantalla, chat del viaje, mapas, QR impreso y de subida,
ajustes por Entidad / itinerario / parada / usuario.

## 14. Entregables

- Las **2 APK** (64 y 32 bits).
- El **código del servidor con `vendor/` incluido**, listo para subir por FTP; todo lo que haya que ejecutar en el
  servidor, por **endpoints de la API**.
- Sin contenedores por ahora.

## 15. Versión 4.1.0 (13/11/2026, docs/11 §11.56–§11.60)

- **Pertenencias:** un itinerario está como mucho en una Entidad (puede no tener); una parada, en varios itinerarios o
  en ninguno; una persona, en varias Entidades y en **varios itinerarios de cada una**, cada uno con su parada. Aprobar
  o incluir por QR **añade** el itinerario. Cada uno ve los viajes de todos sus itinerarios.
- **Gestión:** tarjetas de las tablas → pantalla de cada tabla (con los sueltos) → formulario con sus relaciones.
- **Inicio:** como el formulario del Trabajador de la propia persona (datos, Mi QR, viajes activos, Entidades,
  itinerarios y sus solicitudes, paradas, hijos) con sus Acciones; Más se queda con Conversaciones, Compartir la app y
  las herramientas del Administrador.
- **Toda la app:** spinner con «Cancelar» en las operaciones con el servidor y mensajes escuetos; Actualizar solo la
  pantalla visible y las notificaciones; sin contraseñas propuestas; notificaciones dentro de la app si está abierta;
  «Salir sin guardar» y teclado en todos los formularios; modales con ícono, título, pregunta y botones.

## 16. Versión 4.2.0 (15/11/2026, docs/11 §11.61–§11.62)

- **Ausencias por itinerario:** una ausencia cubre uno o varios itinerarios de la persona (de cualquiera de sus
  Entidades), no toda la Entidad; «Hasta» opcional (vacío = indefinida); «Terminar ausencia» en Acciones de Inicio.
- **Solicitudes:** el diálogo de una solicitud muestra **Aprobar** y **Rechazar** (con motivo) a quien puede
  resolverla (Administrador; Jefe en su itinerario) y **Cancelar solicitud** si es propia. Las listas de Entidades e
  Itinerarios tienen la sección **«Solicitudes»**.
- **Tiempo real:** «Sin datos del vehículo» hasta que informan los sensores (el servidor ya no supone «En movimiento»
  al empezar); por qué cada trabajador es o no sensor (tocar los sensores); **Dormido y Botado también en la ida**,
  respecto a la primera parada, con la regla simplificada (Dormido = llega después del paso; Botado = estaba antes y
  no subió), sin «Cálculos consecutivos» para Botado; **«Pasó por la parada X»** a mano para el Jefe y el
  Administrador, que cuenta como la confirmación de los sensores.
- **Ventana de viaje y segundo plano:** de X antes de la salida a Y después de que el viaje termine para el
  trabajador, envía y recibe cada Z en una sola petición con un servicio de ubicación en primer plano que arranca una
  alarma exacta aunque la app esté cerrada (notificación fija); fuera, solo recibe cada F (≥ 15 min) sin GPS; se
  reprograma al reiniciar. Pantalla de permisos (ubicación todo el tiempo, batería sin restricciones, alarmas, consejo
  por fabricante) y, sin ellos, solo con la app abierta. La ubicación solo es obligatoria para los trabajadores del
  viaje. Contador hasta la próxima conexión junto al botón Actualizar.
- **Tema** claro, oscuro o automático (inicio de sesión e Inicio → Acciones).
- **Caché local** en archivos: se muestra al momento lo guardado («Actualizado hace …») y se pregunta solo lo que
  cambió (ETag/304 y huellas de `GET sync`); sin conexión, solo consulta; se borra al cerrar sesión.
- **Servidor:** migración de actualización 4.1.0 → 4.2.0 con «Actualizar base de datos» (docs/10 §10.3 bis).

## 17. Versión 4.3.0 (15/11/2026, docs/11 §11.63)

- **Tema en un solo botón** con el icono del modo actual y un menú (Claro, Oscuro, Automático), en el inicio de
  sesión y en la barra de Inicio.
- **Sin sesión:** el inicio de sesión comprueba la conexión cada 30 s con su contador; Recuperar acceso muestra el
  contador de la consulta de la solicitud pendiente.
- **Viajando y Recogido unificados en Viajando** (base de datos, servidor, app y notificaciones). Estados: ida = De
  camino, En parada, Viajando, Dejado, Botado, Dormido, No voy; regreso = De camino, En parada, Viajando, Botado,
  Dormido, No voy.
- **Notificaciones nuevas** (§10): seis canales, una notificación por cosa que se actualiza en su sitio, línea
  destacada en naranja, siempre en la cortina; sin aviso dentro de la app.
- **Servidor:** migración de actualización 4.2.0 → 4.3.0 con «Actualizar base de datos» (convierte los «recogido»);
  acepta «recogido» de los teléfonos con la 4.2.0.

## 18. Versión 4.4.0 (16/11/2026, docs/11 §11.65)

- **Frecuencias:** solo dos, **Frecuencia corta** (10 s) con la app abierta o en recientes y, cerrada, dentro de la
  ventana de un viaje; **Frecuencia larga** (15 min, mínimo) solo cerrada y fuera de la ventana. Corrige el contador de
  ~15 min dentro de la ventana.
- **Estados del trabajador**, iguales en la ida y en el regreso: **De camino, En la parada, Viajando, Dejado, No
  recogido** (antes Botado), **Retrasado** (antes Dormido) y **No voy**; finales Dejado, No recogido, Retrasado y No
  voy. Se sube y se baja en **cualquier parada**, detectada por cercanía; la parada asignada pasa a ser la **parada
  habitual** (opcional, solo para planificar).
- **Hora de captura:** todo lo que calcula el teléfono (estado del trabajador y observaciones del vehículo) va con su
  hora y en cola si no hay conexión; el servidor fija con ellas la salida y el paso por cada parada. Si un teléfono no
  envía, el servidor pone No recogido / Retrasado al pasar el vehículo.
- **Ver recorrido:** mismo diseño de la línea, sin la tarjeta de ocupación; tarjetas de Sensores y Mi estado del mismo
  tamaño; Mi estado con su parada (salvo Viajando; en Dejado, donde se le dejó); cada parada con cuántos hay De
  camino, En la parada, Retrasados, No recogidos y Dejados (sin ceros).
- **Registro de cambios:** el servidor anota cada alta, cambio y baja; la app descarga todo tras el inicio de sesión y
  en cada consulta aplica solo lo que cambió, sin avisar; las pantallas abren con lo guardado (spinner solo si no hay
  nada). Poda a 1 mes (ajuste «Conservación cambios»).
- **Interfaz:** modales con los botones a todo el ancho, uno debajo del otro (acción arriba, Cancelar gris abajo;
  Eliminar rojo; Confirmar en el color principal); «Salir sin guardar» con **Guardar**; spinners «Consultando /
  Creando / Actualizando / Eliminando [Objeto]» sobre fondo blanco con el círculo naranja y «✕ Cancelar», con las barras
  visibles; sin cintas tras las acciones; menús con nombres CRUD («Crear Viaje», «Actualizar Viaje: Cancelar»…);
  «Crear [Objeto]» en cada formulario, que tras guardar sigue mostrando lo guardado; relaciones **pendientes hasta
  Guardar**; ningún icono cambiado.
- **Crear Viaje:** Ida y Regreso con su interruptor, Fecha, Hora (12 h, en un diálogo) y Tipo de vehículo; por
  omisión, ida hoy 05:00 p. m. y regreso mañana 06:00 a. m. Un viaje cancelado o eliminado ya no impide crear otro.
- **Paradas:** botón **Pegar ubicación** («lat, lng», Google Maps, OsmAnd, OpenStreetMap, `geo:`).
- **Inicio:** «Ocultar / Mostrar solicitudes aprobadas» (ocultas por omisión; se recuerda).
- **Nomencladores:** motivos de rechazo separados para solicitudes de **Entidad** y de **itinerario**; la instalación
  crea los tipos de vehículo **Ómnibus Yutong** (45 + 15) y **Carro Dongfeng** (32 + 9).
- **Servidor:** migración de actualización 4.3.0 → 4.4.0 con «Actualizar base de datos» (docs/10 §10.3 quater); las
  apps 4.3.0 siguen funcionando.

