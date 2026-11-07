# 11. Acuerdos: registro, personas y Entidades, contraseñas, tarjetas, hijos y QR

Acuerdos con el Product Owner del 03 y 04/11/2026, **implementados en la versión 3.0.0**. Cambian lo descrito en
`02-procesos.md`, `05-app.md` y `09-repaso-pantallas.md` en lo que se indica.

## 11.1 Se eliminan el Pase y la jerarquía

- **Se elimina el Pase de toda la app**: registro, tarjetas, búsquedas, «Olvidé algo», QR, estadísticas y API. En
  la práctica daba problemas (a veces no se tiene Pase y hay que acceder al transporte).
- **Se elimina la jerarquía, por ahora**: nomenclador, campo de la persona, su elección y las estadísticas por
  jerarquía.

## 11.2 La persona se identifica por su carné de identidad

- **El carné de identidad** (11 dígitos) identifica a la persona y es **único en toda la app**, como en la primera
  versión (`07-algoritmos.md` §7.1 de entonces):
  - los 6 primeros dígitos (`AAMMDD`) son la **fecha de nacimiento**, que se calcula y no se escribe;
  - el **7.º dígito** da el siglo: 9 → 1800; 0–5 → 1900; 6–8 → 2000;
  - el **penúltimo dígito** da el **sexo**: par → masculino; impar → femenino. El sexo se calcula y no se elige.
- Se guarda **cifrado**, con una huella (HMAC) para buscarlo y comprobar que no se repite.
- **Quién lo ve:**
  - el propio trabajador;
  - el Administrador;
  - el Jefe de itinerario, solo el de los miembros de su itinerario y de quienes solicitan entrar en él.
  - No lo ven los demás trabajadores ni el Jefe de Transporte.
- Los **hijos** también se identifican por su carné, del que salen su fecha de nacimiento y su sexo (§11.11).

## 11.3 Tarjeta de usuario

**Tarjeta:** visualización resumida y compacta de los datos de un objeto. No lleva los nombres de los campos,
solo los valores.

| Posición | Contenido | Ejemplo |
|---|---|---|
| Izquierda | Foto de perfil (sin foto: ícono genérico de persona) | — |
| Línea 1 | Nombres y apellidos | Maicol Almarales Tamayo |
| Línea 2 | Abreviaturas de sus Entidades separadas por •; si no tiene ninguna: **Sin Entidad** | UMIM • DPTRANS |

- El itinerario, la parada y los roles **no van en la tarjeta del usuario**: tienen sus propias tarjetas (§11.10).
- Si un texto no cabe, se corta con «…».
- En las tarjetas, la parada se nombra por su **punto de referencia**, porque no tiene campo «nombre». Campos de la
  parada: Entidad, punto de referencia, calle, entrecalle 1 (opcional), entrecalle 2 (opcional), latitud y
  longitud.

## 11.4 Usuario

- Longitud: **de 2 a 50 caracteres** (antes de 4 a 20).
- La regla «al menos 3 letras» pasa a **al menos 2 letras**. El resto de reglas de formación y las palabras
  reservadas se mantienen.

**Usuario propuesto.** El sistema siempre propone un usuario; quien registra (la persona o el Administrador) puede
cambiarlo. Se van añadiendo partes, separadas por punto, solo mientras el resultado esté ocupado o no sea válido,
todo en minúsculas y sin tildes:

1. primer nombre → `maicol`
2. \+ segundo nombre, si tiene → `maicol.alberto`
3. \+ primer apellido → `maicol.alberto.almarales`
4. \+ segundo apellido → `maicol.alberto.almarales.tamayo`
5. \+ un número → `maicol.alberto.almarales.tamayo.2` (3, 4…)

## 11.5 Registro

### Pantalla 1: Registro

- Primer nombre, segundo nombre (opcional), primer apellido, segundo apellido y **carné de identidad**. El sexo y la
  fecha de nacimiento salen del carné.
- **Usuario** y **contraseña** (con su repetición), ya **propuestos por el sistema** y modificables.
- **Sin Entidad.** La Entidad se solicita después, ya dentro de la app (§11.6).
- Si el carné ya está registrado:
  > «Alguien ya se registró con este carné de identidad. Si fue usted, emplee la opción Olvidé algo. Si no fue
  > usted, comuníquese con el Administrador de la aplicación, su Jefe de Itinerario o el Jefe de Transporte de su
  > Entidad.»

**Primer registro (Administrador).**
- La app pregunta al servidor (consulta pública que solo responde sí o no) **si ya hay Administrador**.
- Si no lo hay, quien se registra es el **Administrador**. El servidor lo comprueba: el primero que completa el
  registro es el Administrador, aunque dos lo intenten a la vez.

### Pantalla 2: «Otros datos del registro»

Se abre justo después del registro, ya con la sesión iniciada:

- **Solicitar entrar en una Entidad**: se escribe su abreviatura, se comprueba que existe y se muestra su nombre
  para confirmar. Nunca se muestra la lista de Entidades.
- **Solicitar itinerario y parada** (siempre juntos), una vez aprobada la Entidad.
- **Añadir hijos** (directamente, sin solicitud: §11.11).
- **Solicitar roles**: chofer, Jefe de itinerario o Jefe de Transporte.
- **Mi QR**: para que un jefe le dé de alta directamente en un itinerario y su parada (§11.8).
- **Hablar con el desarrollador** en esta pantalla y en todas las que se abren desde ella.

**Itinerario y parada siempre van juntos.** Nadie tiene itinerario sin parada ni parada sin itinerario. Mientras no
tiene ninguno de los dos en una Entidad, en Inicio sale la tarjeta «Sin itinerario» (§11.10).

### Registro por el Administrador

- Lo hace **solo el Administrador**, en la Entidad que elija.
- Datos: nombres y apellidos, **carné de identidad** y si **tiene teléfono** (§11.9).
- El sistema propone usuario y contraseña; el Administrador puede cambiarlos.
- Al guardar, se muestran la tarjeta de la persona, su **usuario** y su **contraseña**, con botones para copiarlos
  y compartirlos.
- **Si el carné ya existe** (la persona ya tiene cuenta, quizá en otra Entidad): **no se crea otra cuenta**; se le
  añade esa Entidad, ya aprobada. Si tiene teléfono, se le avisa; si no, se lo comunica el Administrador.
- **Desaparecen** «Me registró un superior» y los códigos de activación.

## 11.6 Varias Entidades por persona

- **La cuenta es de la persona**: usuario, contraseña, nombres y apellidos, carné (y con él sexo y fecha de
  nacimiento), **hijos** y **QR**.
- **En cada Entidad tiene**: itinerario y parada, y roles (Chofer, Jefe de itinerario, Jefe de Transporte).
- **Está activo a la vez en todas las Entidades** en las que solicitó entrar y se le aprobó: en cada una cuenta
  como pasajero esperado y en sus estadísticas.
- **Solicitar entrar en una Entidad:**
  - la solicita la persona, indicando la abreviatura de la Entidad;
  - la aprueba **solo el Administrador**.
- **Darse de baja de una Entidad:** cuando quiera. Se borran su itinerario, su parada y sus roles en esa Entidad.
  Para volver a pertenecer a ella, tiene que **solicitarlo de nuevo**. Si era su única Entidad, se queda con la
  cuenta **sin Entidad**.
- **Ausencias:** no hacen falta para nada de esto. Se declaran para **no perder el derecho a viajar** (§11.12).

## 11.7 Contraseñas

- **Contraseña puesta por otro:** al entrar por primera vez con una contraseña que no eligió él mismo, debe
  **cambiarla**.
- Cada uno cambia su propia contraseña desde **Mi perfil** cuando quiera. **Nadie se la resetea sin que él lo
  pida.**

**Olvidé algo.**
1. La persona lo pide indicando su **carné de identidad** y un **teléfono**.
2. **Solo el Administrador** lo aprueba, tras verificar los datos y confirmarlo por una tercera vía (llamada o
   WhatsApp).
3. Al aprobarlo, el sistema propone una contraseña nueva. Se comunica **solo lo que se olvidó y se pidió**
   (usuario, contraseña o ambos), por esa tercera vía o enviándolo al teléfono que hizo la solicitud.
4. Al entrar con la contraseña nueva, debe cambiarla.

## 11.8 Código QR del trabajador

> **Sustituido por §11.19 (06/11/2026, pendiente de implementar):** el QR solo sirve para asignar itinerario.

**Un solo QR por persona para toda la app**, generado siempre de la misma forma. Identifica a la **persona**, no
una Entidad: sirve en todas sus Entidades.

**Usos**
1. **Subida al transporte.** Lo escanea el chofer o el Jefe de itinerario.
   - Si la persona **no pertenece a ese itinerario o a esa Entidad**, se avisa a quien escanea, que **decide si lo
     deja subir**.
   - Si lo deja, se registra y **cuenta como pasajero**.
   - Estadística nueva: **trabajadores que viajan fuera de su itinerario** (o de su Entidad).
   - Se marca **qué hijos suben con él** (§11.11).
2. **Alta directa en un itinerario**, sin solicitud.
   - La hace, por ahora, **solo el Administrador**, y solo si la persona **pertenece a esa Entidad**.
   - Quien escanea elige la **parada**.
   - Si la persona tenía otro itinerario **en esa Entidad**, **se le cambia y pierde el anterior**.
   - Si era Jefe del itinerario anterior, sigue siéndolo: cambiar de itinerario no quita jefaturas.

**Funcionamiento con o sin conexión en ambos teléfonos.** La conexión mejora, pero no limita su uso.
1. Al iniciar sesión, el teléfono crea una clave propia en el almacén seguro de Android, que no se puede copiar ni
   exportar.
2. El servidor firma un **certificado** de esa clave: persona y fecha de caducidad.
3. El teléfono genera el QR **sin conexión**, firmando el identificador de la persona, la fecha y hora y un número
   aleatorio. **Se renueva cada pocos segundos.**
4. El teléfono que escanea comprueba **sin conexión** la firma del servidor sobre el certificado (con la clave
   pública del servidor guardada al sincronizar) y la firma del QR.
5. La tarjeta de la persona sale de la lista de trabajadores de la Entidad guardada al sincronizar: **el QR no
   lleva datos personales**.
6. Sin conexión, las subidas y las altas se guardan en el teléfono y se envían al recuperarla.

**Para que no se pueda copiar ni reutilizar**
- La pantalla del QR **no admite capturas ni grabación** de pantalla.
- Una foto de la pantalla deja de valer en segundos.
- Una copia de la app en otro teléfono no tiene la clave.
- Cada código es de **un solo uso**: el teléfono que escanea no acepta dos veces el mismo, y el servidor descarta
  los repetidos al sincronizar.
- Diferencia de hora admitida entre los dos teléfonos: **±2 minutos**.

## 11.9 QR impreso para quien no tiene teléfono

> **Eliminado por §11.19 (06/11/2026, pendiente de implementar).**

- Al registrar a alguien, el Administrador indica **si tiene teléfono**.
- **Sin teléfono:** el sistema genera un **QR fijo**, que **no caduca**, se puede **imprimir** y se puede
  **compartir** con la lista de Android (WhatsApp, Telegram, Bluetooth…).
- **Un único QR por persona que no cambia nunca**: sirve en todas sus Entidades sin reimprimirlo.
- **Usos:** los mismos que el QR del trabajador (§11.8): subir a la guagua y que un jefe le dé de alta o le
  **cambie de itinerario y parada**.
- **Funciona sin conexión.** El código solo lleva el identificador de la persona y la firma del servidor, sin datos
  personales. Quien escanea con MiRuta ve la tarjeta de la persona.
- **Tarjeta impresa:** el QR y, impresos al lado, solo **nombres, apellidos y sexo**.
- **La foto no es obligatoria.** Si tiene foto, se muestra al escanear para comparar; si no, se compara con el
  nombre.
- **Quién lo ve, lo reimprime y lo anula:** el Administrador y el Jefe de su itinerario.
- **Protección ante copias** (una fotocopia funciona igual que el original):
  - se puede **anular y generar uno nuevo** en cualquier momento; sin conexión, el teléfono que escanea se entera al
    sincronizar;
  - **una sola subida por trayecto**: si el mismo QR se usa dos veces en el mismo viaje, se avisa.
- **Cuenta:** también se le crea usuario y contraseña, propuestos por el sistema. Cuando entra por primera vez en la
  app, su QR impreso **se anula** y pasa a usar el QR que cambia cada pocos segundos.
- **Alta en otra Entidad:** la registra el **Administrador** (§11.5).

## 11.10 Pantalla de Inicio y tarjetas modelo

**Imagen por defecto:** cuando no se ha subido imagen, se muestra un **ícono**.

**Campos nuevos de imagen** (opcionales): foto de los **hijos**, imagen de la **Entidad**, del **itinerario** y de
la **parada**.

**Pantalla de Inicio**, de arriba abajo, con un título pequeño encima de cada grupo:

| Grupo | Tarjeta |
|---|---|
| (sin título) | **Usuario** (§11.3) |
| Hijos | Una por hijo con derecho. **Foto a la derecha**. Línea 1: nombres y apellidos. Línea 2: `Nacimiento 20/01/20`. Línea 3: `Derecho 20/01/30`. |
| Entidad | **Entidad elegida.** Imagen a la izquierda. Línea 1: abreviatura. Línea 2: nombre. Línea 3: `50 trabajadores`. Sin Entidad: tarjeta «Sin Entidad», que al tocarla abre la solicitud. |
| Itinerario y parada | De la Entidad elegida. Las dos imágenes juntas a la izquierda (itinerario y parada). Línea 1: nombre del itinerario. Línea 2: `calle • punto de referencia`. Línea 3: `50 trabajadores` (del itinerario). Sin itinerario: tarjeta «Sin itinerario», que al tocarla abre la solicitud de itinerario y parada. |
| Roles | De la Entidad elegida. **Siempre primero la tarjeta «Trabajador»** (línea 2: abreviatura de la Entidad); después una por cada rol aprobado, con su ícono. Línea 1: el rol. Línea 2: **Jefe de itinerario** → nombre de su itinerario; **Jefe de Transporte** y **Chofer** → abreviatura de la Entidad. |
| Viajes | De la Entidad elegida: los planificados y los que están en curso (tarjeta de viaje actual). |

- **Elegir la Entidad:** se toca la tarjeta de la Entidad y se abre la lista de sus Entidades. Al final de la lista:
  **«Solicitar entrar en otra Entidad»** y **«Darme de baja de esta Entidad»**. La app recuerda la última elegida.
  Elegir solo cambia lo que se ve: la persona sigue activa en todas.
- **Hijos:** son de la persona; se muestran siempre, sea cual sea la Entidad elegida. Cuando un hijo pierde el
  derecho por edad, **deja de mostrarse**.
- **«Trabajador» no es un rol que se solicite:** es la condición de quien pertenece a una Entidad. Sin Entidad no
  hay tarjeta «Trabajador».
- **Botones de Inicio**, debajo de la tarjeta del usuario, con **ícono y una sola palabra** debajo:
  **Perfil**, **Hijos**, **Entidades**, **Itinerario**, **Roles** y **Viajes**. Cada uno lleva a su pantalla
  (§11.18).
- **Al tocar las tarjetas de Inicio:**
  - **usuario** → pantalla **Perfil**;
  - **un hijo** → formulario de **ese hijo**;
  - **Entidad** → **selector de Entidad**;
  - **itinerario y parada** → pantalla **Itinerario y parada**;
  - **un rol** → pantalla **Roles**;
  - **un viaje** → **detalle de ese viaje**.
- **Barra inferior sin «Solicitudes»**: queda Inicio, Viajes, Mensajes y Más. Las solicitudes se hacen desde
  las tarjetas.
- **Tarjetas modelo:** estas tarjetas son el modelo para toda la app. Cuando se mencione la tarjeta de un usuario,
  hijo, Entidad, itinerario y parada, rol o viaje, se usa esta forma.

## 11.11 Hijos

- **Se eliminan las solicitudes de hijos** (`child_addition` y `child_removal`), con su aprobación por los jefes.
- **Los padres añaden, corrigen y quitan a sus hijos directamente**, cuando quieran, desde la tarjeta de hijos en
  Inicio o desde Mi perfil.
- **Se identifican por su carné de identidad**: nombres, apellidos y carné. La fecha de nacimiento y el sexo salen
  del carné.
- **Un mismo niño puede tenerlo declarado más de una persona** (sus padres). Si ya está registrado, la app avisa de
  que ya está declarado y se lo asigna igualmente.
- **El sistema verifica el derecho** al guardar, con la regla de siempre: hasta el 31 de agosto siguiente al
  cumpleaños en que alcanza `child_max_age`. Si no tiene derecho, no se deja añadir. Cuando lo pierde, deja de
  mostrarse.
- **En la planificación no se espera a ningún niño**: los pasajeros esperados son solo trabajadores y la ocupación
  prevista no suma niños.
- **Al subir**, se marca **qué hijos suben** con ese trabajador. Cada niño **cuenta una sola vez**, en el viaje en
  que sube el padre que lo lleva, aunque lo tengan declarado los dos padres.
- **El sistema mantiene las estadísticas** de los niños: declarados con derecho y los que viajan realmente.

## 11.12 Ausencias sin aprobación

- **Las ausencias no llevan aprobación**: las **declara la propia persona** cuando lo necesite, con su tipo y
  fechas, o indefinida. Cambia lo que había (aprobación del Jefe de su itinerario o del Jefe de Transporte).
- Se declaran para **no perder el derecho a viajar**: durante la ausencia **no cuenta como pasajero esperado** y se
  **pausa la baja automática por inactividad**.

## 11.13 El Administrador también puede ser trabajador

- El Administrador se registra como cualquiera, con su carné, y queda **sin Entidad**.
- Cuando ya existen Entidades, puede **entrar en las que quiera sin solicitud ni aprobación**.
- Desde ese momento, en esas Entidades es un trabajador más: tarjeta **Trabajador** en Roles, itinerario y parada,
  hijos, QR y viajes, y **cuenta** en sus trabajadores y estadísticas.
- **Dónde:** botón **«Unirme a una Entidad»** en Inicio, junto a los otros botones del final de la pantalla
  (Añadir hijo, Solicitar rol). Abre un formulario con la abreviatura de la Entidad.
- **Sigue siendo Administrador**, con todos sus permisos sobre todas las Entidades.

## 11.14 Servidor y conexión

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

## 11.15 Quién hace qué (configuración de partida)

Es el reparto **con el que arranca la app**. Los roles se pueden editar después (§11.16).

**Jefe de Transporte:** solo **aprueba a los choferes**, **gestiona los vehículos** y **planifica los viajes** de su
Entidad.

| Tarea | Quién |
|---|---|
| Aprobar la entrada en una Entidad | Administrador |
| Aprobar itinerario y parada | Jefe de ese itinerario y Administrador |
| Aprobar el rol de Chofer | Jefe de Transporte de la Entidad y Administrador |
| Aprobar el rol de Jefe de itinerario | Administrador |
| Aprobar el rol de Jefe de Transporte | Administrador |
| Crear y editar itinerarios y paradas (y ordenar sus paradas) | Administrador |
| Registrar trabajadores (también sin teléfono) | Administrador |
| Alta directa en un itinerario con el QR | Administrador (por ahora) |
| Ver el carné | El propio trabajador; Administrador; Jefe de itinerario (miembros de su itinerario y quienes solicitan entrar) |
| Ver, reimprimir y anular el QR impreso | Administrador y Jefe de su itinerario |
| Ajustes de la Entidad | Administrador |
| Gestionar vehículos | Jefe de Transporte y Administrador |
| Planificar viajes | Jefe de Transporte (toda su Entidad), Jefe de itinerario (su itinerario) y Administrador |
| Escanear la subida | Chofer y Jefe de itinerario |

**Asignar y quitar directamente**, sin solicitud:

| Quién | Qué |
|---|---|
| Administrador | Todo: Entidad, itinerario y parada, y los roles de Chofer, Jefe de itinerario y Jefe de Transporte |
| Jefe de Transporte | Solo el rol de Chofer en su Entidad |
| Jefe de itinerario | Nada directamente: solo aprueba las solicitudes de su itinerario |


### El Administrador

«Gestionar» significa **crear, consultar, actualizar y eliminar**. El Administrador gestiona:

- choferes;
- vehículos;
- viajes;
- trabajadores y sus hijos;
- itinerarios;
- paradas;
- Entidades;
- tipos de ausencia;
- la relación trabajador – itinerario – ausencia;
- la relación trabajador – Entidad;
- la relación trabajador – Entidad – itinerario – parada;
- la configuración global de la app;
- la configuración por Entidad;
- la configuración por itinerario y parada;
- la configuración por trabajador;
- los roles;
- la relación trabajador – Entidad – roles.

## 11.16 Roles configurables

- **La tabla de operaciones es fija**: viene con la app y nadie la puede editar, solo consultar.
- **Un rol es un conjunto de operaciones**, cada una con su **ámbito**:

  | Ámbito | Significa |
  |---|---|
  | Propio | Solo sus datos (su cuenta, sus hijos, sus ausencias) |
  | Su itinerario | El itinerario del que es jefe o miembro |
  | Su Entidad | La Entidad en la que tiene ese rol |
  | Todas | Toda la app |

- **El Administrador crea, edita y elimina roles**, les pone nombre y marca sus operaciones y ámbitos.
  - **Chofer, Jefe de itinerario y Jefe de Transporte** son roles de partida (configurados como en §11.15),
    **editables**.
  - Se puede **eliminar un rol aunque lo tengan personas asignadas**: lo pierden en ese momento y reciben el
    aviso de rol quitado.
- **El Administrador es un rol fijo**: todas las operaciones con ámbito «Todas»; no se puede editar ni eliminar;
  siempre debe haber al menos una persona con ese rol.
- **Cada rol tiene además:**
  - si **se puede solicitar** o solo lo asigna quien tenga permiso;
  - **qué roles aprueban sus solicitudes** (por ejemplo, Chofer → Jefe de Transporte de esa Entidad y
    Administrador).
- **Asignación por Entidad:** los roles se asignan a una persona **en una Entidad**. Si el rol actúa sobre «su
  itinerario», quien lo asigna elige el itinerario. Un **Jefe de itinerario lo es de un solo itinerario en cada
  Entidad**.
- **Rol por defecto:** el Administrador elige qué rol se asigna automáticamente **cada vez que se aprueba la
  entrada de una persona en una Entidad** (por ejemplo, «Trabajador»).
- **Los trabajadores solicitan** los roles que se pueden solicitar; los aprueban los roles indicados.

### Tabla de operaciones (fija)

| Grupo | Operación | Ámbitos posibles |
|---|---|---|
| Cuenta propia | Ver y editar mi perfil, mi foto y mi contraseña | Propio |
| | Ver mi QR | Propio |
| | Solicitar entrar en una Entidad / darme de baja | Propio |
| | Solicitar itinerario y parada / darme de baja | Propio |
| | Solicitar un rol / renunciar a un rol | Propio |
| | Declarar y editar mis ausencias | Propio |
| | Editar mis ajustes | Propio |
| Trabajadores | Consultar trabajadores | Su itinerario, Su Entidad, Todas |
| | Registrar trabajadores (con o sin teléfono) | Su Entidad, Todas |
| | Editar los datos de un trabajador | Su itinerario, Su Entidad, Todas |
| | Desactivar y reactivar trabajadores | Su Entidad, Todas |
| | Eliminar trabajadores | Todas |
| | Ver el carné | Su itinerario, Su Entidad, Todas |
| | Ver, reimprimir y anular el QR impreso | Su itinerario, Su Entidad, Todas |
| Hijos | Consultar hijos | Propio, Su itinerario, Su Entidad, Todas |
| | Añadir, editar y quitar hijos | Propio, Todas |
| Entidades | Consultar Entidades | Su Entidad, Todas |
| | Crear, editar y eliminar Entidades | Todas |
| | Aprobar o rechazar la entrada en una Entidad | Su Entidad, Todas |
| | Añadir o quitar a alguien de una Entidad directamente | Su Entidad, Todas |
| Itinerarios y paradas | Consultar itinerarios y paradas | Su itinerario, Su Entidad, Todas |
| | Crear, editar y eliminar itinerarios | Su Entidad, Todas |
| | Crear, editar y eliminar paradas | Su Entidad, Todas |
| | Ordenar las paradas de un itinerario | Su itinerario, Su Entidad, Todas |
| | Marcar el recorrido de referencia | Su itinerario, Su Entidad, Todas |
| Miembros del itinerario | Aprobar o rechazar solicitudes de itinerario y parada | Su itinerario, Su Entidad, Todas |
| | Asignar o quitar itinerario y parada directamente | Su itinerario, Su Entidad, Todas |
| | Alta en un itinerario escaneando el QR | Su itinerario, Su Entidad, Todas |
| Roles | Consultar roles y la tabla de operaciones | Todas |
| | Crear, editar y eliminar roles | Todas |
| | Elegir el rol por defecto | Todas |
| | Asignar o quitar roles directamente | Su Entidad, Todas |
| | Aprobar o rechazar solicitudes de rol | Su Entidad, Todas |
| Vehículos | Consultar vehículos | Su Entidad, Todas |
| | Crear, editar y eliminar vehículos | Su Entidad, Todas |
| | Asignar el chofer habitual de un vehículo | Su Entidad, Todas |
| Viajes | Consultar viajes | Propio, Su itinerario, Su Entidad, Todas |
| | Planificar viajes (crear y copiar a un rango de fechas) | Su itinerario, Su Entidad, Todas |
| | Editar viajes (vehículo, chofer, horas) | Su itinerario, Su Entidad, Todas |
| | Confirmar y cancelar viajes | Su itinerario, Su Entidad, Todas |
| | Eliminar viajes | Su Entidad, Todas |
| | Marcar un viaje como realizado | Su itinerario, Su Entidad, Todas |
| Recorrido | Conducir: iniciar y terminar el recorrido y enviar la ubicación | Su Entidad, Todas |
| | Ver el recorrido en tiempo real | Propio, Su itinerario, Su Entidad, Todas |
| | Escanear la subida | Su itinerario, Su Entidad, Todas |
| | Dejar subir a alguien de otro itinerario o Entidad | Su itinerario, Su Entidad, Todas |
| | Corregir los pasajeros de un viaje | Su itinerario, Su Entidad, Todas |
| Ausencias | Consultar ausencias de otros | Su itinerario, Su Entidad, Todas |
| | Declarar, editar y quitar ausencias de otros | Su itinerario, Su Entidad, Todas |
| | Crear, editar y eliminar tipos de ausencia | Todas |
| Configuración | Ajustes de la app | Todas |
| | Ajustes de la Entidad | Su Entidad, Todas |
| | Ajustes por itinerario y parada | Su itinerario, Su Entidad, Todas |
| | Ajustes de un trabajador | Su itinerario, Su Entidad, Todas |
| Nomencladores | Tipos de vehículo y motivos de conversación | Todas |
| Mensajes | Chat del viaje | Propio |
| | Recibir y responder conversaciones dirigidas a un rol | Su itinerario, Su Entidad, Todas |
| | Borrar mensajes de otros | Su itinerario, Su Entidad, Todas |
| Estadísticas | Consultar estadísticas | Su itinerario, Su Entidad, Todas |
| Olvidé algo | Consultar, aprobar, rechazar y bloquear teléfonos | Todas |
| Actualizaciones de la app | Publicar y retirar versiones | Todas |
| Mantenimiento del servidor | Ver el estado y ejecutar órdenes | Todas |

## 11.17 Ajustes por itinerario y parada

- Nuevo nivel de configuración **por itinerario** y **por parada dentro de un itinerario**.
- Se pueden cambiar en ese nivel **todos los ajustes que tengan sentido**: los del viaje y el recorrido por
  itinerario (tolerancia de atraso, desvíos, avisos, retención del chat del viaje…) y los de la parada por parada
  (tiempo mínimo de parada, velocidad de paso…).
- **Gana el más concreto:** trabajador → parada del itinerario → itinerario → Entidad → app.

## 11.18 Pantallas interiores y forma de uso

Todas las pantallas tienen la **misma forma**; lo que cambia son los datos: título, selector de Entidad arriba si
hace falta, tarjetas, el botón **Acciones** y, siempre abajo, la **barra principal** (Inicio, Viajes, Mensajes y
Más), también en las pantallas interiores.

**Selector de Entidad:** en todas las pantallas es como el de Inicio, la **tarjeta de la Entidad con ↕**. Al
tocarla se abre «Mis Entidades» para elegir, con ✓ en la elegida.

**Tarjetas y acciones**
- **Las tarjetas no llevan botones dentro.**
- **Tocar una tarjeta** abre directamente su formulario de edición.
- **Mantenerla pulsada** entra en **modo selección**: queda marcada con ✓ y cada toque marca o desmarca otras,
  así que se pueden seleccionar varias. Arriba: «N seleccionadas» y ✕ para salir.
- **Botón «Acciones»**, naranja, abajo a la derecha, encima de la barra principal. Al tocarlo se despliega un
  **menú flotante** encima del botón, a la derecha, con la lista de acciones (ícono y texto); el botón cambia a ✕
  para cerrarlo. Tiene **todas las acciones de la pantalla**:
  - las que no necesitan selección (Crear, Agregar, Solicitar, Declarar, Guardar…) están **siempre activas**;
  - **Editar** se activa con **una** tarjeta seleccionada y abre el mismo formulario que tocarla;
  - **Desactivar, Eliminar, Darme de baja, Cancelar solicitud…** se activan con **una o varias** seleccionadas
    y piden confirmación. Eliminar va en rojo;
  - las que no se pueden usar en ese momento salen **en gris**.

**Inicio:** mantiene, de momento, sus **seis botones** (Perfil, Hijos, Entidades, Itinerario, Roles y Viajes),
3 por fila, centrados y del mismo tamaño, con ícono y una palabra.

**Formulario de un hijo:** sus datos editables, **quién más lo tiene declarado** (solo aquí, no en la tarjeta) y la
opción de **desactivarlo** (o reactivarlo).

**Pantallas**

| Pantalla | Selector de Entidad | Contenido | Acciones |
|---|---|---|---|
| **Perfil** | No | Foto; nombres y apellidos, carné y usuario editables; sexo y fecha de nacimiento de solo lectura (salen del carné) | Guardar perfil, Cambiar contraseña |
| **Formulario de un hijo** | No | Foto; nombres, apellidos y carné editables; sexo, nacimiento y derecho a viajar de solo lectura; quién más lo tiene declarado | Guardar, Desactivar / Reactivar, Eliminar |
| **Hijos** | No | Con derecho a viajar; Desactivados (en gris). Las tarjetas mantienen sus tres líneas. | Crear (hijo nuevo), Agregar (ya registrado, por carné), Editar, Desactivar / Reactivar, Eliminar |
| **Entidades** | No | Mis Entidades; Solicitudes pendientes | Solicitar (entrar en una Entidad), Darme de baja, Cancelar solicitud |
| **Itinerario y parada** | Sí | Mi itinerario y parada; Ausencias | Solicitar (otro itinerario y parada), Darme de baja, Declarar (ausencia), Editar, Eliminar |
| **Roles** | Sí | Mis roles (Trabajador siempre); Solicitudes pendientes | Solicitar (un rol), Darme de baja (no aplica a Trabajador), Cancelar solicitud |
| **Viajes** | Sí | En curso; Confirmados | Sin botón Acciones (tocar un viaje abre su detalle) |

## 11.19 QR simplificado: solo para asignar itinerario (06/11/2026, pendiente de implementar)

Sustituye a §11.8 y §11.9.

- **Cada persona tiene un único QR**, que no se puede imprimir, copiar ni reutilizar. Se mantiene cómo se genera:
  clave guardada en el teléfono (Android Keystore) certificada por el servidor, código que cambia cada 15 segundos,
  de un solo uso y con la pantalla sin capturas ni grabación.
- **Su único uso es asignar itinerario y parada sin solicitud.**
  - **Jefe de itinerario:** asigna **su propio itinerario** (el que dirige), solo a personas registradas en **su misma
    Entidad**, que es la de ese itinerario.
  - **Administrador:** asigna **cualquier itinerario de cualquier Entidad**. Si la persona no pertenecía a esa
    Entidad, **queda añadida automáticamente**, ya aprobada, con el rol por defecto.
  - **La parada la elige quien escanea** en ese momento, de las paradas del itinerario.
  - Si la persona ya tenía otro itinerario en esa Entidad, **se le cambia y pierde el anterior**; no pierde sus
    jefaturas.
- **Funciona con y sin conexión.** Sin conexión, el teléfono de quien escanea comprueba el QR, guarda la asignación y
  la envía al servidor al recuperar la conexión; hasta entonces la persona no ve su nuevo itinerario y parada.
- **Cambio de parada:** después, la persona puede **cambiarse de parada directamente**, sin solicitud, entre las
  paradas de su itinerario.
- **Se elimina en esta versión:**
  - subir a la guagua con el QR (escaneo del chofer, marcar hijos al escanear, dejar subir a quien es de fuera,
    corrección de pasajeros con QR, aviso de QR usado dos veces);
  - la lista y la cola de escaneos de **subida** sin conexión;
  - el **QR impreso** (compartir, imprimir, anular) y el dato **«¿tiene teléfono?»** al registrar;
  - las estadísticas que dependían del escaneo de subida (quienes viajan fuera de su itinerario o Entidad).


## 11.20 Gestión de Entidades, itinerarios, paradas y nomencladores (06/11/2026, pendiente de implementar)

Mismo diseño que el resto (§11.18): selector de Entidad, tarjetas, selección múltiple y menú «Acciones».

**Quién puede qué**

| | Entidades | Itinerarios | Paradas | Nomencladores |
|---|---|---|---|---|
| **Administrador** | Todo (crear, consultar, editar, desactivar, eliminar) | Todo, en cualquier Entidad | Todo, en cualquier Entidad | Todo |
| **Jefe de itinerario** | — | Ver los de las Entidades donde está registrado | **Todo sobre las paradas de su itinerario** (crear, editar, quitar y reordenar); ver las de sus Entidades | — |
| **Trabajador** | — | Ver los de las Entidades donde está registrado | Ver las de sus Entidades | — |

**Pantallas**
- **Gestión:** «Entidades y recorridos» (Entidades, Itinerarios, Paradas) y «Nomencladores» (Tipos de vehículo,
  Tipos de ausencia, Motivos de conversación).
- **Entidades:** activadas y desactivadas. Acciones: Crear Entidad; Editar, Desactivar/Activar, Eliminar.
- **Formulario de Entidad:** imagen, abreviatura, nombre, número, descripción, observación. Acciones: Guardar,
  Desactivar, Eliminar.
- **Itinerarios** (selector de Entidad): Acciones: Crear itinerario; Editar, Desactivar, Eliminar.
- **Formulario de itinerario:** imagen, nombre, descripción y sus **paradas numeradas en orden** (la 1.ª es la salida y
  la última el regreso). Acciones: Guardar, Añadir parada existente, Crear parada nueva, Ordenar paradas, Quitar
  parada, Eliminar itinerario.
- **Paradas** (selector de Entidad): cada una dice en qué itinerarios está o «Sin itinerario». Acciones: Crear parada;
  Editar, Eliminar.
- **Formulario de parada:** imagen, punto de referencia, calle, entrecalles y **mapa** para situarla; en qué itinerarios
  está y en qué posición. Acciones: Guardar, Eliminar.
- **Nomencladores:** activos y desactivados, con cuántas veces se usa cada uno. Acciones: Crear; Editar, Desactivar,
  Eliminar (también varios a la vez).
- **Jefe de itinerario:** en Paradas ve las de **su itinerario** (numeradas) y, solo para consultar, las de los otros
  itinerarios de su Entidad. Acciones sobre su itinerario: **crear, editar, quitar y reordenar paradas**.
- **Trabajador:** Itinerarios y Paradas de sus Entidades, solo para consultar, sin botón «Acciones».

**Se elimina todo lo del chofer:** el rol Chofer, el chofer habitual de los vehículos y el chofer de los viajes,
conducir y compartir la ubicación como chofer, las solicitudes y pantallas del chofer. **Los vehículos y el
nomenclador Tipos de vehículo se mantienen por ahora.**

## 11.21 Gestión unificada «Entidades y personas» (06/11/2026, pendiente de implementar)

- **Una pantalla** con tres **selectores en cascada** arriba: **Entidad → Itinerario → Parada**; cada uno filtra al
  siguiente y cada uno tiene la opción **«Todos/Todas»**. Debajo, las **personas** que cumplen el filtro.
- **Tarjetas de los selectores:** tocar la tarjeta abre el **formulario de edición** de esa Entidad, itinerario o
  parada; el botón naranja **↕** abre la lista para elegir (con «Todos» primero y ✓ en el elegido).
- **Acciones** según lo elegido y seleccionado: Crear Entidad, Crear itinerario en <Entidad>, Crear parada en
  <itinerario>, Registrar persona en <Entidad>; con personas seleccionadas: Editar (una), Asignar itinerario y parada,
  Asignar rol, Desactivar, Dar de baja de la Entidad; y **«Listados y nomencladores…»**.
- **Listados y nomencladores:** Entidades, Itinerarios, Paradas, Personas, Tipos de vehículo, Tipos de ausencia y
  Motivos de conversación; cada uno abre su **listado independiente** con su CRUD en el menú Acciones (§11.20).

**Quién la ve:** **todo el mundo**.
- **Trabajador:** el selector de Entidad solo ofrece **las Entidades donde está registrado**. Ve **todos los
  itinerarios, paradas y personas** de esas Entidades. Puede abrir los formularios tocando las tarjetas, pero **solo
  para consultar**: no puede crear, editar ni eliminar (sin acciones de cambio). El carné de las personas no se le
  muestra (§11.2).
- **Jefe de itinerario:** igual que el trabajador y, además, todo sobre las paradas de su itinerario (§11.20).
- **Administrador:** todas las Entidades y todas las acciones.

**Regla para toda la app:** **tocar una tarjeta abre su edición** y, además, **al marcarla** (selección) aparece en
Acciones la acción **Editar**, que abre el mismo formulario. Vale también para las tarjetas de los selectores.

## 11.22 Pantalla «Gestión» en la barra principal (06/11/2026, pendiente de implementar)

- La pantalla unificada (§11.21) se llama **Gestión** y va en la **barra principal, justo después de Inicio**:
  Inicio, Gestión, Viajes, Mensajes, Más.
- **Trabajador:** en Acciones, **Solicitar entrar en una Entidad**, **Solicitar itinerario y parada** y los listados
  de consulta. Sus formularios son de solo consulta.
- **Solicitudes:** ver las solicitudes, aprobarlas o denegarlas (Jefe de itinerario y Administrador) y que el
  trabajador vea las suyas y su estado se hará **en otra pantalla más adelante**.
- **Motivos de denegación:** son un **nomenclador** por tipo de solicitud (entrada en Entidad, itinerario y parada,
  rol). Se gestionan desde «Listados y nomencladores».
- **Todas las eliminaciones de la app piden confirmación**, explicando qué se borra y qué se conserva.
- **Al eliminar:**
  - **una Entidad:** se eliminan sus itinerarios y paradas; las personas **no** se eliminan: quedan sin esa Entidad;
  - **un itinerario:** se eliminan sus paradas; las personas quedan **sin itinerario y sin parada**;
  - **una parada:** las personas quedan **sin parada** (conservan su itinerario y eligen otra parada; pueden
    hacerlo ellas mismas, porque el cambio de parada es directo);
  - **una persona:** sin consecuencias para lo demás.
- **«Itinerario y parada van juntos» es una regla de interfaz:** una parada siempre se muestra dentro del itinerario
  del que forma parte. En los datos, una persona **sí puede tener itinerario sin parada** (por ejemplo, tras eliminar
  su parada).
- **El Jefe de itinerario también ve la pantalla Gestión:** igual que el trabajador (sus Entidades, consulta de
  itinerarios, paradas y personas, y las solicitudes) y, además, en Acciones, **crear, editar, quitar y reordenar las
  paradas de su itinerario**.


## 11.23 Cuatro pantallas de gestión (06/11/2026, pendiente de implementar; sustituye a §11.21 y §11.22 en lo que cambie)

| Pantalla | Arriba | Listado | Acciones (además de «Ir a» las otras tres) |
|---|---|---|---|
| **Gestionar Trabajadores** | Selectores Entidad → Itinerario → Parada (con «Todos») | Trabajadores | CRUD de trabajadores (Registrar, Editar, Desactivar, Eliminar) |
| **Gestionar Entidades** | — | Entidades; solicitudes | CRUD de Entidades; **Crear itinerario** en la Entidad; solicitar / resolver solicitudes |
| **Gestionar Itinerarios** | Selector de Entidad | Itinerarios; solicitudes | CRUD de itinerarios; **Crear parada** en el itinerario; solicitar / resolver solicitudes; darse de baja del itinerario |
| **Gestionar Paradas** | Selectores Entidad → Itinerario | Paradas (numeradas, en orden) | CRUD de paradas (Jefe de su itinerario y Administrador), ordenar, quitar del itinerario; **«Cambiarme a esta parada»** (directo) |

- **Solicitudes** (Entidad e itinerario y parada; la parada se cambia directamente):
  - **Trabajador:** ve **sus solicitudes**, su **estado** y, si se rechazaron, **quién, cuándo y el motivo**; puede
    **cancelar** las pendientes y **eliminar** las suyas.
  - **Jefe de itinerario y Administrador:** ven las solicitudes por resolver de su ámbito; **aprobar** o
    **rechazar eligiendo el motivo** del nomenclador (más una observación opcional). No pueden eliminarlas: las pueden
    **ocultar** y **mostrar las ocultas**.
- La pestaña **Gestión** de la barra principal abre estas pantallas (se navega entre ellas desde Acciones).
- La pestaña **Gestión** abre primero **Gestionar Trabajadores**.
- **Textos del menú Acciones:**
  - navegación: **«Gestionar Trabajadores»**, **«Gestionar Entidades»**, **«Gestionar Itinerarios»**,
    **«Gestionar Paradas»** (sin «Ir a»);
  - solicitudes: **«Solicitar Entidad»** y **«Solicitar Itinerario»**;
  - crear: **«Crear <objeto>»**, sin nombrar la Entidad o el itinerario padre («Crear itinerario», «Crear parada»);
  - darse de baja: **«Salir de <objeto>»** («Salir de la Entidad», «Salir del itinerario»).
- **Gestionar Paradas:** las tarjetas llevan el **ícono de arrastrar** para ordenarlas (Jefe de su itinerario y
  Administrador; el trabajador no lo ve); desaparece «Ordenar paradas» del menú. Nueva acción **«Cambiar de
  itinerario»** para las paradas marcadas.
- **Roles:** los trabajadores **ya no solicitan roles**. El **Administrador asigna directamente** el rol de Jefe de
  itinerario («Asignar Jefe de itinerario» en Gestionar Trabajadores).
- **Se elimina la pantalla Roles** del trabajador (y su botón en Inicio): sus roles siguen viéndose en Inicio.
- El ícono de **Gestión** en la barra principal es un **engranaje**.
- **Gestionar Itinerarios** muestra también las **personas** (sin CRUD de personas). Con personas marcadas, en
  Acciones: **«Asignar Jefe de itinerario»** y **«Cambiar de itinerario»**.
- **Gestionar Paradas** muestra también las **personas** (sin CRUD de personas). Con personas marcadas, en Acciones:
  **«Cambiar de parada»**.
- **Itinerario y parada dejan de ser obligatorios.** Una persona puede **no tener itinerario**; y si tiene
  itinerario, puede **no tener parada**. Al ponerla en un itinerario se le ofrece elegir parada, pero **no es
  obligatorio**.
- **Todos los selectores de itinerario** incluyen la opción **«Sin itinerario»** (personas sin itinerario) y **todos
  los selectores de parada** la opción **«Sin parada»** (personas del itinerario sin parada), además de «Todos».

### Estructura común de las cuatro gestiones (06/11/2026)

- **Todas** llevan arriba los selectores **Entidad → Itinerario → Parada** (con «Todos», «Sin itinerario» y «Sin
  parada») y al final las **tarjetas de personas** que cumplen el filtro.
- Entre los selectores y las personas va lo propio de cada gestión:

  | Pantalla | Tarjetas propias | Además |
  |---|---|---|
  | Gestionar Trabajadores | — (solo personas) | CRUD de trabajadores |
  | Gestionar Entidades | Entidades | CRUD de Entidades, crear itinerario, solicitudes de Entidad |
  | Gestionar Itinerarios | Itinerarios | CRUD de itinerarios, crear parada, solicitudes de itinerario |
  | Gestionar Paradas | Paradas (arrastrar para ordenar) | CRUD de paradas |

- **Movimientos** de personas (en Acciones, con personas marcadas, en todas las gestiones donde tengan sentido):
  **Asignar rol** (Jefe de itinerario), **Cambiar de Entidad**, **Cambiar de itinerario** (con parada opcional) y
  **Cambiar de parada**.
- Las **solicitudes** se mantienen donde proceden (Entidades e Itinerarios), como en §11.23.

### Tarjetas y selectores en toda la app (06/11/2026; sustituye lo dicho antes sobre los selectores)

- **Tocar una tarjeta** abre el **formulario de consulta o edición** de ese objeto.
- **Mantener el dedo en una tarjeta** la **marca** para realizar acciones (selección múltiple).
- **Tocar un selector** solo **despliega** su lista para elegir (no abre formularios).
- **Los selectores nunca se marcan**: mantener el dedo en ellos no hace nada distinto de tocarlos.
- Por tanto, el botón ↕ deja de ser necesario: todo el selector despliega la lista.
- **Selectores:** llevan el ícono de flechas **↕** para que se reconozcan como selectores.

### Menú «Acciones» según lo marcado (06/11/2026, toda la app)

- **Sin nada marcado:** acciones generales de la pantalla (crear, solicitar, mostrar ocultas, navegar a otras
  pantallas).
- **Con tarjetas marcadas:** **solo las acciones sobre lo marcado** (Editar —con una—, asignar, cambiar, aprobar,
  rechazar, ocultar, desactivar, eliminar…). Las generales desaparecen hasta desmarcar.
- Ya no se muestran acciones en gris: en cada momento solo aparecen las que se pueden usar.
- **Se marca un solo tipo de tarjeta cada vez** (06/11/2026): al marcar una tarjeta de otro tipo (por ejemplo, una
  persona con paradas marcadas) se desmarcan las anteriores y queda marcada solo la nueva.

## 11.24 Ajustes a la gestión y nueva plataforma PHP (06/11/2026, pendiente de implementar)

- **Activación:** las tablas de **Entidades, itinerarios, paradas y trabajadores** tienen un campo **activación**
  (booleano): `true` = **Activado**, `false` = **Desactivado**. Las acciones «Activar» / «Desactivar» cambian ese
  campo.
- **Lo desactivado en las listas de gestión** (06/11/2026): se muestra **atenuado** (gris claro) solo al
  **Administrador** y al **Jefe de itinerario** (en su ámbito), que pueden volver a activarlo. El **trabajador no lo
  ve**.
- La acción de las solicitudes se llama **«Rechazar»** (sin puntos suspensivos).
- **Solicitudes, para todos los roles:** dos opciones en Acciones, **«Mostrar/Ocultar solicitudes rechazadas»** y
  **«Mostrar/Ocultar solicitudes aprobadas»**. Se **quitan** las opciones anteriores de ocultar una solicitud y
  «Mostrar solicitudes ocultas».
- **Una parada puede pertenecer a varios itinerarios de varias Entidades** (la parada deja de pertenecer a una sola
  Entidad; la relación es solo itinerario–parada).
- **Paradas compartidas** (06/11/2026): el **Jefe de itinerario** puede **editar** una parada de su itinerario
  aunque la usen otros (el cambio se ve en todos); **no puede eliminarla** mientras la use otro itinerario, solo
  **quitarla del suyo**. Eliminarla del todo es del **Administrador**.
- **«Añadir parada existente»** (06/11/2026): ofrece **todas las paradas del sistema**, de cualquier Entidad, con
  **búsqueda por nombre o calle**, para reutilizarlas en vez de repetirlas.
- **Paradas sin itinerario** (06/11/2026): si una parada se queda sin ningún itinerario **se conserva**. Los
  selectores de itinerario tienen la opción **«Sin itinerario»**, que en Gestionar Paradas muestra esas paradas (y,
  como siempre, las personas sin itinerario); el Administrador puede añadirlas a un itinerario o eliminarlas.
- **«Sin Entidad»** (06/11/2026): el selector de Entidad tiene esta opción **solo para el Administrador**; muestra a
  las personas que se quedaron sin Entidad (por ejemplo, al eliminar la suya) para ponerlas en otra con «Cambiar de
  Entidad». El Jefe de itinerario y el trabajador no la ven.
- **Persona sin ninguna Entidad** (06/11/2026): **puede entrar** en la app con acceso limitado: ve su perfil y puede
  **«Solicitar Entidad»**; no ve viajes ni itinerarios hasta que la acepten en una.
- **Persona con Entidad pero sin itinerario** (06/11/2026): **no ve viajes** hasta tener itinerario; puede
  «Solicitar Itinerario» o ser asignada por QR.
- **Persona con itinerario pero sin parada** (06/11/2026): **no ve viajes** hasta tener parada; puede elegirla con
  «Cambiarme a esta parada» en Gestionar Paradas.
- **Avisos en Inicio de lo que falta** (06/11/2026): la pantalla Inicio muestra un aviso con su botón, que
  desaparece en cuanto se resuelve:
  - «Aún no tiene Entidad» → botón **«Solicitar Entidad»**;
  - «Aún no tiene itinerario» → botón **«Solicitar Itinerario»**;
  - «Aún no tiene parada» → botón **«Elegir parada»** (lleva a Gestionar Paradas de su itinerario).
- **Cambiar de Entidad:** además del itinerario, se puede **escoger la parada** (ambos opcionales).
- **Cambiar de parada:** muestra el **itinerario en solo lectura**.
- **Los formularios de consulta y edición no muestran datos relacionados** (lookup), **al menos en esta versión**: por ejemplo, el formulario del
  trabajador no lista sus itinerarios y paradas, el de la parada no lista sus itinerarios y el del itinerario no
  muestra el Jefe de itinerario. Solo los campos propios del objeto.
- **PHP del hospedaje: 8.2.35** (exacta). Se actualiza la tecnología de implementación y de pruebas:
  - **Decisión (06/11/2026): Laravel 12** (`laravel/framework` ^12, exige PHP ^8.2) en lugar de Lumen, que ya no
    publica versiones nuevas (la última, 11.2.0, es de 2024). Laravel 13 no sirve: exige PHP ^8.3.
  - Se mantiene la **misma API JSON:API** (rutas, respuestas y errores) para que la app no cambie por esto.
  - Pruebas con **PHPUnit 11** (la del esqueleto oficial de Laravel 12) y `fakerphp/faker`.
  - `composer.json`: `"php": "^8.2"` y `config.platform.php` = `8.2.35`.
  - El contenedor de pruebas pasa de PHP 7.2 a **PHP 8.2** (imagen oficial `php:8.2`), y el paquete de hospedaje
    (`configuracion.php`, mantenimiento sin cron, `desempaquetar.php`, `diagnostico.php`) y las instrucciones de
    hospedaje y local se adaptan igual.

## 11.25 Misma estructura y acciones completas en las cuatro gestiones (06/11/2026, pendiente de implementar; sustituye lo que cambie de §11.23)

- **Todas las pantallas de gestión** tienen, en este orden: los **4 selectores**, un **separador**, las **tarjetas de
  Entidad**, las **tarjetas de itinerario**, las **tarjetas de parada**, las **tarjetas de personas** y, al final,
  las **solicitudes**.
- Las tarjetas llevan al **formulario de consulta y edición** del objeto, **sin datos relacionados** (lookup).
- **Acciones:** cada gestión incluye las operaciones con **su objeto** y también las **relacionadas con los demás
  objetos**. Ejemplo dado por el usuario, **Gestionar Trabajadores**: registrar, eliminar, activar/desactivar,
  actualizar los datos del trabajador, asignarle o quitarle una Entidad, solicitar Entidad, solicitar itinerario,
  asignarle o cambiarle el itinerario, asignarle o cambiarle la parada.

## 11.26 Una sola pantalla de Gestión (06/11/2026, pendiente de implementar; sustituye a las cuatro gestiones de §11.23 y §11.25)

- La pestaña **Gestión** abre **una única pantalla**; desaparecen «Gestionar Trabajadores / Entidades / Itinerarios /
  Paradas» y la navegación entre ellas.
- **Arriba:** selectores **Entidad → Itinerario → Parada** (con «Todos», «Sin Entidad» —solo Administrador—, «Sin
  itinerario», «Sin parada») y un **campo de búsqueda de personas** (nombre, carné o usuario) en lugar de un cuarto
  selector. Después, un **separador**.
- **Secciones plegables con su cantidad:** Entidades, Itinerarios, Paradas, Personas y Solicitudes. Los selectores
  filtran todas las secciones.
- Las secciones se abren **como las dejó la última vez** (el teléfono recuerda cuáles estaban plegadas); la primera
  vez, todas desplegadas.
- Los selectores se abren con **lo último que eligió** (lo recuerda el teléfono); la primera vez, **su Entidad, su
  itinerario y «Todas las paradas»**.
- Tocar una tarjeta abre su formulario (sin datos relacionados); mantenerla la marca; **un solo tipo marcado** cada
  vez.
- **Marca:** el check va en **color de énfasis (naranja), arriba a la derecha** de cada tarjeta.
- **Con tarjetas marcadas**, el menú Acciones incluye además **«Marcar todo»**, **«Desmarcar todo»** e **«Invertir
  selección»** (sobre las tarjetas de ese tipo).
- **Acciones de un solo objeto** (Editar, «Cambiarme a esta parada», Asignar Jefe de itinerario, etc.) **solo
  aparecen con exactamente una tarjeta marcada**; con varias se ocultan. «Marcar todo», «Desmarcar todo» e «Invertir
  selección» aparecen siempre que haya algo marcado.
- **Menú Acciones sin nada marcado:** Registrar trabajador, Crear Entidad, Crear itinerario, Crear parada, Solicitar
  Entidad, Solicitar Itinerario, Mostrar/Ocultar solicitudes aprobadas, Mostrar/Ocultar solicitudes rechazadas y
  **Nomencladores (solo el Administrador)**.
- **Con marcadas, según el tipo:**
  - Entidades: Editar, Activar/Desactivar, Eliminar, Crear itinerario, Salir de la Entidad.
  - Itinerarios: Editar, Activar/Desactivar, Eliminar, Cambiar de Entidad, Asignar Jefe de itinerario, Crear parada,
    Añadir parada existente, Salir del itinerario.
  - Paradas: Editar, Activar/Desactivar, Eliminar, Añadir a un itinerario, Quitar del itinerario, Cambiarme a esta
    parada.
  - Personas: Editar, Activar/Desactivar, Eliminar, Asignar rol, Cambiar de Entidad, Cambiar de itinerario, Cambiar
    de parada.
  - Solicitudes: Aprobar / Rechazar (Jefe y Administrador); Cancelar / Eliminar las propias (trabajador).
- **Ordenar paradas arrastrando** solo cuando hay un itinerario elegido.
- **Quién ve qué:** el Administrador todo; el Jefe de itinerario todo, actuando solo en su itinerario; el trabajador
  las mismas secciones sin acciones de gestión (solo lo suyo).
- **Nomencladores** (solo Administrador, 06/11/2026): **una sola pantalla** como Gestión, con una **sección plegable
  por nomenclador** y su cantidad (Tipos de vehículo, Tipos de ausencia, Motivos de conversación, Motivos de
  denegación). Tocar abre el formulario; mantener marca; Acciones: Crear, Editar, Activar/Desactivar, Eliminar
  (con las mismas reglas de marcado). *Quedan cosas por definir.*
- **Activar/Desactivar** (06/11/2026): como es un campo de la tabla, **sale del menú Acciones** y queda solo como el
  interruptor **«Activado»** en los **formularios de consulta y edición** (Entidad, itinerario, parada, trabajador y
  nomencladores).
- **Todas las secciones paginadas de 5 en 5** (06/11/2026): Entidades, Itinerarios, Paradas, Personas y
  Solicitudes, con primera / anterior / siguiente / última página y «1–5 de N».
  **Excepción:** con un **itinerario elegido**, sus **paradas no se paginan** (se ven todas, para ordenarlas
  arrastrando).
- **Quién ve qué solicitudes** (06/11/2026):
  - **«Mis solicitudes»**: solo las ve **el propio trabajador** que las hizo.
  - **Estados:** una solicitud está **pendiente** o **resuelta**; las resueltas están **aprobadas** o **rechazadas**.
  - Solicitudes de otros (pendientes y resueltas, aprobadas o rechazadas): el **Jefe de itinerario** ve solo las
    **de su itinerario**; el **Administrador** las ve **todas** (por tanto, las solicitudes de Entidad las resuelve
    el Administrador). Las resueltas se muestran con «Mostrar solicitudes aprobadas» / «Mostrar solicitudes
    rechazadas».
- **Número en la pestaña Gestión** (06/11/2026): para el Jefe de itinerario y el Administrador, la pestaña muestra
  la **cantidad de solicitudes pendientes** que les toca resolver; desaparece cuando no hay ninguna.
- **El trabajador se entera de lo resuelto** (06/11/2026): cuando le aprueban o rechazan una solicitud, la pestaña
  Gestión le muestra un **número** hasta que abre la sección Solicitudes. Si se aprobó, Inicio se actualiza solo (desaparece
  el aviso «Aún no tiene…» correspondiente). Sin mensaje aparte.
- **Buscador** (06/11/2026): busca **solo personas** (nombre, carné o usuario).
- **Gestión sin conexión** (06/11/2026): **solo consulta** de lo último cargado, con el aviso «Sin conexión: datos
  del dd/mm hh:mm»; las acciones que cambian datos se ocultan hasta que vuelva la conexión, **salvo asignar
  itinerario por QR** (que funciona con y sin conexión, §11.19).
- **Dónde está el QR** (06/11/2026): **«Asignar itinerario por QR»** aparece, solo para el **Jefe de itinerario** y
  el **Administrador**, en **dos lugares**: en el **menú Acciones de Gestión sin nada marcado** y como **botón en
  Inicio**. Abre la cámara, se escanea el QR de la persona y se elige la parada.
- **«Mi QR»** (06/11/2026): el trabajador muestra su QR desde **dos lugares**: un **botón «Mi QR» en Inicio**
  (para todos; si no tiene itinerario, junto al aviso «Aún no tiene itinerario») y en **su perfil** (pestaña Más).

## 11.27 El QR sirve para incluir en Entidad, itinerario o parada (06/11/2026, pendiente de implementar; amplía §11.19)

- La acción pasa a llamarse **«Incluir por QR»** (Jefe de itinerario y Administrador; **solo en Acciones de Gestión
  sin nada marcado**, no en Inicio). Tras escanear el QR de la persona se elige **dónde incluirla**:
  - **En una Entidad:** se puede escoger además **itinerario y parada** (opcionales).
  - **En un itinerario:** se puede escoger además **parada** (opcional).
  - **En una parada:** el **itinerario se muestra bloqueado** (solo lectura); al quedar en la parada, la persona
    queda **automáticamente en la Entidad y el itinerario** de esa parada.
- El formulario **indica dónde está ya** la persona: «Ya está en la Entidad …», «Ya está en el itinerario …», «Ya
  está en la parada …».
- **Un único itinerario por Entidad** y **una sola parada por itinerario**: incluir por QR en otro itinerario de la
  misma Entidad **equivale a cambiarle el itinerario**; incluir en otra parada del mismo itinerario **equivale a
  cambiarle la parada**.
- El Jefe de itinerario solo puede incluir en **su itinerario** (y, con ello, en su Entidad); el Administrador en
  cualquiera.
- Funciona con y sin conexión (§11.19).

## 11.28 Botones de Inicio (06/11/2026, pendiente de implementar)

- Inicio tiene solo los botones **Perfil**, **Hijos** y **Mi QR** (para todos).
- Se quitan **Entidades** e **Itinerario** (se gestionan en la pestaña Gestión), **Roles** (pantalla eliminada),
  **Viajes** (ya está en la barra principal) e **Incluir por QR** (queda solo en Acciones de Gestión; sustituye lo
  dicho en «Dónde está el QR»).

## 11.29 Eliminar nomencladores en uso (06/11/2026, pendiente de implementar)

- Un elemento de nomenclador **en uso** (p. ej. un motivo con el que ya se rechazaron solicitudes o un tipo de
  vehículo con vehículos registrados) **no se puede eliminar**: la app avisa de que está en uso y **propone
  desactivarlo** (interruptor «Activado» del formulario). Los que no están en uso se eliminan tras confirmar.

## 11.30 Tres roles fijos (06/11/2026, pendiente de implementar; sustituye a §11.16)

- Desaparecen los **roles configurables** (tablas de roles, permisos por operación y aprobadores, y su pantalla de
  configuración). Quedan **tres roles fijos**, con sus permisos definidos en el código:
  - **Administrador:** todo, en todas las Entidades (incluye Nomencladores).
  - **Jefe de itinerario:** gestiona **su itinerario** (paradas, personas, solicitudes de su itinerario, Incluir por
    QR) y ve sus Entidades.
  - **Trabajador:** consulta; solicita Entidad e itinerario, sale de ellos, se cambia de parada y gestiona sus
    propias solicitudes.
- El Administrador **asigna directamente** el rol de Jefe de itinerario (no hay solicitudes de rol).
- En los **Motivos de conversación**, el destinatario «Un rol» elige entre estos roles fijos (o el desarrollador).
- **Varios Jefes por itinerario** (06/11/2026): un itinerario puede tener **más de un Jefe**, todos con los mismos
  permisos sobre él; cada persona sigue siendo Jefe de **un solo itinerario**.
- **El Jefe viaja en su itinerario** (06/11/2026): al asignarle el rol de Jefe de un itinerario **se le pone en ese
  itinerario** si no lo estaba (avisando de que le cambia el itinerario); si después se le cambia a otro itinerario
  (o se le saca del suyo), **pierde el rol de Jefe**, también con aviso previo.
- **Solo el Administrador** asigna y quita el rol de Jefe de itinerario (con personas marcadas: «Asignar rol» y
  **«Quitar rol de Jefe»**); un Jefe no puede nombrar a otros Jefes (06/11/2026).

## 11.31 Campos de nomencladores (06/11/2026, pendiente de implementar)

- **Tipo de vehículo:** además de nombre, descripción, observación y activación, tiene **cantidad de asientos** y
  **cantidad de pasajeros de pie**. El **total de pasajeros** es la **suma** de ambos (calculado, solo lectura).
- **Motivo de conversación:** tiene una **clave foránea al rol** al que pertenece (`role_id` → tabla `roles` con los
  tres roles fijos de §11.30), obligatoria. Sustituye al campo «Destinatario».
- **Se elimina el modelo Vehículo** (tabla `vehicles`, su pantalla y su API) (06/11/2026). La capacidad (asientos,
  de pie y total) está **solo en el tipo de vehículo**. Un **viaje** solo indica **qué tipo de vehículo** lo hará
  (clave foránea al tipo de vehículo, en lugar de al vehículo).

## 11.32 Recorrido en tiempo real sin chofer (06/11/2026, **NO implementar todavía**: el usuario lo modificará)

- Sin chofer, la ubicación del viaje la puede enviar **el Jefe de itinerario que va en el viaje** o **cualquier
  pasajero que se ofrezca**, desde el viaje («Iniciar recorrido» / «Terminar»).
- **No se implementa nada del recorrido en tiempo real** en la próxima entrega: queda pendiente de nuevas
  indicaciones del usuario.

## 11.33 Pestaña Viajes (06/11/2026, pendiente de implementar; en definición)

- **Quién ve qué:** el **Jefe de itinerario** solo ve los viajes **de su itinerario**; el **Administrador** ve
  **todos**; el trabajador, los de su itinerario.
- **Sin filtros de fecha.** Se muestran los viajes **confirmados** y los **en marcha** (de ida y de regreso), y también
  **todos los terminados**; en Acciones, **«Ocultar viajes terminados»** (y «Mostrar…» para volver a verlos).
- **«Declarar ausencia»** sale de Viajes y pasa a **Gestión** (donde están el itinerario y las paradas).
- **Opciones del trabajador en un viaje en marcha:** **«Estoy en mi parada»**, **«Ya me recogieron»**, **«Ya me
  bajé»** y **«No voy en este viaje»**. Caso particular: el trabajador que está en la **primera parada, que es el
  trabajo**. Ojo: en el viaje de **regreso**, en la interfaz, la **última parada es la primera del recorrido** (el
  orden se invierte).
- **Un viaje son en realidad dos viajes:** uno de **ida** y otro de **regreso**, cada uno por separado.
- **Sentido de los viajes** (06/11/2026; corrige lo anotado antes): la **parada 1 no tiene por qué ser el trabajo**
  (aunque, como una parada puede estar en varios itinerarios, es probable que la primera de muchos sea algo como
  «Parqueo del trabajo»).
  - **Ida:** empieza en la **primera parada**. **Todos esperan y suben ahí**; después **solo se bajan**, cada uno en
    su parada; en la **última parada** se baja quien no se haya bajado antes.
  - **Regreso:** empieza en la **última parada**, donde sube una parte; en el camino **van subiendo** más por sus
    paradas, hasta llegar a la **primera parada**, donde **se bajan todos**.
  - La parada de cada trabajador es, por tanto, **donde se baja en la ida y donde sube en el regreso**.
  - La interfaz muestra las paradas en el **orden del recorrido** de cada viaje (en el regreso, invertido).
- **Opciones del trabajador en un viaje en marcha** (06/11/2026; sustituyen a las anteriores):
  - **Ida:** **«Estoy en la parada <nombre de la primera parada>»** y **«Me bajé en mi parada»** (su parada, de la
    segunda a la última; la última es una parada más).
  - **Regreso:** **«Estoy en mi parada»** (su parada, de la última a la segunda), **«Ya me recogieron»** y
    **«Terminó el viaje»** (equivale a estar en la primera parada).
  - En la ida, «Ya me recogieron» es **sinónimo** de «Estoy en la parada <primera>» (todos suben ahí), por eso no
    es una opción aparte.
  - En los dos: **«No voy en este viaje»**.
- **Viajes sin confirmar** (06/11/2026): solo los ven el **Jefe de itinerario** (los de su itinerario) y el
  **Administrador**, en una sección **«Sin confirmar»**, para confirmarlos. El trabajador no los ve hasta que se
  confirman.
- **Pasajeros esperados** (06/11/2026): se espera a **todos los del itinerario** (con parada); nadie se apunta. Quien
  no va pulsa **«No voy en este viaje»** o declara una **ausencia** en Gestión. La ocupación prevista se calcula sola.
- **Planificar** (06/11/2026): el formulario tiene dos casillas, **«Ida»** y **«Regreso»** (las dos marcadas por
  defecto), cada una con **su hora y su tipo de vehículo**; se crean **dos viajes independientes**. Se puede
  planificar solo la ida o solo el regreso. Igual en «Planificar por fechas».
- **«No voy en este viaje» en la ida** (06/11/2026): la app pregunta **«¿Tampoco irá en el regreso?»** («Sí,
  tampoco» / «No, solo la ida») y, si responde que tampoco, lo marca también en el regreso de ese día.
- **Ajustes a Viajes** (06/11/2026):
  - El diálogo de «No voy» en la ida tiene los botones **«Tampoco»** y **«Solo la ida»**.
  - Se quita la acción **«Cambiar tipo de vehículo»**: el tipo de vehículo se cambia en el **formulario** del viaje.
  - La acción **«Pasajeros»** se llama **«Trabajadores»**.
  - **Recogido en el regreso con hijos:** cuando el **trabajador** pulsa «Ya me recogieron» indica **con cuáles de
    sus hijos** subió (niños concretos). Cuando lo marca el **Jefe de itinerario** (o el Administrador) como
    recogido, indica solo **cuántos hijos** subieron con él.
  - **«No va en este viaje»** lo puede marcar **el propio trabajador**, el **Jefe de itinerario** o el
    **Administrador**.
  - **Se eliminan** la **planificación por fechas** y **«Copiar a otras fechas»**: en esta versión todos los viajes
    se planifican **de forma manual**, uno a uno.
- **Formato de fechas y horas en toda la app** (06/11/2026): fechas **«sáb. dd-mm-aa»** (día de la semana abreviado
  y año de 2 dígitos, separados por guiones, p. ej. «sáb. 14-03-26»); horas en formato de **24 horas** («17:30»).
  Sustituye a las barras usadas antes (docs/05, docs/09).
- **Hijos en la ida** (06/11/2026): igual que en el regreso. Al pulsar **«Estoy en la parada <primera>»** el
  trabajador elige **con qué hijos** sube; si lo marca el Jefe de itinerario o el Administrador, solo indica
  **cuántos**.
- **Niños y ocupación** (06/11/2026; corrige lo anotado antes): los niños **cuentan en la cantidad total de
  pasajeros** (cuántas personas viajan), pero **no ocupan plaza** frente a la capacidad del tipo de vehículo, porque
  van sentados en las piernas de sus padres. La ocupación (normal, de pie, no caben) se calcula **solo con
  trabajadores**; los niños se muestran aparte (p. ej. «45 de 60 • 51 pasajeros con 6 niños»).

## 11.34 Estados de un viaje (06/11/2026, pendiente de implementar; en definición)

**Estados de un viaje** (06/11/2026): **No confirmado**, **Confirmado**, **Atrasado** (parado, pero en la
**primera o la última parada**, es decir, sin haber salido), **En marcha**, **Detenido** (parado **en el trayecto**)
y **Terminado**. «En marcha» sustituye a «En curso».
Además, **Cancelado** (06/11/2026): el Jefe del itinerario o el Administrador cancelan un viaje que no ha
terminado; **se conserva en el historial**, se **avisa a los trabajadores** y los cancelados se pueden **mostrar u
ocultar** en Viajes.

**Transiciones permitidas** (06/11/2026):

| Desde | Puede pasar a |
|---|---|
| No confirmado | Confirmado, Cancelado |
| Confirmado | No confirmado, Cancelado, Atrasado, En marcha |
| Atrasado | En marcha, Cancelado |
| En marcha | Detenido, Terminado |
| Detenido | En marcha, Terminado |
| Terminado | — |
| Cancelado | — |

- Confirmar, desconfirmar y cancelar solo lo hacen el Jefe del itinerario y el Administrador.
- **Opciones de los trabajadores** (cada marca es un voto; en el menú Acciones del viaje, solo las que tienen
  sentido según el estado actual): Confirmado → «Está atrasado…» (con causa) / «Ya está en marcha»; Atrasado → «Ya
  está en marcha»; En marcha → «Está detenido…» (con causa) / «Terminó el viaje»; Detenido → «Ya está en marcha» /
  «Terminó el viaje».

Cada viaje (de ida o de regreso) pasa por estos estados. Los cambios los provoca **una persona con autoridad**, un
**mínimo de usuarios de acuerdo** o, de forma **automática**, las **ubicaciones** que envían los teléfonos.

| Estado | Manual (Administrador o Jefe del itinerario) | Por usuarios | Automático (ubicaciones) |
|---|---|---|---|
| **Confirmado** | Lo confirma | — | — |
| **Atrasado** | Lo marca **indicando la causa** (nomenclador «Causas de atraso») | **Al menos 3** usuarios lo marcan con **la misma causa** | **Al menos 3** teléfonos envían su ubicación, están a **menos de 150 m de la parada de salida** y **ya pasó la hora de salida** |
| **En marcha** | Lo marca | **Al menos 3** usuarios lo marcan | **Al menos 3** teléfonos están a **150 m o más de la parada de salida** |
| **Terminado** | Lo marca | **Al menos 3** usuarios lo marcan | **Al menos 3** teléfonos están a **menos de 150 m de la parada de llegada** |
| **Detenido** | Lo marca **indicando la causa** (nomenclador «Causas de detención») | **Al menos 3** usuarios lo marcan con **la misma causa** | Se reciben las ubicaciones de **al menos 3** teléfonos en un instante y, en el **siguiente envío**, siguen a **menos de 150 m** (no se han movido) |

- **Parada de salida y de llegada** (07/11/2026): en la **ida** la salida es la **primera** parada y la llegada la
  **última**; en el **regreso**, al revés (sale de la última y llega a la primera). Las reglas automáticas usan la
  parada de salida o de llegada **del viaje en cuestión**.
- **Terminado, regla automática** (06/11/2026): se mide contra la **parada final del recorrido**: en la **ida**, la
  **última** parada; en el **regreso**, la **primera**. Además, **solo puede pasar a Terminado un viaje que ya estuvo
  En marcha**.
- **Detenido, regla automática** (06/11/2026): se aplica **tal como está** (interesa saber siempre que el viaje está
  detenido). Cuando lo detecta **el servidor no se indica causa**; la causa la ponen el Administrador, el Jefe del
  itinerario o al menos 3 trabajadores con la misma causa. Si la detención es a **menos de 150 m de la próxima
  parada**, **el servidor sí pone la causa «Recogiendo en la parada» e indica qué parada** (p. ej. «Recogiendo en
  la parada Coppelia»). En la **ida** la causa es **«Dejando en la parada …»** y en el **regreso** **«Recogiendo en
  la parada …»**. Son las únicas causas que pone el servidor.
- **Salir de Detenido** (06/11/2026): vuelve a **En marcha** por las mismas tres vías: lo marca el Administrador o el
  Jefe del itinerario; lo marcan al menos 3 trabajadores; o el servidor ve que al menos 3 teléfonos se han movido
  **150 m o más** entre un envío y el siguiente.
- **Umbrales ajustables** (06/11/2026): el **mínimo de usuarios o teléfonos** (3 por defecto) y la **distancia**
  (150 m por defecto) son **ajustes generales de toda la app**, en la **tabla de configuración** (no por
  itinerario).
- **Nomencladores nuevos:** **Causas de atraso** y **Causas de detención** (en la pantalla de Nomencladores, con
  las mismas reglas que los demás).
- Las reglas automáticas dependen de que los teléfonos envíen su ubicación (recorrido en tiempo real, §11.32, que
  **aún no se implementa**).
- **Secciones de Viajes y estados** (06/11/2026): los estados **Atrasado** y **Detenido** **no tienen sección
  propia**. El viaje se planifica, aparece en su lista y, a partir de ahí, **su estado se indica en la propia
  tarjeta** (etiqueta).
- **Secciones de la pestaña Viajes** (06/11/2026):

  | Sección | Qué viajes | Quién la ve |
  |---|---|---|
  | **Sin confirmar** | No confirmados (Acciones: «Ocultar viajes sin confirmar») | Todos |
  | **Planificados** | Confirmados, Atrasados, En marcha y Detenidos (estado en la etiqueta de la tarjeta) | Todos |
  | **Terminados** | Terminados (Acciones: «Ocultar viajes terminados») | Todos |
  | **Cancelados** | Cancelados (ocultos por defecto; Acciones: «Mostrar cancelados») | Todos |
- **Viajes sin confirmar para todos** (06/11/2026; sustituye lo dicho antes): los ven **todos los roles**, con la
  opción **«Ocultar viajes sin confirmar»** en Acciones.
- **Maquetas de Viajes aprobadas** (06/11/2026): las de la tercera versión (lista con «Sin confirmar»,
  «Planificados» y «Terminados»; opciones por estado y sentido; hijos al subir; causas de atraso y detención;
  «Trabajadores» del viaje; planificar solo de forma manual).

## 11.35 Chat del viaje (06/11/2026, pendiente de implementar; en definición)

- **Sin avisos automáticos** dentro del chat: solo los mensajes de las personas (los cambios de estado se ven en el
  viaje, no en el chat).
- **Un chat por viaje** (06/11/2026): uno para la **ida** y otro para el **regreso**.
- **Se eliminan** los mensajes del chat **en cuanto el viaje queda cancelado, terminado o eliminado** (sin plazo de
  retención; desaparece el ajuste `trip_chat_retention_days`).
- **Desde cuándo** (06/11/2026): el chat se abre **al confirmarse** el viaje; si vuelve a **No confirmado**, el chat
  queda **oculto** (sin borrarse) hasta que se confirme otra vez.
- **Participantes y borrado** (06/11/2026): participan los **trabajadores del itinerario que ven el viaje** (con
  parada), los **Jefes del itinerario** y el **Administrador**. Cada uno **borra sus mensajes**; los **Jefes del
  itinerario y el Administrador** pueden borrar también **los de otros**. Los mensajes se marcan como el resto de
  tarjetas (Acciones: Marcar todo, Desmarcar todo, Invertir selección, Copiar, Eliminar).
- **Se elimina la pestaña Mensajes** (06/11/2026). En su lugar, la barra principal tiene **«Avisos»** con el ícono de
  una **campanita** (sustituye a la campanita de la barra superior de Inicio). Barra principal: Inicio, Gestión,
  Viajes, **Avisos**, Más.
- Por tanto, al **chat del viaje** se entra **desde el viaje** (Acciones: «Chat del viaje»).
- **Conversaciones por motivo** (06/11/2026): se **mantienen**, con entrada desde la pestaña **Más** («Conversaciones»):
  lista de sus conversaciones y opción para abrir una nueva eligiendo el **motivo** (que determina el rol que la
  recibe, §11.31).

## 11.36 Pestaña Avisos (06/11/2026, pendiente de implementar; en definición)

- Se mantienen los avisos actuales (solicitud recibida, solicitud resuelta, contraseña por caducar). Los de
  incidencias del recorrido esperan al recorrido en tiempo real (§11.32).
- **Avisos de estado del viaje:** los trabajadores del viaje, sus Jefes y el Administrador reciben un aviso cuando
  el viaje se **confirma**, se **cancela**, se **atrasa** (con la causa), se pone **en marcha**, se **detiene** (con
  la causa) o **termina**. Cada usuario puede **apagarlos en sus ajustes**.
- **Mensajes nuevos** (del chat del viaje o de una conversación) (06/11/2026): **solo notificación del teléfono**, no
  aparecen en la pestaña Avisos; al tocarla se abre el chat o la conversación.

## 11.37 Sin pantalla de Avisos: solo notificaciones del teléfono (06/11/2026, decisión final; sustituye a §11.36)

- **Se elimina la pantalla (y la pestaña) Avisos**, y con ella la campanita. Barra principal: **Inicio, Gestión,
  Viajes, Más**.
- **Todo lo que la app tenga que avisar lo hace con las notificaciones del teléfono**, al menos en esta versión.
- **Qué se notifica queda pendiente:** el usuario lo indicará más adelante. Hasta entonces no se implementan avisos
  nuevos (los de estado del viaje de §11.36 quedan en suspenso).
- El número en la pestaña Gestión (solicitudes pendientes o resueltas, §11.26) se mantiene: no es un aviso, es un
  contador de la propia pantalla.

## 11.38 Un solo nivel de ajustes y pestaña Más (07/11/2026, pendiente de implementar)

- **Un único nivel de ajustes:** todos los ajustes valen **para toda la app, todos los usuarios y todos los
  teléfonos** (tabla de configuración), al menos en esta versión. Desaparecen los ajustes **de Entidad**, **por
  itinerario**, **por parada** (§11.17) y **de cada usuario**. Solo el **Administrador** los cambia («Ajustes de la
  app»).
- **Pestaña Más** (propuesta mostrada; pendiente de confirmar el resto):
  - Tarjeta de la persona (abre el perfil); Mi QR; Conversaciones; Estadísticas; Compartir la app; Cerrar sesión y
    versión.
  - Administrador: Nomencladores, Ajustes de la app, «Olvidé algo», Actualizaciones de la app, Mantenimiento del
    servidor.
  - Desaparecen de Más: Avisos, «Alta en itinerario con QR», Gestión, Vehículos y choferes, Roles, Entidades,
    Planificación, Ajustes de la Entidad, Ajustes por itinerario y Mis ajustes.
- **Estadísticas** (07/11/2026): **se quitan en esta versión** (pantalla, API y tareas que las calculan); el usuario
  indicará más adelante cuáles necesita.
- **Nomencladores** (07/11/2026): **solo en Más** (sección Administrador); sale del menú Acciones de Gestión.
- **Baja automática por inactividad** (07/11/2026): **se quita en esta versión** (tarea, ajustes y avisos
  relacionados); se podrá retomar más adelante.

## 11.39 Viaje en tiempo real con una línea, sin mapa (07/11/2026; amplía §11.32)

- **Se quita el mapa** del viaje en tiempo real (y el recorrido de referencia dibujado en él).
- El viaje en tiempo real se muestra **solo con una línea**: las paradas en el **orden del recorrido**, las ya
  pasadas en gris, y el vehículo en el tramo donde va («En marcha • a 600 m de Coppelia»), con «Mi parada» marcada.
- Como el resto del tiempo real (§11.32), **queda pendiente de implementar** hasta nuevas indicaciones.
- **Ubicación de la parada sin mapa** (07/11/2026): el formulario de la parada **no tiene mapa**; tiene el botón
  **«Usar mi ubicación actual»** (se pulsa estando en la parada) y muestra **latitud y longitud** en solo lectura.
  La app deja de necesitar mapas (se quitan el selector de mapa y las herramientas de servidor de mapas).

## 11.40 Ajustes de duración con unidades (07/11/2026, pendiente de implementar)

- Los ajustes que son **tiempos** se guardan en la tabla de configuración como **texto con unidad**, y el servidor
  (y la app) los interpretan. Unidades (07/11/2026; sustituyen a `s`, `m`, `h`):

  | Unidad | Significa |
  |---|---|
  | `seg` | segundos |
  | `min` | minutos |
  | `hor` | horas |
  | `dia` | días |
  | `sem` | semanas |
  | `mes` | meses |
  | `ano` | años |

- **Meses y años fijos** (07/11/2026): `1mes` = **30 días** y `1ano` = **365 días** siempre (no según el
  calendario); `1sem` = 7 días.
- Se pueden **combinar**: **`12hor30min30seg`** = 12 horas, 30 minutos y 30 segundos; **`1ano6mes`**, **`2sem3dia`**.
- Así, cada tiempo puede cambiar de unidad sin tocar el código (sustituye a los ajustes con la unidad en el nombre,
  como «…_minutes», «…_seconds», «…_days»).

## 11.41 Batería, ubicación y sincronización (07/11/2026, pendiente de implementar; en definición)

- **Objetivos:** gastar poca batería y que la app sea confiable (depende de la sincronización y de que los usuarios
  tengan la ubicación activada). No hay websockets: la app consulta al servidor.
- **Ubicación obligatoria:** para ver el **estado del viaje**, el **chat del viaje** y la **línea del recorrido**, el
  trabajador **debe tener la ubicación activada**; si no, la app se lo pide antes de mostrarlos.
- **Recordatorio para activarla:** cuando falten **10 min** para empezar un viaje (tiempo configurable por el
  Administrador), la app recuerda activar la ubicación.
- **Recordatorio para desactivarla:** cuando el viaje **termina**, la app recuerda desactivar la ubicación.
- **Frecuencias** (propuesta del usuario, en estudio): durante un viaje en ejecución, consultar al servidor y enviar
  la ubicación cada **5 s**; sin viajes confirmados, actualizar cada **1 hora**. Ambos configurables por el
  Administrador para todas las apps.

## 11.42 Modelo simplificado: viaje, vehículo y trabajador (07/11/2026, en definición; sustituye a los estados de §11.34)

Se necesita saber cuatro cosas, cada una con su propio estado:

| Qué | Valores |
|---|---|
| **Estado del viaje** | **Planificado** (al crearlo el Administrador o el Jefe de itinerario) → **En ejecución** → **Terminado**; de Planificado también puede pasar a **Cancelado** |
| **Estado del vehículo** | **Detenido**, **En movimiento** |
| **Ubicación del vehículo** | **En una parada** del itinerario, **Entre 2 paradas** del itinerario |
| **Estado del trabajador** | En la ida: **está en la primera parada**. En el regreso: **está en su parada**; **está en el vehículo** |

- Desaparecen los estados No confirmado, Confirmado, Atrasado, En marcha y Detenido del viaje (§11.34). Lo que
  antes era «Atrasado» o «Detenido» pasa a deducirse del estado y la ubicación del vehículo.
- Cuando el vehículo está **Detenido**, la **causa de la detención** es un **nomenclador** («Causas de detención»).
- Los **algoritmos** para determinar cada cosa se definirán paso a paso con el usuario.
- **Se quita «Causas de atraso»** (07/11/2026): ya no existe el estado Atrasado; el nomenclador desaparece.
- **Algoritmo 1 — Ubicación del vehículo** (07/11/2026): se toma de los teléfonos de los **trabajadores que están
  «en el vehículo»**. Si hay varios, el servidor toma el **punto en que coincide la mayoría** y **descarta** al que
  se aleja mucho (p. ej. alguien que se bajó sin avisar).

## 11.43 Algoritmos desde cero (07/11/2026, en definición; sustituye a las propuestas anteriores de §11.34 y §11.42)

Se definen uno a uno, con el usuario.

### Estado del viaje

- **Planificado:** al crearlo el Administrador o el Jefe de itinerario.
- **Planificado → Cancelado:** lo cancela el **Administrador** o el **Jefe de itinerario que lo planificó**.
- **Planificado → En ejecución**, si ocurre cualquiera de:
  - el **Administrador** o el **Jefe del itinerario** lo declaran;
  - **ida:** al menos **3 trabajadores cualesquiera** lo declaran; **regreso:** al menos **3 trabajadores de la última
    parada** lo declaran;
  - **después de la hora de inicio**, al menos **3 teléfonos** envían su ubicación y están a **más de 100 m** de la
    **primera parada** (ida) o de la **última parada** (regreso).
- **En ejecución → Terminado**, si ocurre cualquiera de:
  - el **Administrador** o el **Jefe del itinerario** lo declaran;
  - **ida:** al menos **3 trabajadores de la última parada** lo declaran; **regreso:** al menos **3 trabajadores
    cualesquiera** lo declaran;
  - **ida:** al menos **3 teléfonos de trabajadores de la última parada** envían su ubicación y están a **más de
    100 m** de la última parada;
  - **regreso:** al menos **3 teléfonos cualesquiera** envían su ubicación y están a **menos de 100 m** de la primera
    parada;
  - **ida:** el **vehículo está detenido** a **menos de 100 m** de la **última parada**;
  - **regreso:** el **vehículo está detenido** a **menos de 100 m** de la **primera parada**.

### Ubicación del trabajador (se determina antes que el estado del viaje)

- Valores: **En la primera parada** (ida), **En su parada** (regreso), **Fuera de la parada**.
- **Ida — En la primera parada:** su teléfono estaba a **menos de 100 m** de la **primera parada** **10 minutos
  antes** de la hora de comienzo.
- **Regreso — En su parada:** su teléfono estaba a **menos de 100 m** de la **última parada** 10 minutos antes.
- **Fuera de la parada:** a **más de 100 m** de la primera parada (ida) o de la última parada (regreso) en esos
  10 minutos antes.
- Los **10 minutos** son **un único ajuste** de la app (el mismo para ida y regreso), configurable por el
  Administrador.
- **Regreso, paradas intermedias** (07/11/2026): cada trabajador se mide respecto a **su propia parada**: está **En su
  parada** si su teléfono está a menos de 100 m de ella. Para los de la última parada coincide con lo anterior; para
  los demás se mide desde **10 minutos antes de la hora estimada de paso** por su parada o desde que el viaje está
  **En ejecución**. (Cómo se estima la hora de paso queda por definir.)

### Trabajador «En el vehículo»

Un trabajador está **En el vehículo** si ocurre cualquiera de:

- lo declara el **Administrador** o el **Jefe del itinerario**;
- lo declara **el propio trabajador**;
- lo declaran **al menos 3 trabajadores que ya iban en el vehículo**;
- regla automática (07/11/2026, afinada): el trabajador **alcanzó el estado «En la parada»** (primera parada en la
  ida, su parada en el regreso); **después, el vehículo pasó por su parada**; y **luego se alejó más de 100 m** de
  ella. (Así no cuenta quien se va a pie antes de que pase el vehículo.)
- **El vehículo pasó por la parada de salida** (07/11/2026): se considera que pasó cuando el viaje pasa a **En
  ejecución** (por cualquiera de sus vías). En las demás paradas se sabe por la **ubicación del vehículo**.

### Estado del trabajador en el regreso (07/11/2026, en definición; versión simple)

Cada teléfono envía su ubicación en instantes sucesivos t1, t2… Con la distancia a **su parada** en cada envío
(d1 en t1, d2 en t2):

| Condición | Estado |
|---|---|
| d2 < d1 | **Acercándose a la parada** |
| d2 < d1 y d2 ≤ 100 m | **En la parada** |
| d2 > d1 | **Alejándose de la parada** |
| d2 > d1 y d2 > 100 m | **No voy a viajar** |

- **Tolerancia al «temblor» del GPS** (07/11/2026):
  - si **d2 ≤ 100 m**, el trabajador está **En la parada**, se acerque o se aleje un poco;
  - solo se considera que **se acerca o se aleja** si **|d1 − d2| > 20 m** (ajuste de la app); si la diferencia es
    menor, **no se movió** y conserva el estado que tenía.

El estado que falta en el regreso es **Recogido** (cómo se determina, en definición).

**Estados del trabajador en el regreso, definitivos** (07/11/2026): **De camino a la parada** (sustituye a
«Acercándose a la parada»), **En la parada**, **No voy a viajar** y **Recogido**. Desaparece «Alejándose de la
parada». Reglas, en este orden: d2 ≤ 100 m → En la parada; |d1 − d2| ≤ 20 m → conserva el estado; se acerca y
d2 > 100 m → De camino a la parada; se aleja y d2 > 100 m → No voy a viajar; Recogido → por definir.

- **Quién declara los estados del trabajador** (07/11/2026): en esta primera versión **solo el propio trabajador**,
  o se **calculan automáticamente**. (No los declaran el Jefe, el Administrador ni otros trabajadores.)
- **Recogido** (07/11/2026, en definición): lo declara el propio trabajador o se calcula automáticamente cuando el
  trabajador **se aleja de la parada a una velocidad mayor que la de caminar**. Velocidad = (d2 − d1) / (t2 − t1).
  - **Límite: 10 km/h** (ajuste de la app). Si antes estuvo **En la parada** y se aleja a **más de 10 km/h** →
    **Recogido**; si se aleja a menos y ya está a más de 100 m → **No voy a viajar**.
  - La velocidad **solo se calcula cuando ya está a más de 100 m** de la parada y alejándose; mientras está dentro
    de los 100 m sigue **En la parada** (así, un arranque suave del vehículo no cambia el estado).
- **Recogido es el estado final e irreversible** (07/11/2026): una vez Recogido, ya no cambia ni se calcula nada
  más para ese trabajador en ese viaje.
- **No voy a viajar definitivo** (07/11/2026): si se aleja a **más de 1000 m** de su parada a velocidad de persona
  (10 km/h o menos), «No voy a viajar» pasa a ser **definitivo**. Entre 100 m y 1000 m todavía **puede cambiar**
  (volver a De camino a la parada / En la parada, o pasar a Recogido si se aleja a más de 10 km/h). Los 1000 m son
  un ajuste de la app.

### Dónde se calcula el estado del trabajador (07/11/2026)

- **Todos los cálculos del estado del trabajador se hacen en la app del teléfono** (tiene la ubicación de su parada
  y la suya por GPS), **no en el servidor**.
- La app **envía al servidor solo el cambio de estado**. El servidor responde con un **acuse**. Si la app recibe el
  acuse, no lo vuelve a enviar; si no lo recibe, **lo reenvía hasta recibirlo**.
- **Ajustes de la app para los estados del trabajador** (propuestos por el usuario): **radio de parada** `100m`;
  **velocidad humana** `10km/h`; **frecuencia de cálculo antes de Recogido** `10seg`.
- **Lista completa de ajustes de los estados del trabajador** (07/11/2026):

  | Ajuste | Valor por defecto |
  |---|---|
  | Radio de parada | `100m` |
  | Velocidad humana | `10km/hor` |
  | Frecuencia de cálculo antes de Recogido | `10seg` |
  | Tolerancia del GPS (diferencia mínima entre d1 y d2) | `20m` |
  | Distancia de «No voy a viajar» definitivo | `1km` |
  | Cuándo empieza a calcular (antes de la salida; mismo ajuste que el recordatorio de activar la ubicación) | `10min` |

- **Velocidades** se escriben como **distancia/tiempo** con las unidades acordadas (`10km/hor`, `200m/min`).
- Las **distancias se pueden combinar** como los tiempos (`1km200m`).
- **Distancias con unidades** (07/11/2026): como los tiempos, las distancias se guardan con su unidad: **`m`** para
  metros y **`km`** para kilómetros (p. ej. `100m`, `1km`), y el sistema las distingue.

## 11.44 Nombres y grupos de los ajustes (07/11/2026, regla para toda la app)

- Los **nombres de los ajustes** son de **pocas palabras** y usan **solo sustantivos, adjetivos, verbos y
  adverbios** (sin artículos ni preposiciones), p. ej. «Radio parada», «Velocidad humana».
- Los ajustes se **separan en dos grupos**: los **generales**, que sirven para varias cosas, y los **específicos**
  de cada cosa (p. ej. «Estado trabajador»).
- **Ajustes definidos hasta ahora** (07/11/2026):

  | Grupo | Nombre | Valor | Uso |
  |---|---|---|---|
  | General | **Radio parada** | `100m` | Estado del trabajador, estado del viaje, vehículo en la parada |
  | General | **Anticipación viaje** | `10min` | Recordatorio de activar la ubicación; inicio del cálculo del estado del trabajador |
  | General | **Mínimo confirmaciones** | `3` | Estado del viaje (trabajadores o teléfonos que deben coincidir) |
  | Estado trabajador | **Velocidad humana** | `10km/hor` | Recogido / No voy a viajar |
  | Estado trabajador | **Tolerancia GPS** | `20m` | Diferencia mínima entre d1 y d2 |
  | Estado trabajador | **Distancia abandono** | `1km` | «No voy a viajar» definitivo |
  | Estado trabajador | **Frecuencia cálculo** | `10seg` | Cálculo en el teléfono antes de Recogido |
  | Estado trabajador | **Cálculos consecutivos** | `6` | Velocidad humana seguida en una parada para Dejado (ida) |
  | Estado trabajador | **Espera final** | `10min` | Tras Dormido o Botado, dejar de calcular y recordar desactivar el GPS |
  | Estado viaje | **Plazo eliminación** | `5hor` | Eliminar un viaje que nunca salió (desde su último estado) |
  | Estado viaje | **Duración máxima** | `5hor` | Terminar un viaje que sigue En ejecución |
  | Estado viaje | **Espera cierre** | `2hor` | Terminar tras el último Dejado (ida) o Recogido (regreso) sin llegar a la parada final |
  | Notificaciones | **Detención larga** | `5min` | Notificar a quienes están En la parada si el vehículo lleva detenido más de ese tiempo |
  | Sincronización | **Frecuencia reposo** | `1hor` | Consulta al servidor sin viajes ese día |
  | Sincronización | **Frecuencia día viaje** | `15min` | Consulta al servidor cuando hay un viaje ese día |
  | Sincronización | **Frecuencia chat** | `5seg` | Consulta del chat mientras está abierto |

### Estado del trabajador en la ida (07/11/2026, en definición)

- Estados: **De camino a la parada** (antes «Acercándose», mismo nombre que en el regreso), **En la parada** (la
  primera; como todos suben ahí, no hace falta un estado «Recogido»), **Viajando**, **Dejado** y **No voy a viajar**.
- **De camino a la parada** y **No voy a viajar**: se calculan **igual que en el regreso** (respecto a la primera
  parada), con las mismas condiciones y ajustes.
- **Viajando**: se calcula **igual que Recogido** en el regreso (estuvo En la parada; ya a más de Radio parada se
  aleja a más de Velocidad humana).
- **Dejado** (07/11/2026): estando Viajando, la velocidad es **humana** y está **dentro del radio de alguna parada**
  del recorrido (no necesariamente la suya; bajarse fuera de su parada no es relevante).
  Solo es Dejado si la velocidad sigue siendo humana en **N cálculos consecutivos** (ajuste de la app, «Cálculos
  consecutivos», por defecto **6**: con Frecuencia cálculo `10seg`, 1 minuto).
- **Dejado** y **No voy a viajar** (definitivo) son **estados definitivos**.
- **No voy a viajar al salir el vehículo** (07/11/2026): cubre a quien se queda cerca de la primera parada (p. ej.
  trabajando a menos de 1 km). **Ida:** cuando el viaje pasa a **En ejecución** (el teléfono lo sabe en su siguiente
  consulta al servidor), todo trabajador que **no esté Viajando** pasa a **No voy a viajar definitivo**, esté donde
  esté; la app deja de calcular y recuerda quitar el GPS. **Regreso:** igual, cuando **el vehículo ya pasó por su
  parada** y el trabajador no está Recogido (cómo se sabe que pasó, se define con el vehículo).
- **Viajando es semidefinitivo** (07/11/2026): desde Viajando **solo se puede pasar a Dejado**. Una vez Viajando,
  **solo se calcula la velocidad** (y si está en el radio de una parada), no la distancia a la primera parada.
- **Recordatorio de quitar el GPS** al llegar a un estado definitivo.
- Todo se **calcula en la app** y se envía el **cambio de estado** con acuse, como en el regreso, con los mismos
  ajustes. Por eso los ajustes «Estado trabajador» sirven para **ida y regreso**.

### Estado y ubicación del vehículo (07/11/2026, en definición)

- **Estados del vehículo:** **Detenido** y **En movimiento**.
- **Teléfonos sensores:** cuando un trabajador alcanza **Recogido** (regreso) o **Viajando** (ida), su teléfono pasa a
  ser **sensor del estado del vehículo**.
- Cada cierto tiempo recalcula su posición: si cambió (más allá de un umbral de algunos metros) → **En movimiento**;
  si es la misma (dentro del umbral) → **Detenido**. De ahí salen los ajustes (frecuencia y umbral).
- **Dónde está detenido:** en cada instante se conoce la **próxima parada**, con la que se comparan las distancias
  (igual que «acercándose» / «alejándose» de la parada):
  - **Detenido** a **menos de Radio parada** de la próxima parada → **Recogiendo** en esa parada (en la ida,
    «Dejando»).
  - **Detenido** fuera de ese radio → detenido **en el trayecto** (semáforo, bache, rotura…).
  - **En movimiento** con la distancia a la **próxima parada disminuyendo** (o la distancia a la **parada anterior
    aumentando**) → **entre la parada anterior y la próxima**.
- **Ajustes del sensor** (07/11/2026): se reutilizan **Frecuencia cálculo** (`10seg`) como frecuencia del sensor y
  **Tolerancia GPS** (`20m`) como umbral de «misma posición».
- **Varios sensores** (07/11/2026): cada teléfono sensor envía al servidor su **cambio de estado del vehículo** (con
  acuse). El servidor toma el estado que indica **la mayoría** de los sensores y solo lo cambia si coinciden al
  menos **Mínimo confirmaciones** (`3`); si hay menos de 3 sensores, basta la mayoría de los que haya.
- **Avance de la próxima parada** (07/11/2026): la próxima parada queda **pasada** cuando el vehículo **entró en su
  radio** (Radio parada) y luego **salió del radio alejándose**; entonces la próxima es la siguiente del recorrido.
  Cada sensor lo calcula e informa, y el servidor lo acepta con la misma mayoría. Si el vehículo **se salta** una
  parada sin entrar en su radio, se considera pasada cuando **empieza a acercarse a la siguiente**. Esto es lo que
  determina que «el vehículo ya pasó por su parada» (No voy a viajar definitivo en el regreso).

### Estado del viaje, versión final (07/11/2026; sustituye a la versión con «teléfonos a más de 100 m»)

Los teléfonos ya no envían ubicaciones, solo cambios de estado; el estado del viaje se deduce así:

| Paso | Cuándo |
|---|---|
| **Planificado → Cancelado** | Lo cancela el **Administrador** o el **Jefe que lo planificó** |
| **Planificado → En ejecución** | Lo declara el Administrador o el Jefe del itinerario, **o** al menos **Mínimo confirmaciones** (3) trabajadores pasan a **Viajando** (ida) o a **Recogido** en la **última parada** (regreso) |
| **En ejecución → Terminado** | Lo declara el Administrador o el Jefe del itinerario, **o** según los sensores el vehículo **pasó la última parada** (ida) o está **Detenido en el radio de la primera parada** (regreso) |

- Al **terminar** el viaje, la app de todos **deja de calcular** y **recuerda quitar el GPS**.

### Lo que calcula el servidor (07/11/2026)

- **Ida:**
  - **personas en el vehículo:** los que alcanzaron **Viajando**;
  - **en cada parada:** cuántos **se van dejando** (Dejado) y cuántos **siguen Viajando**.
- **Regreso:**
  - **personas en cada parada** (En la parada);
  - **personas en el vehículo:** los que alcanzaron **Recogido**.
- **Fecha y hora en que el vehículo pasó por cada parada**, en la ida y en el regreso.
- La interfaz muestra la **cantidad de sensores** (teléfonos que informan el estado del vehículo).

### Estado «Botado» en el regreso (07/11/2026)

- Si **el vehículo ya pasó por su parada** y **después** el trabajador llega a **En la parada**, su estado es
  **Botado**, y la app **le informa que llegó tarde** a su parada.
- Mientras tenga ese estado, el **recorrido de regreso** (la línea) muestra **la cantidad de personas Botadas** en
  esa parada.
- Después puede pasar a **No voy a viajar** según su movimiento (se aleja), o **pasado un tiempo** la app deja de
  calcular y recuerda **desactivar el GPS**. (Botado implica que no va a viajar.)
- Sustituye, para este caso, a «No voy a viajar definitivo» cuando el vehículo ya pasó por su parada.
- **Nombres definitivos** (07/11/2026):
  - **Dormido:** llegó a **En la parada** **después** de que el vehículo pasara por ella (llegó tarde).
  - **Botado:** estaba **En la parada** cuando pasó el vehículo, pero **no lo recogió** (no paró o iba lleno): sigue
    a velocidad humana sin llegar a Recogido después del paso del vehículo.
  - La línea del regreso muestra en cada parada **cuántos Dormidos y cuántos Botados** hay mientras mantengan ese
    estado; los dos pueden pasar luego a No voy a viajar o, pasado un tiempo, la app deja de calcular.
  - **Espera final** (ajuste de la app, por defecto `10min`): tiempo tras quedar Dormido o Botado, si no se aleja,
    para que la app deje de calcular y recuerde desactivar el GPS.

### Frecuencias de consulta al servidor (07/11/2026; cierra lo que estaba «en estudio» en §11.41)

| Momento | Consulta al servidor | Ajuste |
|---|---|---|
| Sin viajes ese día | Cada `1hor` | Frecuencia reposo |
| Hay un viaje ese día | Cada `15min` | Frecuencia día viaje |
| Desde Anticipación viaje (10 min antes) hasta su estado definitivo | Cada `10seg`, en la **misma petición** en que envía sus cambios de estado | Frecuencia cálculo |
| Con el chat abierto | Cada `5seg` | Frecuencia chat |

- Si no hay novedades, el servidor responde **casi vacío**.
- El recordatorio de activar la ubicación lo **programa el propio teléfono** al enterarse del viaje.
- **Revisión del estado del viaje** (07/11/2026):
  - **Nunca salió:** si sigue **Planificado**, el viaje **se elimina del servidor** pasadas **5 horas** (ajuste de la
    app).
  - **En ejecución sin terminar:** a las **5 horas** pasa a **Terminado** (ajuste de la app).
  - Las horas se miden **a partir del último estado** del viaje (07/11/2026).
  - **También termina** (07/11/2026; sustituye a lo anterior sobre sensores y «todos Dejados»):
    - **ida:** pasaron **2 horas** desde que **el último trabajador alcanzó Dejado** y el vehículo **no llegó a la
      última parada**;
    - **regreso:** pasaron **2 horas** desde que **el último trabajador alcanzó Recogido** y el vehículo **no llegó
      a la primera parada**.
    - Las 2 horas son un ajuste de la app.

## 11.45 El tiempo real entra en la próxima versión, con la línea del recorrido (07/11/2026)

- **Corrección:** el tiempo real **sí entra** en la próxima versión, **sin mapa**, mostrado con la **línea del
  recorrido** (§11.39). Se implementa todo lo definido en §11.41–§11.44: estados del trabajador calculados en el
  teléfono, teléfonos sensores, estado y ubicación del vehículo, avance de la próxima parada, estado del viaje,
  lo que calcula el servidor, ajustes y frecuencias.
- Queda **sin efecto** el «no implementar todavía» de §11.32 y §11.39.

## 11.46 Sin chat en esta versión (07/11/2026)

- **Se elimina el chat del viaje** (§11.35) y las **conversaciones dirigidas a un rol** en esta versión.
- **Solo quedan las conversaciones con el desarrollador** (entrada desde Más → «Conversaciones»).
- **Motivos de conversación** (07/11/2026): se **mantienen** para **clasificar los mensajes al desarrollador** (p. ej.
  «Error», «Sugerencia», «Duda»); se les **quita el campo Rol** (sustituye a §11.31 en ese punto).
- **Línea del recorrido** (07/11/2026): maqueta mostrada (personas en el vehículo con niños aparte, cantidad de
  sensores, «Mi estado», cantidades por parada, hora de paso y estado del vehículo). **Sin horas estimadas** de
  llegada mientras no se defina cómo calcularlas.
- **Sin horario estimado** en esta versión (07/11/2026).
- **Sensor** (07/11/2026): un trabajador **Recogido** (regreso) o **Viajando** (ida) **cuyo teléfono está enviando**
  al servidor. La línea del recorrido muestra **en todo momento** cuántos sensores hay, de forma destacada.
- **Sensor activo** (07/11/2026): deja de contar si **no envía nada en 3 cálculos seguidos** (con Frecuencia cálculo
  `10seg`, 30 s); si vuelve a enviar, cuenta otra vez.
- **Diseño de la línea** (07/11/2026):
  - La **línea sale siempre en la misma posición**; lo que cambia es el **orden de las paradas** de arriba abajo
    (ida o regreso).
  - **Regreso:** una parada **no visitada** muestra solo **De camino** y **En la parada**; una parada **ya visitada**
    muestra solo **Botados**, **Dormidos** y la **hora en que pasó**.
  - **Ida:** las paradas **ya pasadas** muestran la **hora** y la cantidad de **Dejados**.
  - Los **Recogidos** (regreso) y los **Viajando** (ida) se muestran en una **tarjeta abajo**.
  - **Cantidades en cero no se muestran** (07/11/2026), en ningún estado.
  - **Ida:** una **tarjeta** con los trabajadores **esperando en la primera parada** (En la parada), y esa cantidad
    también aparece en la **línea**, en la primera parada.
    Texto de la tarjeta: **«N esperando en [nombre de la primera parada]»** (p. ej. «38 esperando en Parqueo del
    trabajo»).

## 11.47 Notificaciones del teléfono (07/11/2026; completa §11.37)

Todas por **notificaciones del teléfono** (no hay pantalla de avisos).

| Para | Se notifica |
|---|---|
| **Trabajadores del viaje** | **Creación** del viaje y sus **cambios de estado**, **excepto** la eliminación y la terminación |
| | **Cambios en los valores** del viaje mientras está **Planificado** (p. ej. la hora de salida) |
| | **Estado del vehículo** durante el viaje: a los trabajadores **En la parada**, (1) cuando hay una **detención de más de `5min`** (ajuste «Detención larga»), (2) cuando, **después de esa detención larga, vuelve a moverse**, y (3) cuando el vehículo **llega a cada parada** (Detenido recogiendo) |
| | **Sus propios estados**, después de activar el GPS |
| **Trabajadores** | **Aceptación o denegación** de sus solicitudes |
| | **Mensajes nuevos** (respuestas del **desarrollador**) en su conversación |
| **Administrador y Jefe de itinerario** | **Solicitudes hechas** (que les toca resolver) |

- Además siguen los **recordatorios** ya acordados: activar la ubicación antes del viaje y quitar el GPS al llegar a
  un estado definitivo.
- **Viaje en ejecución no editable** (07/11/2026): cuando un viaje pasa a **En ejecución**, **ya no se pueden
  cambiar sus valores** (fecha, hora, tipo de vehículo…) en la tabla; solo cambian su estado y los datos que calcula
  el sistema.

## 11.48 Botón de actualización manual (07/11/2026)

- La app tiene **en todo momento** un **botón para actualizar manualmente** los datos, en la barra superior, **al lado
  del indicador de conectividad** (el punto verde). Al pulsarlo consulta al servidor en ese momento, además de las
  consultas periódicas.

## 11.49 Dependencias mínimas (07/11/2026, para la implementación)

- Al pasar a Laravel 12 se **eliminan los paquetes que no se usen** y se **instalan solo los necesarios** (servidor y,
  por coherencia, también en la app Flutter).

## 11.50 Más notificaciones y estilo de pantallas (07/11/2026)

- **Notificación de actualizaciones de la app disponibles** (para todos).
- **Hijos:** la consulta y edición de un hijo tiene el **mismo estilo que la de los trabajadores** (formulario sin
  datos relacionados, interruptor «Activado», menú Acciones).
- **Perfil:** el **mismo estilo que la de los trabajadores**.
- **Conversación con el desarrollador:** estilo **WhatsApp** (burbujas propias a la derecha y ajenas a la izquierda,
  hora en cada mensaje, campo de texto abajo), **solo texto**.
- **Pantalla de inicio de sesión:**
  - lleva el **indicador de conexión** (como el resto de pantallas);
  - el botón para indicar el **servidor** se pone **en rojo** cuando **no hay servidor indicado**, y con su **color
    normal** cuando sí lo hay;
  - **cada vez que se intente operar la app sin servidor** indicado, aparece un **aviso**.
