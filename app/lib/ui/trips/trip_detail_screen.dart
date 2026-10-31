import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../admin/trip_form_screen.dart';
import '../chat/chat_screen.dart';
import '../tracking/boarding.dart';
import '../tracking/passengers_screen.dart';
import '../tracking/tracking_screen.dart';
import '../widgets/common.dart';
import 'trip_context.dart';

class TripDetailScreen extends StatefulWidget {
  final String tripId;

  const TripDetailScreen({super.key, required this.tripId});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  final _view = GlobalKey<AsyncViewState<TripContext>>();

  Future<void> _reload() async => _view.currentState?.reload();

  Future<void> _startLeg(TripContext data, String direction) async {
    final ok = await runAction(context, () async {
      await context.api.post('/trip-legs', resourceData('trip-legs', attributes: {'direction': direction}, relationships: {
        'trip': ResourceId('trips', data.trip.id),
      }));
    });
    if (ok && mounted) {
      final fresh = await TripContext.load(context.api, data.trip.id);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => TrackingScreen(tripId: data.trip.id, legId: fresh.leg(direction)!.id)));
      _reload();
    }
  }

  Future<void> _markCompleted(TripContext data) async {
    if (!await confirm(context, 'Marcar como realizado', '¿El viaje se realizó?')) return;
    if (!mounted) return;
    await runAction(context, () => context.api.post('/trip-completions', resourceData('trip-completions', relationships: {
          'trip': ResourceId('trips', data.trip.id),
        })), success: 'Viaje marcado como realizado');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.me;
    return Scaffold(
      appBar: AppBar(title: const Text('Viaje')),
      body: AsyncView<TripContext>(
        key: _view,
        load: () => TripContext.load(context.api, widget.tripId),
        builder: (context, data, reload) {
          final trip = data.trip;
          final operate = data.canOperate(me);
          final passenger = data.isPassenger(me);
          final active = data.activeLeg;
          final departure = data.stop(trip.departureStopId);
          final returnStop = data.stop(trip.returnStopId);

          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            ListTile(
              title: Text(trip.itineraryName ?? '', style: Theme.of(context).textTheme.titleLarge),
              subtitle: Text(TripStatus.label(trip.status)),
              trailing: StatusChip(TripStatus.label(trip.status), color: tripStatusColor(trip.status)),
            ),
            if ((operate || me.managesTransport) && trip.overloaded) OverloadBanner(expected: trip.expectedPassengers, capacity: trip.totalCapacity),
            if (me.managesTransport && trip.needsReassignment)
              const ListTile(leading: Icon(Icons.person_off, color: Colors.red), title: Text('El chofer de este viaje se dio de baja. Hay que reasignarlo.')),
            Card(
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.north_east),
                  title: Text('Salida: ${formatDateTime(trip.departsAt)}'),
                  subtitle: Text(departure == null ? '' : '${departure.landmark}\n${departure.address}'),
                ),
                ListTile(
                  leading: const Icon(Icons.south_west),
                  title: Text('Regreso: ${formatDateTime(trip.returnsAt)}'),
                  subtitle: Text(returnStop == null ? '' : '${returnStop.landmark}\n${returnStop.address}'),
                ),
              ]),
            ),
            Card(
              child: Column(children: [
                ListTile(leading: const Icon(Icons.directions_bus), title: Text('${trip.vehicleTypeName ?? ''} ${trip.vehiclePlate ?? ''}'), subtitle: Text('Capacidad: ${trip.totalCapacity} pasajeros')),
                ListTile(leading: const Icon(Icons.person), title: Text(trip.driverName ?? 'Sin chofer'), subtitle: const Text('Chofer')),
                ListTile(
                  leading: const Icon(Icons.people_alt_outlined),
                  title: Text('${trip.expectedPassengers} pasajeros esperados'),
                  subtitle: Text('${trip.expectedChildren} niños'),
                ),
              ]),
            ),
            if (trip.isConfirmed)
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: const Text('Chat del viaje'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen.trip(tripId: trip.id, title: trip.itineraryName ?? 'Viaje'))),
              ),
            const SectionTitle('Recorrido'),
            for (final leg in data.legs)
              ListTile(
                leading: Icon(leg.isActive ? Icons.radar : Icons.flag_outlined, color: leg.isActive ? Theme.of(context).colorScheme.primary : null),
                title: Text('${leg.directionLabel}${leg.isActive ? ' · en curso' : ' · terminado'}'),
                subtitle: Text('Inicio ${formatTime(leg.startedAt)}${leg.endedAt == null ? '' : ' · fin ${formatTime(leg.endedAt!)}'} · ${leg.stopPasses.length} paradas pasadas'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => TrackingScreen(tripId: trip.id, legId: leg.id)));
                  reload();
                },
              ),
            if (data.legs.isEmpty) const ListTile(title: Text('El recorrido aún no ha comenzado.')),
            if (passenger && active != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: () => selfBoarding(context, active, me.childrenCount),
                    icon: const Icon(Icons.how_to_reg),
                    label: const Text('Ya subí'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BoardingPassScreen(leg: active))),
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('Mi QR'),
                  ),
                ]),
              ),
            ],
            if (operate) ...[
              const SectionTitle('Control del viaje'),
              if (trip.isConfirmed && data.leg('outbound') == null)
                ListTile(leading: const Icon(Icons.play_arrow), title: const Text('Iniciar recorrido de salida'), onTap: () => _startLeg(data, 'outbound')),
              if (trip.isConfirmed && data.leg('return') == null)
                ListTile(leading: const Icon(Icons.play_arrow), title: const Text('Iniciar recorrido de regreso'), onTap: () => _startLeg(data, 'return')),
              ListTile(
                leading: const Icon(Icons.format_list_numbered),
                title: const Text('Pasajeros en orden de subida'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PassengersScreen(context: data))),
              ),
              if (trip.status != TripStatus.cancelled && trip.status != TripStatus.completed)
                ListTile(leading: const Icon(Icons.task_alt), title: const Text('Marcar como realizado'), onTap: () => _markCompleted(data)),
            ],
            if (me.canPlan(trip.itineraryId))
              ListTile(
                leading: const Icon(Icons.edit_calendar),
                title: const Text('Editar viaje'),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => TripFormScreen(trip: trip)));
                  reload();
                },
              ),
          ]);
        },
      ),
    );
  }
}
