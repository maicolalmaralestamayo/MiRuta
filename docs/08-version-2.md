# 8. Versión 2: varias Entidades

Acuerdos para que la app la usen trabajadores de varias empresas (**Entidades**). Lo que no se menciona aquí sigue como en los documentos anteriores; donde haya contradicción, manda este documento hasta que los demás se actualicen.

## 8.1 Peso de la app y actualizaciones

1. **Dos APK por versión:** 64 bits (~13 MB) y 32 bits (~12 MB).
   - La app pregunta a Android qué APK admite y descarga el suyo.
   - Si una versión se publica con un solo APK, todos reciben ese.
   - Para la primera instalación se reparte el de 64 bits; si un teléfono dice que no es compatible, se le pasa el de 32.
2. **Lector de QR sin cambios:** lleva su propio ML Kit, así funciona sin servicios de Google.
3. **Se quitan los iconos de iOS** que no se usan.
4. **Ajuste "Descargar actualizaciones solo con Wi-Fi"**, **desactivado** por defecto.
   - Si está activado y hay datos móviles, se avisa del tamaño y se puede descargar igualmente.
   - Las obligatorias se descargan siempre, avisando antes del tamaño.
5. **Botón "Compartir la app"** (en **Más**): abre el menú de compartir de Android (WhatsApp, Telegram, Bluetooth, Quick Share…) y envía el APK. Pregunta para qué tipo de teléfono: **"La mayoría (64 bits)"** (por defecto) o **"Teléfonos antiguos (32 bits)"**. Por Bluetooth o Quick Share no gasta datos.
6. **Se elimina el PDF.** Las estadísticas no tienen ninguna forma de exportar: solo se ven en la app, con gráfico y tabla.
7. Se mantiene el mínimo de **Android 7**.

## 8.2 Entidades

1. **Tabla de Entidades**, que solo crea, edita y desactiva el Administrador:

   | Campo | Regla |
   |---|---|
   | **Abreviatura** | Obligatoria. Única entre todas, también las inactivas. Se guarda en mayúsculas, de 2 a 15 letras y números. **Es lo que se muestra en toda la app** |
   | Número | Opcional. 4 dígitos, único si se pone |
   | Nombre | Obligatorio |
   | Campos de nomenclador | Descripción, observación y fechas, con borrado lógico |

2. **Cada trabajador pertenece a una sola Entidad** y tiene un **Pase** (entero, obligatorio, único dentro de su Entidad).
3. **La Entidad se escribe, no se elige:** se teclea la abreviatura sin importar mayúsculas y la app muestra el nombre para confirmar. **Nunca se muestra la lista de Entidades** (salvo al Administrador).
4. **Qué tablas llevan la Entidad:** solo las raíz (trabajadores, itinerarios, paradas y vehículos). Las demás la heredan. La API comprueba que todo lo relacionado sea de la misma Entidad.
5. **Compartimentación:**
   - cada uno ve y actúa solo sobre su Entidad;
   - lo ajeno responde 404, como si no existiera;
   - el Administrador ve todo, con un **selector de Entidad**.
6. **Paradas:** dos Entidades pueden usar el mismo lugar, pero cada una registra la suya.
7. **Nomencladores comunes a toda la app:** jerarquías, tipos de vehículo, tipos de ausencia, motivos de conversación y uno nuevo de **palabras no permitidas** para los usuarios.
8. **Ajustes en tres niveles**, todos granulares (cada plazo por separado, con su valor por defecto, mínimo y máximo):

   | Nivel | Quién lo fija |
   |---|---|
   | App | Administrador. Incluye la caducidad de los chats y la política de contraseñas |
   | Entidad | Jefe de Transporte de la Entidad (y el Administrador) |
   | Usuario | Cada uno |

9. **Las migraciones se rehacen desde cero**, porque aún no hay datos.

## 8.3 Cuentas y registro

1. **Cuenta y trabajador se separan.**
   - La **cuenta** (`users`) es quien entra en la app: usuario, contraseña, nombres, foto.
   - El **trabajador** (`workers`) pertenece a una Entidad y viaja: Pase, sexo, jerarquía, itinerario y parada.
   - El **Administrador** es el primero que se registra. Es una cuenta **sin trabajador**: no tiene Entidad, Pase, jerarquía ni viajes. Ve todo, incluido el Pase.
2. **Paso 1, crear la cuenta:** primer nombre, segundo nombre, primer apellido, segundo apellido (**los cuatro obligatorios**), usuario y contraseña. El primero que se registra pasa a ser Administrador y termina aquí.
3. **Paso 2, unirse a la Entidad** (obligatorio para los demás): abreviatura, Pase, **sexo** (se pide explícitamente) y jerarquía. Hasta completarlo, la app no deja hacer nada más.
4. **Se elimina el carné por completo**, de trabajadores y de hijos.
5. **Reglas del usuario:**
   - lo escribe el propio usuario, sin propuesta automática;
   - de 4 a 20 caracteres: letras sin tilde, números, `.` y `_`;
   - empieza por letra y no termina en signo;
   - sin dos signos seguidos;
   - al menos 3 letras;
   - ningún carácter repetido más de 3 veces seguidas;
   - se guarda en minúsculas y es único en toda la app;
   - no puede contener palabras reservadas (`admin`, `soporte`, `sistema`, `mitransporte`…) ni palabras no permitidas, comprobadas también con números camuflados (`p3nd3jo`);
   - se puede cambiar siempre desde el perfil, y el anterior queda **bloqueado 30 días** (ajuste global).
6. **Inicio de sesión:** solo con usuario y contraseña.
7. **Jerarquía:** cada uno la cambia en su perfil, sin solicitud. Sirve solo para estadísticas.
8. **Quién ve el Pase:** el propio trabajador, el Jefe de su itinerario (también al aprobar su entrada en el itinerario), el Jefe de Transporte de su Entidad y el Administrador.
9. **Trabajadores sin teléfono:**
   - Los registran el Jefe de Transporte, el Jefe de itinerario o el Administrador. La cuenta queda sin usuario ni contraseña.
   - Se genera un **código de activación** de un solo uso, con caducidad configurable. Se entrega en mano (papel o QR) y se puede regenerar.
   - El trabajador pulsa **"Ya me registró un superior"**, escribe abreviatura, Pase y código, y **elige él mismo su usuario y su contraseña**.

## 8.4 Contraseñas

1. **Política (ajustes globales):**

   | Ajuste | Por defecto |
   |---|---|
   | Longitud mínima | 8 |
   | Tipos de carácter (mayúscula, minúscula, número, símbolo) | Al menos 3 de los 4 |
   | No puede contener el usuario ni los nombres o apellidos | Sí |
   | No puede ser una contraseña común (`12345678`, `password`, `qwerty123`…) | Sí |
   | Caducidad | 365 días |
   | Aviso antes de que caduque | 15 días antes |
   | Contraseñas anteriores que no se pueden repetir | 5 |

2. **Al caducar**, la API rechaza todo con `PASSWORD_CHANGE_REQUIRED` salvo el cambio de contraseña, y la app muestra la pantalla de **cambio obligatorio**. Afecta a todos, incluido el Administrador.
3. Se comprueba al crear la cuenta, al activarla con el código, al cambiarla en el perfil, al recuperar el acceso y en el cambio anual. La app avisa mientras se escribe; decide la API.
4. **Almacenamiento:**
   - En el servidor, **hash bcrypt** (nunca texto plano). El historial guarda solo hashes. Si el servidor tiene PHP 7.3 o superior se podrá pasar a Argon2id.
   - En el teléfono **no se guarda la contraseña**: se envía por HTTPS al entrar y se olvida. En el almacenamiento seguro de Android quedan el token de renovación, el usuario recordado y el **PIN de la app como hash PBKDF2 con sal**.

## 8.5 Roles

1. Los trabajadores siguen **pidiendo** roles con solicitudes.
2. Los superiores pueden **asignar y quitar** roles directamente, a usuarios ya registrados:

   | Quién | Qué |
   |---|---|
   | Administrador | Jefe de Transporte de cualquier Entidad, y todo lo demás |
   | Jefe de Transporte | Jefe de itinerario y chofer (hacerlo o retirarlo) en su Entidad; itinerario y parada de sus trabajadores |
   | Jefe de itinerario | Itinerario y parada, solo en su itinerario |

3. **Un Jefe de itinerario solo puede serlo de un itinerario.**
4. **Historial:** cada asignación o retirada queda como una solicitud ya resuelta, con quién la hizo.
5. **Aviso:** el trabajador recibe un aviso y puede darse de baja de un rol cuando quiera.

## 8.6 "No puedo entrar" (sustituye a "Contraseña olvidada")

1. La persona marca qué olvidó: **usuario**, **contraseña** o **los dos**.
2. Escribe abreviatura de la Entidad, Pase y **teléfono**. La respuesta es siempre "Solicitud enviada", coincidan o no los datos.
3. El **Administrador** ve si los datos coinciden con un trabajador y quién es. Lo verifica por su cuenta (llamada, etc.) y **aprueba** o **rechaza**.
4. Al aprobar, **en ese mismo teléfono** (la solicitud va ligada a la instalación de la app):
   - si olvidó el usuario, la app se lo muestra;
   - si olvidó la contraseña, le deja elegir una nueva directamente.
5. **Se elimina el código por WhatsApp.**
6. **Límites:** caducidad configurable, el teléfono se borra al cerrar la solicitud y hay límite de solicitudes por hora.

## 8.7 Hablar con el desarrollador sin cuenta

1. **Botón "Hablar con el desarrollador"** en inicio de sesión, crear cuenta y unirse a la Entidad.
2. **Sin cuenta:** nombre, teléfono, motivo (los mismos motivos de conversación) y mensaje.
3. **Para saber de dónde sale:** cada conversación lleva un identificador de la instalación, la versión de la app, el modelo del teléfono y la versión de Android. En la bandeja del Administrador aparece como **"Sin cuenta"**.
4. **El Administrador responde dentro de la app**, desde su bandeja, y la respuesta le llega a ese teléfono.
5. Si después crea su cuenta en ese teléfono, la conversación pasa a su cuenta.
6. **Contra el abuso:** límite de mensajes por hora, cerrar conversaciones y bloquear instalaciones. Caducan como las demás.

## 8.8 Hijos

1. Cuatro nombres (obligatorios) y **fecha de nacimiento**, que solo ven el padre o la madre, sus jefes al aprobar y el Administrador.
2. El derecho a viajar se calcula igual: hasta el 31 de agosto siguiente a cumplir la edad máxima.
3. **Posible duplicado:** si en la misma Entidad ya hay uno con la misma fecha, primer nombre y primer apellido, se **avisa** a quien aprueba, sin bloquear.

## 8.9 Ocupación y avisos de saturación

1. **Solo cuentan los trabajadores.** Los niños van cargados y no ocupan plaza, pero sus números siempre se muestran: "35 trabajadores (+10 niños) · capacidad 40".
2. **Tres niveles:**

   | Estado | Cuándo | Color |
   |---|---|---|
   | Normal | Trabajadores ≤ asientos | Sin marca |
   | **Saturado** | Más que asientos, pero caben de pie | Naranja |
   | **Sobresaturado** | Más que asientos + capacidad de pie | Rojo |

3. **Avisos configurables por cada usuario:** recibirlos o no; nivel; de qué viajes (los suyos, su itinerario o toda su Entidad, estos dos últimos solo para jefes); cuándo (al cambiar el estado, X tiempo antes de la salida o las dos).
4. **Por defecto:** **sobresaturado** activado para los jefes y para los propios viajes; **saturado** desactivado.

## 8.10 Se elimina el orden de subida

1. Se quitan el cálculo, su algoritmo, sus pantallas y lo que anunciaba la voz.
2. La lista de pasajeros va **por parada y alfabética**.
3. La jerarquía pierde la prioridad y queda con un orden de presentación. El sexo queda solo para estadísticas.

## 8.11 Inactividad

1. **Qué cuenta como actividad:** que el chofer o el Jefe de itinerario marquen que subió, o que el sistema lo detecte. **Conducir un viaje realizado también cuenta.**
2. Solo cuentan los días en que su itinerario tuvo viajes realizados. Las ausencias aprobadas no cuentan.
3. **Aviso previo** al trabajador y **baja de su itinerario** al llegar al límite. Los plazos se fijan a nivel de Entidad.

## 8.12 Interfaz

- **Indicador de carga en el control que lanza la acción** (botón, interruptor, icono o elemento de lista), que queda desactivado mientras espera. Al cargar una pantalla o lista, el indicador aparece en esa zona. Un componente común para toda la app.
