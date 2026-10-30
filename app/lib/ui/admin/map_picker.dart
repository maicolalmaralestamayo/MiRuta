import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Elegir un punto tocando en el mapa (OpenStreetMap).
class MapPickerScreen extends StatefulWidget {
  final LatLng? initial;

  const MapPickerScreen({super.key, this.initial});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _controller = MapController();
  LatLng? _point;

  @override
  void initState() {
    super.initState();
    _point = widget.initial;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ubicación de la parada'),
        actions: [TextButton(onPressed: _point == null ? null : () => Navigator.pop(context, _point), child: const Text('Aceptar'))],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _myLocation, child: const Icon(Icons.my_location)),
      body: FlutterMap(
        mapController: _controller,
        options: MapOptions(
          initialCenter: _point ?? const LatLng(0, 0),
          initialZoom: _point == null ? 2 : 16,
          onTap: (_, point) => setState(() => _point = point),
        ),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.mitransporte.mitransporte'),
          if (_point != null) MarkerLayer(markers: [Marker(point: _point!, width: 40, height: 40, child: const Icon(Icons.location_on, size: 40, color: Colors.red))]),
          const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')]),
        ],
      ),
    );
  }
}
