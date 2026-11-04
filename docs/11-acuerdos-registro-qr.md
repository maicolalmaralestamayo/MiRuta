# 11. Acuerdos: registro, personas y Entidades, contraseñas, tarjetas, hijos y QR

Acuerdos con el Product Owner del 03 y 04/11/2026, **pendientes de implementar**. Cambian lo descrito en
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
- **Botones al final de la pantalla:**
  - **Añadir hijo** (directo, §11.11), cuando no tiene hijos registrados;
  - **Solicitar rol**, cuando no tiene en esa Entidad ningún rol además de Trabajador.
- **Al tocar cualquier tarjeta** se abre su formulario de edición, de detalle o de solicitud.
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

## 11.15 Quién hace qué

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

