# MiTransporte — App Android

App Flutter de MiTransporte. La documentación funcional está en [`../docs`](../docs/README.md) (pantallas en `05-app.md`).

## Requisitos

- Flutter 3.47 o superior (Dart 3.13).
- Android SDK con la plataforma 36. La app funciona desde Android 7.0 (API 24).

## Ejecutar

La app **no lleva ninguna dirección de servidor**. La primera vez que se abre pide la **dirección del servidor** (p. ej. `transporte.miempresa.com`), la completa (`https://…/api/v1`), comprueba que ahí responde MiTransporte y la guarda. Se cambia desde el botón **Servidor** de la pantalla de inicio de sesión. Al compartir la app, el mensaje incluye la dirección del servidor.

```bash
cd app
flutter pub get
flutter run
```

Para desarrollar se puede dar una dirección de partida con `--dart-define=API_URL=…`, p. ej. con el emulador de Android y la API en el propio ordenador: `--dart-define=API_URL=http://10.0.2.2:8000/api/v1`. Las direcciones `http://` solo se permiten en las versiones de depuración; en producción hace falta HTTPS.

## Compilar los APK

Cada versión se publica con **dos APK**: uno para teléfonos de 64 bits (la mayoría) y otro para los de 32 bits. Cada teléfono descarga el suyo (docs/08-version-2.md §8.1).

```bash
./build_release.sh
# Resultado: build/release/<versión>/MiTransporte-<versión>-64bits.apk y -32bits.apk
```

El script compila dos veces:

```bash
flutter build apk --release --target-platform android-arm64 \
  --obfuscate --split-debug-info=build/symbols/<versión>
flutter build apk --release --target-platform android-arm \
  --obfuscate --split-debug-info=build/symbols/<versión>
```

Qué hace cada opción para bajar el peso:

- `--target-platform` deja solo un tipo de procesador en cada APK (también en las librerías de los plugins, ver `android/app/build.gradle.kts`). Los dos APK tienen el **mismo código de versión**.
- Las librerías nativas van **comprimidas** dentro del APK (`useLegacyPackaging`). Android las descomprime al instalar.
- `--obfuscate --split-debug-info=…` quita del APK la información de depuración del código Dart y la guarda aparte. **Guarda la carpeta `build/symbols/<versión>`** de cada versión publicada: sin ella no se pueden leer los errores que lleguen de esa versión (`flutter symbolize -i <traza> -d build/symbols/<versión>/app.android-arm64.symbols`).

Cada APK queda en torno a 12–13 MB (antes uno solo de 25 MB, y al principio 86 MB).

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
2. Compila los dos APK firmados con `./build_release.sh` (ver [Compilar los APK](#compilar-los-apk)).
3. En la app, como Administrador: **Más → Gestión → Actualizaciones de la app → Publicar versión**. Elige los dos APK (64 y 32 bits) y escribe la versión, el código, las novedades y si es obligatoria.

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
  core/        Cliente JSON:API (renovación de tokens), almacenamiento, reglas de usuario y contraseña
  models/      Modelos construidos a partir de los recursos JSON:API
  services/    Sesión, ajustes, notificaciones, sincronización, recorrido en segundo plano, voz
  ui/          Pantallas por área (auth, home, trips, tracking, applications, chat, profile, stats, settings, admin)
```

## Funcionamiento en segundo plano

- **Sincronización periódica** (`workmanager`): viajes, avisos y mensajes, con la frecuencia que elige el usuario (Android no permite menos de 15 minutos). Programa los avisos de salida y regreso y avisa de los cambios.
- **Recorrido** (`flutter_foreground_task`): mientras se comparte la ubicación o se sigue un recorrido con la app cerrada, un servicio en primer plano con notificación fija envía la posición (y la guarda si no hay cobertura) y avisa del paso por las paradas.
