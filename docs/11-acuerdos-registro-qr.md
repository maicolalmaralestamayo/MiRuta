# 11. Acuerdos: registro, usuarios, contraseñas, tarjeta de usuario y QR

Acuerdos con el Product Owner del 03/11/2026, **pendientes de implementar**. Cambian lo descrito en
`02-procesos.md` (§2.1 y §2.9), `05-app.md` y `09-repaso-pantallas.md` en lo que se indica.

## 11.1 Jerarquías

- Nuevo campo **abreviatura**. Tanto el **nombre** como la **abreviatura** son **obligatorios y únicos**.
- La app arranca **sin jerarquías**: se quita la lista inicial (Coronel, Teniente coronel…) y las crea el
  Administrador.
- **La lista de jerarquías no es pública.** Solo se ve con sesión iniciada; hoy `GET /ranks` es público y deja de
  serlo.
- El trabajador **elige su jerarquía de un listado** (por su nombre) en «Otros datos del registro» (§11.4).
  Es **obligatoria**.

## 11.2 Tarjeta de usuario

**Tarjeta:** visualización resumida y compacta de los datos de un objeto. No lleva los nombres de los campos,
solo los valores.

La tarjeta de usuario, igual en toda la app:

| Posición | Contenido | Ejemplo |
|---|---|---|
| Izquierda | Foto de perfil (sin foto: ícono genérico de persona) | — |
| Línea 1 | ★ (siempre la estrella, no el ícono de la jerarquía) + abreviatura de la jerarquía + primer apellido | ★ Cap. Almarales |
| Línea 2 | Abreviatura de la Entidad • Pase número | UMIM • Pase 1024 |
| Línea 3 | Itinerario • calle de la parada. punto de referencia de la parada; si no tiene: **Sin itinerario** | Ruta Playa • Calle 23. Coppelia |
| Línea 4 | Roles separados por •; si no tiene ninguno: **Trabajador** | Jefe de Transporte • Chofer |

- Si un texto no cabe, se corta con «…».
- La parada no tiene campo «nombre»: se usa el **punto de referencia**. Campos de la parada: Entidad, punto de
  referencia, calle, entrecalle 1 (opcional), entrecalle 2 (opcional), latitud y longitud.

## 11.3 Usuario

- Longitud: **de 2 a 50 caracteres** (antes de 4 a 20).
- La regla «al menos 3 letras» pasa a **al menos 2 letras**. El resto de reglas de formación y las palabras
  reservadas se mantienen.

**Usuario propuesto.** El sistema siempre propone un usuario; quien registra (el trabajador o su superior) puede
cambiarlo. Se van añadiendo partes, separadas por punto, solo mientras el resultado esté ocupado o no sea válido,
todo en minúsculas y sin tildes:

1. primer nombre → `maicol`
2. \+ segundo nombre, si tiene → `maicol.alberto`
3. \+ primer apellido → `maicol.alberto.almarales`
4. \+ abreviatura de la Entidad → `maicol.alberto.almarales.umim`
5. \+ número de Pase → `maicol.alberto.almarales.umim.1024`

## 11.4 Registro

### Pantalla 1: Registro (una sola pantalla)

- Primer nombre, segundo nombre (opcional), primer apellido, segundo apellido y **sexo**.
- **Abreviatura de la Entidad**: se comprueba que existe y se muestra su nombre para confirmar; **si no existe,
  no se puede registrar**. Nunca se muestra la lista de Entidades.
- **Pase**.
- **Usuario** y **contraseña** (con su repetición), ya **propuestos por el sistema** y modificables.
- Si el Pase ya está registrado en esa Entidad:
  > «Alguien ya se registró con este número de pase. Si fue usted, emplee la opción Olvidé algo. Si no fue usted,
  > comuníquese con el Administrador de la aplicación, su Jefe de Itinerario o el Jefe de Transporte de su
  > Entidad.»
- Al registrarse, la cuenta queda creada y **unida a su Entidad**: desaparece el antiguo segundo paso «unirse a la
  Entidad».

**Primer registro (Administrador).**
- La app pregunta al servidor (consulta pública que solo responde sí o no) **si ya hay Administrador**.
- Si no lo hay, **Entidad y Pase quedan inhabilitados**. El **sexo sí está habilitado** y se guarda en la cuenta,
  porque el Administrador no es trabajador.
- El servidor también lo comprueba: si ya hay Administrador, exige Entidad y Pase. El primero que completa el
  registro es el Administrador, aunque dos lo intenten a la vez.

### Pantalla 2: «Otros datos del registro»

Se abre justo después del registro, ya con la sesión iniciada:

- **Jerarquía**: se elige de un listado por su nombre. **Obligatoria.**
- **Solicitar itinerario y parada** (siempre juntos).
- **Declarar hijos.**
- **Solicitar roles**: chofer, Jefe de itinerario o Jefe de Transporte.
- **Mi QR**: para que un jefe le dé de alta directamente en un itinerario y su parada (§11.7).
- **Hablar con el desarrollador** en esta pantalla y en todas las que se abren desde ella.

**Itinerario y parada siempre van juntos.** Ningún trabajador tiene itinerario sin parada ni parada sin
itinerario. Mientras no tiene ninguno de los dos, su tarjeta dice «Sin itinerario».

### Registro por un superior

- Lo hacen el Administrador, el Jefe de Transporte o el Jefe de itinerario.
- El sistema propone usuario y contraseña; el registrador puede cambiarlos.
- Al guardar, se muestran la tarjeta del trabajador, su **usuario** y su **contraseña**, con botones para copiarlos
  y compartirlos.
- **Desaparecen** «Me registró un superior» y los códigos de activación.

## 11.5 Contraseñas

- **Contraseña puesta por otro:** al entrar por primera vez con una contraseña que no eligió él mismo, el
  trabajador **debe cambiarla**.
- El trabajador cambia su propia contraseña desde **Mi perfil** cuando quiera. **Nadie se la resetea sin que él lo
  pida.**

**Olvidé algo.**
1. El trabajador lo pide indicando su **Entidad** y su **Pase**.
2. **Solo el Administrador** lo aprueba, tras verificar los datos y confirmarlo por una tercera vía (llamada o
   WhatsApp).
3. Al aprobarlo, el sistema propone una contraseña nueva. Se comunica **solo lo que se olvidó y se pidió**
   (usuario, contraseña o ambos), por esa tercera vía o enviándolo al teléfono que hizo la solicitud.
4. Al entrar con la contraseña nueva, el trabajador debe cambiarla.

## 11.6 Servidor y conexión

- Por defecto **la app no trae la dirección del servidor**: las APK se compilan sin ella.
- Botón del servidor en la pantalla de inicio de sesión (como ya funciona):

  | Estado | Texto y color |
  |---|---|
  | Sin dirección | «Indicar servidor», naranja (énfasis) |
  | Conectado | «Conectado al servidor», verde |
  | Sin conexión | «Desconectado del servidor», rojo |

- **Punto de conexión**, solo después de iniciar sesión (antes ya informa el botón del servidor):
  - siempre visible, pequeño, en la barra superior de todas las pantallas;
  - **verde** si hay conexión con el servidor y **rojo** si no;
  - se actualiza con cada petición y, si no hay actividad, comprobando cada 30 segundos;
  - al tocarlo: «Conectado a <servidor>» o «Sin conexión con el servidor desde las hh:mm».

## 11.7 Código QR del trabajador

**Un solo QR para toda la app**, generado siempre de la misma forma.

**Usos**
1. **Subida al transporte.** Lo escanea el chofer o el Jefe de itinerario.
   - Si el trabajador no pertenece a ese itinerario, se avisa a quien escanea, que **decide si lo deja subir**.
   - Si lo deja, se registra y **cuenta como pasajero**.
   - Estadística nueva: **trabajadores que viajan fuera de su itinerario**.
2. **Alta directa en un itinerario**, sin solicitud.
   - La hace el **Jefe de ese itinerario o el Jefe de Transporte**, siempre de la **misma Entidad** que el
     trabajador.
   - Quien escanea elige la **parada**.
   - Si el trabajador tenía otro itinerario, **se le cambia y pierde el anterior**.
   - Si era Jefe del itinerario anterior, sigue siéndolo: cambiar de itinerario no quita jefaturas.

**Funcionamiento con o sin conexión en ambos teléfonos.** La conexión mejora, pero no limita su uso.
1. Al iniciar sesión, el teléfono del trabajador crea una clave propia en el almacén seguro de Android, que no se
   puede copiar ni exportar.
2. El servidor firma un **certificado** de esa clave: trabajador, Entidad y fecha de caducidad.
3. El teléfono genera el QR **sin conexión**, firmando el identificador del trabajador, la fecha y hora y un
   número aleatorio. **Se renueva cada pocos segundos.**
4. El teléfono que escanea comprueba **sin conexión** la firma del servidor sobre el certificado (con la clave
   pública del servidor guardada al sincronizar) y la firma del QR.
5. La tarjeta del trabajador sale de la lista de trabajadores de la Entidad guardada al sincronizar: **el QR no
   lleva datos personales**.
6. Sin conexión, las subidas y las altas se guardan en el teléfono y se envían al recuperarla.

**Para que no se pueda copiar ni reutilizar**
- La pantalla del QR **no admite capturas ni grabación** de pantalla.
- Una foto de la pantalla deja de valer en segundos.
- Una copia de la app en otro teléfono no tiene la clave.
- Cada código es de **un solo uso**: el teléfono que escanea no acepta dos veces el mismo, y el servidor descarta
  los repetidos al sincronizar.
- Diferencia de hora admitida entre los dos teléfonos: **±2 minutos**.

## 11.8 QR impreso para trabajadores sin teléfono

- Al registrar a un trabajador, el Administrador, el Jefe de Transporte o el Jefe de itinerario indican **si tiene
  teléfono**.
- **Sin teléfono:** el sistema genera un **QR fijo**, que **no caduca**, se puede **imprimir** y se puede
  **compartir** con la lista de Android (WhatsApp, Telegram, Bluetooth…).
- **Usos:** los mismos que el QR del trabajador (§11.7):
  - subir a la guagua;
  - que un jefe le dé de alta o le **cambie de itinerario y parada**.
- **Funciona sin conexión.**
  - El código solo lleva el número del trabajador y la firma del servidor, sin datos personales.
  - Quien escanea con MiRuta ve la tarjeta del trabajador, que sale de la lista de la Entidad guardada en su
    teléfono.
- **Tarjeta impresa:** el QR y, impresos al lado, nombres y apellidos, sexo, Entidad y Pase.
  - **Sin jerarquía, itinerario ni parada**, para que siga valiendo dentro de la misma Entidad sin reimprimirla.
- **La foto no es obligatoria.** Si tiene foto, se muestra al escanear para comparar; si no, se compara con el
  nombre y el Pase.
- **Quién lo ve, lo reimprime y lo anula:** el Administrador, el Jefe de Transporte de su Entidad y el Jefe de su
  itinerario.
- **Protección ante copias** (una fotocopia funciona igual que el original):
  - se puede **anular y generar uno nuevo** en cualquier momento; sin conexión, el teléfono que escanea se entera al
    sincronizar;
  - **una sola subida por trayecto**: si el mismo QR se usa dos veces en el mismo viaje, se avisa.
- **Cuenta del trabajador sin teléfono:**
  - también se le crea usuario y contraseña, propuestos por el sistema;
  - cuando entra por primera vez en la app, su QR impreso **se anula** y pasa a usar el QR que cambia cada pocos
    segundos.
