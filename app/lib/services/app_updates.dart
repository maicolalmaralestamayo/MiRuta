import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/api_client.dart';
import '../core/storage.dart';

/// Versión publicada en el servidor.
class AppUpdate {
  final String versionName;
  final int versionCode;
  final String? notes;
  final String downloadUrl;
  final String sha256;
  final int sizeBytes;
  final bool mandatory;

  AppUpdate({
    required this.versionName,
    required this.versionCode,
    this.notes,
    required this.downloadUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.mandatory,
  });

  String get sizeLabel => '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Actualizaciones de la app desde el propio servidor.
class AppUpdates {
  static const _notifiedKey = 'update.notified_code';

  static Future<int> currentVersionCode() async => int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  static Future<String> currentVersionName() async => (await PackageInfo.fromPlatform()).version;

  /// La versión nueva disponible, o null si la app está al día.
  static Future<AppUpdate?> check(ApiClient api) async {
    final current = await currentVersionCode();
    final document = await api.get('/app-versions/latest', query: {'filter[currentVersionCode]': current});
    if (document.meta['updateAvailable'] != true || document.resources.isEmpty) return null;
    final r = document.resource;
    return AppUpdate(
      versionName: r.string('versionName') ?? '',
      versionCode: r.integer('versionCode') ?? 0,
      notes: r.string('notes'),
      downloadUrl: r.string('downloadUrl')!,
      sha256: r.string('sha256')!,
      sizeBytes: r.integer('sizeBytes') ?? 0,
      mandatory: document.meta['mandatory'] == true,
    );
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
