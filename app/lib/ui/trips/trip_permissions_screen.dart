import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:miruta_alarm/miruta_alarm.dart';

import '../../services/tracking/trip_permissions.dart';
import '../navigation.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

/// Permisos para que MiRuta funcione con la app cerrada durante el viaje
/// (docs/11 §11.61 y §11.62, maqueta G23 n.º 10): ubicación «Permitir todo el
/// tiempo», batería sin restricciones, alarmas exactas y el consejo del
/// fabricante. Sin ellos funciona solo con la app abierta y lo recuerda antes
/// de cada viaje.
class TripPermissionsScreen extends StatefulWidget {
  const TripPermissionsScreen({super.key});

  @override
  State<TripPermissionsScreen> createState() => _TripPermissionsScreenState();
}

class _TripPermissionsScreenState extends State<TripPermissionsScreen> with WidgetsBindingObserver {
  TripPermissions? _p;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final p = await TripPermissions.check();
    if (mounted) setState(() => _p = p);
  }

  Future<void> _location() async {
    var permission = await Geolocator.checkPermission();
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
    } else if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      // Android 11+: «Permitir todo el tiempo» solo se elige en los ajustes de la app.
      if (permission == LocationPermission.whileInUse) await Geolocator.openAppSettings();
    } else {
      await Geolocator.openAppSettings();
    }
    await _check();
  }

  Future<void> _battery() async {
    try {
      if (!await FlutterForegroundTask.requestIgnoreBatteryOptimization()) await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    } catch (_) {
      await MirutaAlarm.openBatterySettings();
    }
    await _check();
  }

  Widget _item(bool ok, String title, String detail, String button, VoidCallback onPressed) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline, color: ok ? green : red),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(detail, style: t.textTheme.bodySmall),
              if (!ok) Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: onPressed, icon: const Icon(Icons.settings), label: Text(button))),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return AppScaffold.list(title: 'Permisos del viaje', tab: MainTab.trips, onRefresh: _check, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text('Durante su viaje MiRuta calcula su estado con la ubicación y ayuda a saber dónde va el vehículo, '
            'también con la app cerrada. Para eso Android debe dejarla funcionar en segundo plano. '
            'Fuera del viaje MiRuta no usa el GPS.'),
      ),
      if (p == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else ...[
        _item(p.locationOn, 'Ubicación activada', 'El GPS del teléfono debe estar encendido durante el viaje.', 'Activar', _location),
        _item(p.always, 'Ubicación: «Permitir todo el tiempo»',
            p.foreground ? 'Ahora solo «Mientras se usa la app»: con la app cerrada no puede calcular.' : 'Sin permiso de ubicación no se puede seguir el viaje.', 'Abrir ajustes', _location),
        _item(p.batteryUnrestricted, 'Batería: «Sin restricciones»', 'Así Android no detiene MiRuta durante el viaje.', 'Permitir', _battery),
        _item(p.exactAlarms, 'Alarmas y recordatorios', 'Para empezar a tiempo, antes de la salida, aunque la app esté cerrada.', 'Permitir', () async {
          await MirutaAlarm.openExactAlarmSettings();
          await _check();
        }),
        Card(
          child: ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Su teléfono'),
            subtitle: Text(p.manufacturerHint),
            trailing: IconButton(tooltip: 'Abrir ajustes de la app', icon: const Icon(Icons.open_in_new), onPressed: MirutaAlarm.openBatterySettings),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            p.complete
                ? 'Todo listo: MiRuta funcionará en el viaje aunque cierre la app.'
                : 'Si no los concede, MiRuta solo calcula con la app abierta y se lo recordará antes de cada viaje.',
            style: TextStyle(color: p.complete ? green : amber, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ]);
  }
}

/// Aviso de la línea del recorrido para quien viaja (maqueta G23 n.º 10):
/// sin ubicación no se ve el viaje; con ella pero sin «todo el tiempo» o con
/// la batería restringida, solo funciona con la app abierta.
class TripPermissionsCard extends StatelessWidget {
  final TripPermissions permissions;
  final VoidCallback onChanged;

  const TripPermissionsCard({super.key, required this.permissions, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final blocking = !permissions.foreground;
    final color = blocking ? red : amber;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(side: BorderSide(color: color, width: 1.5), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(blocking ? Icons.location_off : Icons.battery_alert, color: color),
            const SizedBox(width: 10),
            Expanded(
                child: Text(blocking ? 'Active la ubicación' : 'Solo con la app abierta',
                    style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 6),
          Text(blocking
              ? 'Usted viaja en este viaje: para ver su estado y la línea del recorrido, MiRuta necesita la ubicación. Su teléfono también ayuda a saber dónde va el vehículo.'
              : 'Para que MiRuta siga calculando con la app cerrada:'),
          const SizedBox(height: 6),
          Text('1. Ubicación: «Permitir todo el tiempo»\n2. Batería: «Sin restricciones»\n3. ${permissions.manufacturerHint}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () async {
                await push(context, const TripPermissionsScreen());
                onChanged();
              },
              icon: const Icon(Icons.settings),
              label: const Text('Abrir ajustes del teléfono'),
            ),
          ),
        ]),
      ),
    );
  }
}
