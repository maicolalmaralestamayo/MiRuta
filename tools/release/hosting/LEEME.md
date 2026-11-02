# MiRuta en el hospedaje compartido (solo FTP)

Este paquete instala el servidor de MiRuta en un hospedaje que solo da FTP
(sin SSH ni cron). Todo lo que antes eran comandos se hace ahora **desde la
app**, en *Mantenimiento del servidor*.

La configuración ya viene preparada con los datos de su hospedaje:
`htdocs/miruta/servidor/configuracion.php` incluye la base de datos, la
carpeta temporal y unas claves secretas generadas solo para usted.
**Guarde una copia de ese archivo y de `CLAVE-DE-MANTENIMIENTO.txt`** en un
lugar seguro.

La dirección del servidor queda así: `http://www.twintechnology.cu/miruta`.

## Contenido

| Carpeta | Para qué |
|---|---|
| `subida-rapida/` | Todo en un solo `.zip` más `desempaquetar.php`: solo hay que subir 2 archivos (opción A). |
| `htdocs/miruta/` | Lo mismo, ya desempaquetado (opción B, si la opción A no funciona). |
| `base-de-datos/` | La base de datos inicial en SQL, por si prefiere importarla usted mismo (paso 4, alternativa). |

## 1. Conectarse con FileZilla

En *Archivo > Gestor de sitios > Nuevo sitio*:

- **Servidor**: `190.92.127.206`
- **Protocolo**: FTP. **Cifrado**: *Requiere FTP explícito sobre TLS*.
- **Usuario**: `twintechnologyftp`. **Contraseña**: la que le dé el Soporte 24 horas.
- En *Opciones de transferencia*: modo **pasivo**, como mucho **2** conexiones.

En *Edición > Opciones > Transferencias*, ponga como mucho 2 transferencias a
la vez, 3 reintentos y 15 segundos entre ellos. En *Edición > Opciones >
Conexión*, ponga un tiempo de espera de 60 segundos. En *Transferir > Tipo de
transferencia*, elija **Binario**.

## 2. Subir los archivos

Dentro de `/htdocs/` del servidor, cree la carpeta `miruta`.

**Opción A (rápida, recomendada).**

1. Suba a `/htdocs/miruta/` los 2 archivos de `subida-rapida/`: `miruta-servidor.zip` y `desempaquetar.php`.
2. Abra en el navegador la siguiente dirección, con su clave de mantenimiento:
   `http://www.twintechnology.cu/miruta/desempaquetar.php?clave=SU_CLAVE`

El servidor desempaqueta todo y borra los dos archivos. Al terminar, le ofrece
un enlace al diagnóstico.

**Opción B (si la A falla).** Suba el *contenido* de `htdocs/miruta/` a
`/htdocs/miruta/` del servidor. Son unos miles de archivos y tarda.
Compruebe que se suben también los archivos que empiezan por punto
(`.htaccess`, `.user.ini`). En FileZilla: *Servidor > Forzar mostrar archivos
ocultos*.

## 3. Comprobar el hospedaje

Abra: `http://www.twintechnology.cu/miruta/diagnostico.php?clave=SU_CLAVE`

Todo debe salir con ✔. Lo más habitual:

- **Versión de PHP**: hace falta de **7.2.5 a 8.0**. Se probó con 7.2 y con 8.0.
  Si el hospedaje tiene otra, pida al Soporte 24 horas que ponga PHP 7.4 u 8.0
  para el sitio.
- **Carpeta de archivos subidos no escribible**: en FileZilla, botón derecho
  sobre `/htdocs/miruta/uploads` > *Permisos de archivo* > `775`. Si sigue
  igual, `777`. Marque *Recurrir a subdirectorios > Aplicar solo a directorios*.
- **Base de datos no conecta**: revise los datos en
  `servidor/configuracion.php` (*botón derecho > Ver/Editar* en FileZilla).

Compruebe también que el código está protegido. Al abrir
`http://www.twintechnology.cu/miruta/servidor/composer.json` debe salir
*Forbidden* (prohibido). Si se ve el archivo, avise al Soporte de que el
`.htaccess` no se aplica (hace falta `AllowOverride All`).

## 4. Instalar la base de datos (desde la app)

1. Instale MiRuta 2.2.0 en el teléfono. Ya trae puesta la dirección del servidor.
2. En la pantalla de inicio de sesión, pulse el botón del servidor, compruebe
   la dirección (`http` + `www.twintechnology.cu/miruta`) y pulse
   *Conectar al servidor*.
3. Vuelva a abrir esa misma pantalla, pulse **Mantenimiento del servidor** y
   escriba la clave de mantenimiento.
4. Pulse **Instalar base de datos**. Cuando termine, los apartados de la base
   de datos deben salir en verde.

*Alternativa:* importe `base-de-datos/miruta-2.2.0-inicial.sql` desde el
gestor de la base de datos del Servicio de Utilidades
(`https://unixweb.nauta.cu/`). Entre con el usuario de la base de datos.

## 5. Crear la cuenta del Administrador

En la app, pulse *Crear cuenta*. **La primera cuenta que se crea es la del
Administrador.** Hágalo usted antes de dar la dirección a nadie.

Desde entonces, el Administrador tiene *Gestión > Mantenimiento del servidor*
sin necesidad de la clave.

## Sin cron: tareas programadas

Este hospedaje no tiene cron. Las tareas (avisos de retraso, dar por
terminados los viajes, borrar chats viejos…) se ejecutan solas mientras la
app se usa, como mucho una vez por minuto. Las diarias se hacen en la primera
petición después de su hora. En *Mantenimiento del servidor* se ve cuándo se
ejecutó cada una, y el botón *Ejecutar tareas pendientes* las lanza en ese
momento.

## Actualizar a una versión nueva

Use el **paquete de actualización** (`miruta-actualizacion-<versión>.zip`). No
lleva `configuracion.php`, así que no toca sus claves ni los datos de la base
de datos.

1. Suba los 2 archivos de `subida-rapida/` a `/htdocs/miruta/` y abra
   `desempaquetar.php?clave=SU_CLAVE`, con la misma clave de siempre.
   También puede subir el contenido de `htdocs/miruta/` por FTP.
2. En la app: *Gestión > Mantenimiento del servidor > Actualizar base de datos*.

## Seguridad y otros datos del hospedaje

- **http y https.** El sitio va por `http`. El certificado del hospedaje es
  autofirmado y solo sirve para su administración. Si más adelante consigue
  un certificado oficial y el Soporte lo instala, cambie en la app el
  protocolo a `https`.
- **Contraseña de la base de datos.** Es igual al usuario. Pida al Soporte
  que la cambie y ponga la nueva en `configuracion.php`.
- **No hacen falta** el correo, Node.js, memcache ni redis.
- **Carpeta temporal del hospedaje.** Ya está configurada:
  `/srv/www/www.twintechnology.cu/tmp`. MiRuta guarda allí su caché y su
  registro de errores, fuera de la parte pública. El registro se lee desde
  *Mantenimiento del servidor > Ver registro de errores*.
- **Archivos grandes.** Para subir las APK de las actualizaciones hace falta
  un límite de subida de unos 64 MB. El paquete lo pide en `.htaccess` y en
  `.user.ini`. Si el diagnóstico muestra menos, pídalo al Soporte.
