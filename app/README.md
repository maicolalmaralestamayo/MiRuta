# MiTransporte — App Android

App Flutter de MiTransporte. La documentación funcional está en [`../docs`](../docs/README.md) (pantallas en `05-app.md`).

## Requisitos

- Flutter 3.47 o superior (Dart 3.13).
- Android SDK con la plataforma 36. La app funciona desde Android 7.0 (API 24).

## Ejecutar

La dirección de la API se fija al compilar con `API_URL` y también se puede cambiar desde la pantalla de inicio de sesión (botón **Servidor**):

```bash
cd app
flutter pub get
flutter run --dart-define=API_URL=https://mi-servidor/api/v1
```

Con el emulador de Android y la API en el propio ordenador: `--dart-define=API_URL=http://10.0.2.2:8000/api/v1`. Las direcciones `http://` solo se permiten en las versiones de depuración; en producción hace falta HTTPS.

## Compilar el APK

```bash
flutter build apk --release --dart-define=API_URL=https://mi-servidor/api/v1
# Resultado: build/app/outputs/flutter-apk/app-release.apk
```

### Firma

Todas las versiones deben firmarse con **la misma clave**; si cambia, Android no instala la actualización encima de la anterior y habría que desinstalar la app en cada teléfono.

La clave y sus contraseñas **no se suben al repositorio**. Para compilar hacen falta dos archivos en `android/`:

- `keystore/mitransporte-release.jks`: la clave.
- `key.properties`:

  ```properties
  storeFile=keystore/mitransporte-release.jks
  storePassword=…
  keyAlias=mitransporte
  keyPassword=…
  ```

Guárdalos en un lugar seguro y con copia de respaldo. Sin `key.properties` se firma con la clave de depuración (solo sirve para pruebas).

## Publicar una actualización

1. Sube el número de versión en `pubspec.yaml`, por ejemplo de `1.0.0+1` a `1.1.0+2`. El número después del `+` es el **código de versión** y tiene que ser mayor que el anterior.
2. Compila el APK firmado: `flutter build apk --release --dart-define=API_URL=…`.
3. En la app, como Administrador: **Más → Gestión → Actualizaciones de la app → Publicar versión**. Elige el APK y escribe la versión, el código, las novedades y si es obligatoria.

Los teléfonos lo detectan al abrir la app o en la siguiente sincronización.

## Pruebas

```bash
flutter analyze
flutter test
```

`test/api_contract_test.dart` interpreta respuestas **reales** de la API guardadas en `test/fixtures/`. Si cambia la API, hay que regenerarlas ejecutando el escenario completo contra un servidor de desarrollo.

## Estructura

```
lib/
  core/        Cliente JSON:API (renovación de tokens), almacenamiento, carné de identidad
  models/      Modelos construidos a partir de los recursos JSON:API
  services/    Sesión, ajustes, notificaciones, sincronización, recorrido en segundo plano, voz
  ui/          Pantallas por área (auth, home, trips, tracking, applications, chat, profile, stats, settings, admin)
```

## Funcionamiento en segundo plano

- **Sincronización periódica** (`workmanager`): viajes, avisos y mensajes, con la frecuencia que elige el usuario (Android no permite menos de 15 minutos). Programa los avisos de salida y regreso y avisa de los cambios.
- **Recorrido** (`flutter_foreground_task`): mientras se comparte la ubicación o se sigue un recorrido con la app cerrada, un servicio en primer plano con notificación fija envía la posición (y la guarda si no hay cobertura) y avisa del paso por las paradas.
