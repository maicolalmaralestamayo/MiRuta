import 'dart:io';

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

/// Versión publicada en el servidor con el APK para este teléfono.
class AppUpdate {
  final String versionName;
  final int versionCode;
  final String? notes;
  final String? downloadUrl;
  final String? sha256;
  final int sizeBytes;
  final bool mandatory;

  const AppUpdate({required this.versionName, required this.versionCode, this.notes, this.downloadUrl, this.sha256, this.sizeBytes = 0, this.mandatory = false});

  String get sizeLabel => '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  Map<String, dynamic> toJson() => {'versionName': versionName, 'versionCode': versionCode, 'notes': notes, 'downloadUrl': downloadUrl, 'sha256': sha256, 'sizeBytes': sizeBytes};

  factory AppUpdate.fromJson(Map<String, dynamic> j) => AppUpdate(
        versionName: '${j['versionName'] ?? ''}',
        versionCode: (j['versionCode'] as num?)?.toInt() ?? 0,
        notes: j['notes'] as String?,
        downloadUrl: j['downloadUrl'] as String?,
        sha256: j['sha256'] as String?,
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        mandatory: true,
      );
}

/// Actualizaciones de la app desde el propio servidor (un APK de 64 y otro de
/// 32 bits) y actualización obligatoria (docs/11 §11.54).
class AppUpdates {
  /// La obligación se recuerda en el teléfono aunque no haya conexión (no
  /// empieza por «user.»: no se borra al cerrar la sesión).
  static const _mandatoryKey = 'update.mandatory';
  static const _notifiedKey = 'update.notified_code';
  static const _channel = MethodChannel('mitransporte/app');

  static Future<int> currentVersionCode() async => int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  static Future<String> currentVersionName() async => (await PackageInfo.fromPlatform()).version;

  /// La versión nueva disponible para este teléfono, o null si está al día.
  /// Si es obligatoria, la recuerda.
  static Future<AppUpdate?> check(ApiClient api) async {
    final current = await currentVersionCode();
    final abis = await Installation.supportedAbis();
    final document = await api.get('/app-versions/latest', query: {'filter[currentVersionCode]': current, 'filter[abis]': abis.join(',')});
    if (document.meta['updateAvailable'] != true || document.resources.isEmpty) {
      await clearMandatory();
      return null;
    }
    final file = document.meta['file'] as Map?;
    final r = document.resource;
    final update = AppUpdate(
      versionName: r.string('versionName') ?? '',
      versionCode: r.integer('versionCode') ?? 0,
      notes: r.string('notes'),
      downloadUrl: file?['downloadUrl'] as String?,
      sha256: file?['sha256'] as String?,
      sizeBytes: (file?['sizeBytes'] as num?)?.toInt() ?? 0,
      mandatory: document.meta['mandatory'] == true,
    );
    if (update.mandatory) {
      await Storage.setJson(_mandatoryKey, update.toJson());
    } else {
      await clearMandatory();
    }
    return update;
  }

  /// Recibió 426 APP_UPDATE_REQUIRED: se recuerda la obligación.
  static Future<void> rememberMandatory(Map<String, dynamic> meta) async {
    final existing = await mandatory();
    await Storage.setJson(_mandatoryKey, {
      'versionCode': meta['mandatoryVersionCode'] ?? meta['latestVersionCode'] ?? existing?.versionCode ?? 0,
      'versionName': meta['latestVersionName'] ?? existing?.versionName ?? '',
      'downloadUrl': existing?.downloadUrl,
      'sha256': existing?.sha256,
      'sizeBytes': existing?.sizeBytes ?? 0,
    });
  }

  /// La actualización obligatoria pendiente (aunque no haya conexión).
  static Future<AppUpdate?> mandatory() async {
    final json = await Storage.getJson(_mandatoryKey);
    if (json['versionCode'] == null) return null;
    final update = AppUpdate.fromJson(json);
    if (update.versionCode != 0 && update.versionCode <= await currentVersionCode()) {
      await clearMandatory();
      return null;
    }
    return update;
  }

  static Future<void> clearMandatory() => Storage.setString(_mandatoryKey, null);

  /// Descarga el APK (comprobando su huella SHA-256) y abre el instalador.
  static Stream<OtaEvent> install(AppUpdate update) => OtaUpdate().execute(
        update.downloadUrl!,
        destinationFilename: 'miruta-${update.versionCode}.apk',
        sha256checksum: update.sha256,
      );

  /// Para avisar de cada versión una sola vez.
  static Future<bool> shouldNotify(int versionCode) async {
    final notified = int.tryParse(await Storage.getString(_notifiedKey) ?? '') ?? 0;
    if (notified >= versionCode) return false;
    await Storage.setString(_notifiedKey, '$versionCode');
    return true;
  }

  /// «Compartir la app»: el APK instalado si es del tipo pedido; si no, el del servidor.
  static Future<void> share(ApiClient api, {required bool arm64}) async {
    final installed = Map<String, dynamic>.from(await _channel.invokeMethod('installedApk') as Map);
    final nativeDir = installed['nativeLibraryDir'] as String? ?? '';
    final installedIs64 = nativeDir.endsWith('arm64') || nativeDir.endsWith('arm64-v8a');
    final name = (await PackageInfo.fromPlatform()).version;
    final temp = await getTemporaryDirectory();
    final target = File('${temp.path}/miruta-$name-${arm64 ? '64' : '32'}bits.apk');
    if (installedIs64 == arm64) {
      await File(installed['path'] as String).copy(target.path);
    } else {
      final document = await api.get('/app-versions/latest', query: {'filter[abis]': arm64 ? 'arm64-v8a' : 'armeabi-v7a'});
      final file = document.meta['file'] as Map?;
      if (file == null) throw StateError('No hay un APK publicado para ese tipo de teléfono.');
      await Dio().download(file['downloadUrl'] as String, target.path);
    }
    await SharePlus.instance.share(ShareParams(
      files: [XFile(target.path, mimeType: 'application/vnd.android.package-archive')],
      text: 'MiRuta: ábralo para instalar la app. Servidor: ${ServerUrl.short(api.baseUrl)}',
    ));
  }
}
