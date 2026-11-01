import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../models/models.dart';
import '../../services/map_tiles.dart';
import '../widgets/common.dart';

/// Elegir un punto tocando en el mapa propio (docs/09, Mapas). Sin punto
/// previo, se abre en la zona de la Entidad o, si no se conoce, en Cuba.
class MapPickerScreen extends StatefulWidget {
  final LatLng? initial;

  const MapPickerScreen({super.key, this.initial});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _controller = MapController();
  LatLng? _point;
  MapConfig? _config;

  @override
  void initState() {
    super.initState();
    _point = widget.initial;
    MapTiles.config(context.api).then((config) {
      if (mounted) setState(() => _config = config);
    });
  }

  Future<void> _myLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
    final position = await Geolocator.getCurrentPosition();
    final point = LatLng(position.latitude, position.longitude);
    setState(() => _point = point);
    _controller.move(point, 17);
  }

  LatLngBounds _bounds(GeoBox box) => LatLngBounds(LatLng(box.south, box.west), LatLng(box.north, box.east));

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ubicación de la parada'),
        actions: [
          TextButton.icon(
            onPressed: _point == null ? null : () => Navigator.pop(context, _point),
            icon: const Icon(Icons.check),
            label: const Text('Aceptar ubicación'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(tooltip: 'Mi ubicación', onPressed: _myLocation, child: const Icon(Icons.my_location)),
      body: config == null
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: _point ?? const LatLng(21.5, -79.5),
                initialZoom: _point == null ? 7 : 16,
                initialCameraFit: _point != null
                    ? null
                    : CameraFit.bounds(bounds: _bounds(config.area ?? config.bounds), padding: const EdgeInsets.all(24)),
                minZoom: config.minZoom.toDouble(),
                maxZoom: config.maxZoom.toDouble(),
                cameraConstraint: MapTiles.constraint(config),
                onTap: (_, point) => setState(() => _point = point),
              ),
              children: [
                MapTiles.layer(context.api, config),
                if (_point != null) MarkerLayer(markers: [Marker(point: _point!, width: 40, height: 40, child: const Icon(Icons.location_on, size: 40, color: Colors.red))]),
                const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')]),
              ],
            ),
    );
  }
}
