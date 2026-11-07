# 12. Resumen de la próxima versión (07/11/2026)

Resumen **consolidado** de lo acordado en `docs/11-acuerdos-registro-qr.md` §11.19–§11.52, con la **última decisión**
de cada tema (lo sustituido no aparece). Pendiente de implementar.

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
- **Fechas** «sáb. dd-mm-aa»; **horas** de 24 h.
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

- **Estados del trabajador**, calculados **en el teléfono** (envía solo cambios, con acuse y reintento):
  - Ida: De camino a la parada ⇄ En la parada → **Viajando** → **Dejado** (fin); o **No voy a viajar**.
  - Regreso: De camino a la parada ⇄ En la parada → **Recogido** (fin); **Botado**, **Dormido**; o **No voy a viajar**.
  - Reglas: radio de parada, tolerancia del GPS, velocidad humana, 6 cálculos seguidos para Dejado, distancia de
    abandono, salida o paso del vehículo.
- **Sensores:** los teléfonos Viajando / Recogidos calculan si el vehículo está **Detenido** o **En movimiento** y su
  **próxima parada**; el servidor decide por **mayoría** (mínimo 3). Detenido en una parada = **Dejando / Recogiendo**;
  en el trayecto, sin causa hasta que la indiquen.
- **Estado del viaje:** a mano (Administrador o Jefe), o automático (3 trabajadores Viajando o Recogidos en la última
  parada; llegada a la parada final; 2 h tras el último Dejado o Recogido; 5 h de duración máxima; eliminación a las
  5 h si nunca salió).
- **Lo calcula el servidor:** personas en el vehículo y por parada, hora de paso por cada parada, cantidad de sensores.
- **Línea:** siempre en el mismo sitio, orden de paradas según ida o regreso, cantidades (sin ceros), tarjeta de
  «N esperando en [primera parada]», Viajando o Recogidos, sensores destacados, «Mi estado». **Sin horas estimadas.**
- **Ubicación obligatoria** para ver el viaje en curso; recordatorios de activar el GPS (10 min antes) y de quitarlo.

## 10. Notificaciones (del teléfono, sin pantalla de avisos)

- Viaje: creación y cambios de estado (no eliminación ni terminación), cambios mientras está planificado, sus propios
  estados; a quienes están En la parada: detención de más de 5 min, reanudación y llegada a cada parada.
- Trabajador: solicitudes aprobadas o denegadas; respuestas del desarrollador; **actualizaciones de la app**.
- Administrador y Jefe: solicitudes recibidas.

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
- Sincronización: Frecuencia reposo `1hor`, Frecuencia día viaje `15min`, Frecuencia chat `5seg`.
- Notificaciones: Detención larga `5min`.
- Más los de contraseñas, acceso, «Olvidé algo», conversaciones y archivos.

## 13. Lo que se elimina

Chofer, Vehículo, roles configurables, pantallas Roles / Entidades / Itinerario sueltas, planificación por fechas y
copiar viajes, estadísticas, baja por inactividad, avisos en pantalla, chat del viaje, mapas, QR impreso y de subida,
ajustes por Entidad / itinerario / parada / usuario.
