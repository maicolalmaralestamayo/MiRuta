import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_client.dart';
import '../core/server_url.dart';
import '../core/storage.dart';
import 'installation.dart';

/// Versión publicada en el servidor.
class AppUpdate {
  final String versionName;
  final int versionCode;
  final String? notes;
  final String downloadUrl;
  final String sha256;
  final int sizeBytes;
  final bool mandatory;

  /// Tipo de procesador del APK (arm64-v8a, armeabi-v7a o universal).
  final String abi;

  AppUpdate({
    required this.versionName,
    required this.versionCode,
    this.notes,
    required this.downloadUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.mandatory,
    this.abi = 'universal',
  });

  String get sizeLabel => '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Actualizaciones de la app desde el propio servidor, con un APK por tipo
/// de procesador (docs/08-version-2.md §8.1).
class AppUpdates {
  static const _notifiedKey = 'update.notified_code';

  /// Ajuste del teléfono: descargar las actualizaciones solo con Wi-Fi
  /// (desactivado por defecto). Las obligatorias se descargan siempre.
  static const wifiOnlyKey = 'updates.wifi_only';

  static const _channel = MethodChannel('mitransporte/app');

  /// El teléfono usa datos móviles (no Wi-Fi ni cable).
  static Future<bool> onMobileData() async {
    final types = await Connectivity().checkConnectivity();
    return types.contains(ConnectivityResult.mobile) && !types.contains(ConnectivityResult.wifi) && !types.contains(ConnectivityResult.ethernet);
  }

  /// Hay que avisar antes de descargar: el usuario quiere solo Wi-Fi y está con datos.
  static Future<bool> shouldWarnMobileData() async =>
      await Storage.getBool(wifiOnlyKey, fallback: false) && await onMobileData();

  static Future<int> currentVersionCode() async => int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  static Future<String> currentVersionName() async => (await PackageInfo.fromPlatform()).version;

  /// La versión nueva disponible, o null si la app está al día.
  static Future<AppUpdate?> check(ApiClient api) async {
    final current = await currentVersionCode();
    final abis = await Installation.supportedAbis();
    final document = await api.get('/app-versions/latest', query: {'filter[currentVersionCode]': current, 'filter[abis]': abis.join(',')});
    if (document.meta['updateAvailable'] != true || document.resources.isEmpty) return null;
    final file = document.meta['file'] as Map?;
    if (file == null) return null;
    final r = document.resource;
    return AppUpdate(
      versionName: r.string('versionName') ?? '',
      versionCode: r.integer('versionCode') ?? 0,
      notes: r.string('notes'),
      downloadUrl: file['downloadUrl'] as String,
      sha256: file['sha256'] as String,
      sizeBytes: (file['sizeBytes'] as num?)?.toInt() ?? 0,
      mandatory: document.meta['mandatory'] == true,
      abi: file['abi'] as String? ?? 'universal',
    );
  }

  /// "Compartir la app" (docs/08-version-2.md §8.1). Si el APK pedido es del
  /// mismo tipo que el instalado, se comparte el del teléfono (sin gastar
  /// datos, p. ej. por Bluetooth o Quick Share); si no, se descarga del servidor.
  static Future<void> share(ApiClient api, {required bool arm64}) async {
    final wanted = arm64 ? 'arm64-v8a' : 'armeabi-v7a';
    final installed = Map<String, dynamic>.from(await _channel.invokeMethod('installedApk') as Map);
    final nativeDir = installed['nativeLibraryDir'] as String? ?? '';
    final installedIs64 = nativeDir.endsWith('arm64') || nativeDir.endsWith('arm64-v8a');
    final name = (await PackageInfo.fromPlatform()).version;
    final temp = await getTemporaryDirectory();
    final target = File('${temp.path}/MiTransporte-$name-${arm64 ? '64' : '32'}bits.apk');

    if (installedIs64 == arm64) {
      await File(installed['path'] as String).copy(target.path);
    } else {
      final document = await api.get('/app-versions/latest', query: {'filter[abis]': wanted});
      final file = document.meta['file'] as Map?;
      if (file == null) throw StateError('No hay un APK publicado para ese tipo de teléfono.');
      await Dio().download(file['downloadUrl'] as String, target.path);
    }

    await SharePlus.instance.share(ShareParams(
      files: [XFile(target.path, mimeType: 'application/vnd.android.package-archive')],
      text: 'MiTransporte: ábrelo para instalar la app. Dirección del servidor: ${ServerUrl.short(api.baseUrl)}',
    ));
  }

  /// Descarga el APK (comprobando su huella SHA-256) y abre el instalador de Android.
  static Stream<OtaEvent> install(AppUpdate update) {
    return OtaUpdate().execute(
      update.downloadUrl,
      destinationFilename: 'mitransporte-${update.versionCode}.apk',
      sha256checksum: update.sha256,
    );
  }

  /// Para avisar de cada versión una sola vez en segundo plano.
  static Future<bool> shouldNotify(AppUpdate update) async {
    final notified = int.tryParse(await Storage.getString(_notifiedKey) ?? '') ?? 0;
    if (notified >= update.versionCode) return false;
    await Storage.setString(_notifiedKey, '${update.versionCode}');
    return true;
  }
}
