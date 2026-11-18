# MiRuta 4.5.0: entregas

| Archivo | Para qué |
|---|---|
| `miruta-4.5.0-32bits.apk` | App para teléfonos de 32 bits (armeabi-v7a). |
| `miruta-4.5.0-64bits.apk` | App para teléfonos de 64 bits (arm64-v8a). |
| `miruta-servidor-4.5.0.zip` | Servidor completo (instalación desde cero). **Genera claves nuevas**: si se usa sobre un servidor existente, cierra las sesiones e invalida los QR. Los datos de la base de datos vienen como `CAMBIAR`: edite `servidor/configuracion.php` por FTP (DB_HOST, DB_DATABASE, DB_USERNAME, DB_PASSWORD) antes de usarlo. |
| `miruta-actualizacion-4.5.0.zip` | Actualización del servidor, sin `configuracion.php`: conserva la configuración y las claves del servidor instalado. Después: *Mantenimiento del servidor → Actualizar base de datos*. |
