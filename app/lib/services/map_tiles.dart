import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../core/storage.dart';
import '../models/models.dart';
import 'app_updates.dart';

/// Mapa propio (docs/09-repaso-pantallas.md, Mapas): las imágenes las dibuja
/// el servidor de la empresa, la vista no sale de Cuba y cada imagen vista
/// se guarda en el teléfono (también se puede descargar la zona de la
/// Entidad para usarla sin conexión). La app no crece: usa el mismo
/// componente de mapa de siempre.
class MapTiles {
  static const _configKey = 'map.config';
  static const _downloadedAtKey = 'map.area_downloaded_at';

  /// Límites de Cuba por si aún no se ha podido leer la configuración.
  static const defaultBounds = GeoBox(south: 19.6, west: -85.2, north: 23.45, east: -73.9);

  static MapConfig? _config;
  static Directory? _cacheDir;

  /// Configuración del servidor (GET /map), guardada para usarla sin conexión.
  static Future<MapConfig> config(ApiClient api) async {
    try {
      final document = await api.get('/map');
      _config = MapConfig.fromJson(Map<String, dynamic>.from(document.resource.attributes));
      await Storage.setJson(_configKey, _config!.toJson());
    } catch (_) {
      if (_config == null) {
        final cached = await Storage.getJson(_configKey);
        _config = cached.isEmpty
            ? MapConfig(tilesUrl: '/tiles/{z}/{x}/{y}.png', bounds: defaultBounds)
            : MapConfig.fromJson(cached);
      }
    }
    return _config!;
  }

  /// Plantilla completa de las imágenes: relativa a la dirección del servidor (sin /api/v1).
  static String urlTemplate(ApiClient api, MapConfig config) {
    if (config.tilesUrl.startsWith('http')) return config.tilesUrl;
    final base = api.baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');
    return '$base${config.tilesUrl.startsWith('/') ? '' : '/'}${config.tilesUrl}';
  }

  /// La vista no sale de Cuba.
  static CameraConstraint constraint(MapConfig config) => CameraConstraint.containCenter(
        bounds: LatLngBounds(LatLng(config.bounds.south, config.bounds.west), LatLng(config.bounds.north, config.bounds.east)),
      );

  /// Capa del mapa con las imágenes del servidor propio y la caché del teléfono.
  static TileLayer layer(ApiClient api, MapConfig config) => TileLayer(
        urlTemplate: urlTemplate(api, config),
        minZoom: config.minZoom.toDouble(),
        maxZoom: config.maxZoom.toDouble(),
        tileProvider: CachedTileProvider(),
        userAgentPackageName: 'com.mitransporte.mitransporte',
      );

  static Future<Directory> cacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/tiles');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _cacheDir = dir;
  }

  static Future<File> tileFile(int z, int x, int y) async => File('${(await cacheDir()).path}/$z/$x/$y.png');

  /// Cuántas imágenes tiene la zona de la Entidad.
  static int areaTileCount(MapConfig config) {
    final area = config.area;
    if (area == null) return 0;
    var count = 0;
    for (var z = config.downloadMinZoom; z <= config.downloadMaxZoom; z++) {
      final (x0, y0, x1, y1) = _range(area, z);
      count += (x1 - x0 + 1) * (y1 - y0 + 1);
    }
    return count;
  }

  /// Descarga la zona de la Entidad (sus paradas con margen). Respeta el
  /// ajuste "solo con Wi-Fi" de las actualizaciones. Devuelve las descargadas.
  static Future<int> downloadArea(ApiClient api, {void Function(int done, int total)? onProgress}) async {
    final config = await MapTiles.config(api);
    final area = config.area;
    if (area == null) throw StateError('Su Entidad aún no tiene paradas en el mapa.');

    if (await Storage.getBool(AppUpdates.wifiOnlyKey, fallback: false)) {
      final connection = await Connectivity().checkConnectivity();
      if (!connection.contains(ConnectivityResult.wifi) && !connection.contains(ConnectivityResult.ethernet)) {
        throw StateError('Está activado "solo con Wi-Fi": conéctese a una red Wi-Fi para descargar el mapa.');
      }
    }

    final template = urlTemplate(api, config);
    final total = areaTileCount(config);
    final dio = Dio();
    var done = 0;
    var downloaded = 0;

    for (var z = config.downloadMinZoom; z <= config.downloadMaxZoom; z++) {
      final (x0, y0, x1, y1) = _range(area, z);
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          final file = await tileFile(z, x, y);
          if (!file.existsSync()) {
            final url = template.replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y');
            final response = await dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
            await file.parent.create(recursive: true);
            await file.writeAsBytes(response.data!);
            downloaded++;
          }
          done++;
          onProgress?.call(done, total);
        }
      }
    }

    await Storage.setString(_downloadedAtKey, DateTime.now().toIso8601String());
    return downloaded;
  }

  static Future<DateTime?> areaDownloadedAt() async {
    final raw = await Storage.getString(_downloadedAtKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Espacio que ocupa el mapa guardado en el teléfono.
  static Future<int> cachedBytes() async {
    final dir = await cacheDir();
    var bytes = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) bytes += await entity.length();
    }
    return bytes;
  }

  static Future<void> clearCache() async {
    final dir = await cacheDir();
    if (dir.existsSync()) await dir.delete(recursive: true);
    _cacheDir = null;
    await Storage.setString(_downloadedAtKey, null);
  }

  static (int, int, int, int) _range(GeoBox box, int z) {
    int tileX(double lng) => ((lng + 180) / 360 * (1 << z)).floor();
    int tileY(double lat) {
      final rad = lat * math.pi / 180;
      return ((1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * (1 << z)).floor();
    }

    return (tileX(box.west), tileY(box.north), tileX(box.east), tileY(box.south));
  }
}

/// Imágenes del mapa: primero las guardadas en el teléfono; si no están, se
/// descargan del servidor y se guardan.
class CachedTileProvider extends TileProvider {
  CachedTileProvider();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _CachedTileImage(coordinates.z, coordinates.x, coordinates.y, getTileUrl(coordinates, options));
}

@immutable
class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  final int z;
  final int x;
  final int y;
  final String url;

  const _CachedTileImage(this.z, this.x, this.y, this.url);

  static final _dio = Dio();

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_CachedTileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final file = await MapTiles.tileFile(z, x, y);
    Uint8List bytes;
    if (file.existsSync()) {
      bytes = await file.readAsBytes();
    } else {
      final response = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      bytes = Uint8List.fromList(response.data!);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is _CachedTileImage && other.z == z && other.x == x && other.y == y && other.url == url;

  @override
  int get hashCode => Object.hash(z, x, y, url);
}
