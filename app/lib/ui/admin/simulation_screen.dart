import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../navigation.dart';
import '../trips/trip_form_screen.dart';
import '../trips/trip_line_screen.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/busy.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

/// «Simulación» (docs/11 §11.66), en Más → Mantenimiento del servidor, solo
/// para el Administrador: viaje de prueba con trabajadores simulados que
/// el servidor hace informar como teléfonos reales. Sin simulación, el
/// formulario para «Crear Simulación»; con ella, cómo va (consultando cada
/// 10 s, lo que además la hace avanzar en el servidor), «Consultar
/// Recorrido» y «Eliminar Simulación».
class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  static const pollEvery = Duration(seconds: 10);

  WorkerSimulation? _simulation;
  bool _loaded = false;
  Object? _error;
  Timer? _timer;

  final _input = SimulationInput();
  List<Itinerary> _itineraries = const [];
  late final _workers = TextEditingController(text: '${_input.workers}');
  late final _percent = {
    'normal': TextEditingController(text: '${_input.normal}'),
    'late': TextEditingController(text: '${_input.late}'),
    'leftBehind': TextEditingController(text: '${_input.leftBehind}'),
    'notGoing': TextEditingController(text: '${_input.notGoing}'),
  };

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(pollEvery, (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _workers.dispose();
    for (final c in _percent.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final api = context.read<Session>().api;
    try {
      final list = await api.getAll('/simulations');
      final simulation = list.isEmpty ? null : WorkerSimulation.from(list.first);
      var itineraries = _itineraries;
      if (simulation == null && itineraries.isEmpty) {
        itineraries = (await api.getAll('/itineraries', query: {'include': 'entity', 'filter[active]': 'true'})).map(Itinerary.from).toList();
      }
      if (!mounted) return;
      setState(() {
        _simulation = simulation;
        _itineraries = itineraries;
        _input.itineraryId ??= itineraries.length == 1 ? itineraries.first.id : null;
        _loaded = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (!quiet || !_loaded) setState(() => _error = error);
    }
  }

  void _readFields() {
    int value(TextEditingController c) => int.tryParse(c.text.trim()) ?? -1;
    _input.workers = value(_workers);
    _input.normal = value(_percent['normal']!);
    _input.late = value(_percent['late']!);
    _input.leftBehind = value(_percent['leftBehind']!);
    _input.notGoing = value(_percent['notGoing']!);
  }

  Future<void> _create() async {
    _readFields();
    final problem = _input.error;
    if (problem != null) throw StateError(problem);
    final document = await context.read<Session>().api.post('/simulations',
        resourceData('simulations', attributes: _input.attributes(), relationships: {'itinerary': ResourceId('itineraries', _input.itineraryId!)}));
    if (mounted) setState(() => _simulation = WorkerSimulation.from(document.resource));
  }

  Future<void> _delete(WorkerSimulation s) async {
    if (!await confirmDelete(context, 'la simulación',
        consequences: 'Se borran el viaje de prueba, los trabajadores simulados y todo lo que crearon. Los datos reales no se tocan.')) {
      return;
    }
    if (!mounted) return;
    await context.read<Session>().api.delete('/simulations/${s.id}');
    if (mounted) {
      setState(() => _simulation = null);
      await _load();
    }
  }

  void _openLine(WorkerSimulation s) {
    if (s.tripId != null) push(context, TripLineScreen(tripId: s.tripId!));
  }

  List<ActionItem> _actions() {
    final s = _simulation;
    if (!_loaded) return const [];
    if (s == null) return [ActionItem(Icons.science_outlined, 'Crear Simulación', _create)];
    return [
      ActionItem(Icons.science_outlined, 'Consultar Simulación', () => _load()),
      if (s.tripId != null) ActionItem(Icons.timeline, 'Ver recorrido', () => _openLine(s)),
      if (s.tripId != null) ActionItem(Icons.directions_bus_outlined, 'Consultar Viaje', () => push(context, TripFormScreen(tripId: s.tripId!))),
      ActionItem(Icons.delete_outline, 'Eliminar Simulación', () => _delete(s), destructive: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (!_loaded && _error == null) {
      body = BusyPanel(text: 'Consultando Simulación', onCancel: () => Navigator.maybePop(context));
    } else if (!_loaded) {
      body = ErrorView(message: errorText(_error), onRetry: _load);
    } else {
      body = ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 120),
        children: _simulation == null ? _form() : _status(_simulation!),
      );
    }
    return AppScaffold(title: 'Simulación', tab: MainTab.more, actions: _actions, onRefresh: _load, body: body);
  }

  Widget _number(String label, TextEditingController controller, {String? hint, IconData? icon}) => FormText(
        controller: controller,
        label: label,
        hint: hint,
        icon: icon,
        keyboard: TextInputType.number,
        formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
        onChanged: (_) => setState(_readFields),
      );

  List<Widget> _form() {
    final itinerary = _itineraries.where((i) => i.id == _input.itineraryId).firstOrNull;
    final simulated = _input.vehicleMode == SimulationInput.simulatedVehicle;
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text('Crea un viaje de prueba («Simulación») que sale ya, con trabajadores simulados que informan como teléfonos reales. '
            'Usted viaja también en él: vea «Mi estado» y sus notificaciones. Nada de esto se ve en Gestión ni lo ven los trabajadores reales.'),
      ),
      SelectorCard(
        icon: Icons.route,
        title: itinerary?.name ?? 'Elija el itinerario',
        lines: ['Itinerario', if (itinerary?.entityAbbreviation != null) itinerary!.entityAbbreviation!],
        onTap: () async {
          final i = await pickOne<Itinerary>(context, 'Itinerario', _itineraries, (i) => i.name, subtitle: (i) => i.entityAbbreviation ?? '', search: true);
          if (i != null) setState(() => _input.itineraryId = i.id);
        },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: DropdownButtonFormField<String>(
          initialValue: _input.direction,
          decoration: const InputDecoration(labelText: 'Sentido'),
          items: const [DropdownMenuItem(value: 'ida', child: Text('Ida')), DropdownMenuItem(value: 'regreso', child: Text('Regreso'))],
          onChanged: (v) => setState(() => _input.direction = v ?? 'ida'),
        ),
      ),
      _number('Trabajadores simulados', _workers, hint: 'De 1 a ${SimulationInput.maxWorkers}', icon: Icons.groups_outlined),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: DropdownButtonFormField<String>(
          initialValue: _input.vehicleMode,
          decoration: const InputDecoration(labelText: 'Vehículo'),
          items: const [
            DropdownMenuItem(value: SimulationInput.simulatedVehicle, child: Text('Simulado (lo mueve el servidor)')),
            DropdownMenuItem(value: SimulationInput.realVehicle, child: Text('Real (los teléfonos que viajan)')),
          ],
          onChanged: (v) => setState(() => _input.vehicleMode = v ?? SimulationInput.simulatedVehicle),
        ),
      ),
      if (simulated)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: DropdownButtonFormField<int>(
            initialValue: _input.speedFactor,
            decoration: const InputDecoration(labelText: 'Velocidad de la simulación'),
            items: [for (final f in SimulationInput.speedFactors) DropdownMenuItem(value: f, child: Text(f == 1 ? 'Tiempo real (×1)' : '$f veces más rápida (×$f)'))],
            onChanged: (v) => setState(() => _input.speedFactor = v ?? 1),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text('Comportamiento (suman ${_input.total} %)',
            style: TextStyle(fontWeight: FontWeight.w600, color: _input.total == 100 ? null : red)),
      ),
      _number('Viajan normal (%)', _percent['normal']!),
      _number('Llegada tarde (%)', _percent['late']!),
      _number('No recogido (%)', _percent['leftBehind']!),
      _number('No viajaré (%)', _percent['notGoing']!),
      if (_input.error != null)
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text(_input.error!, style: const TextStyle(color: red))),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: primaryButton(context, 'Crear Simulación', Icons.science_outlined,
              _input.error == null ? () => runAction(context, _create, label: 'Creando Simulación') : null),
        ),
      ),
    ];
  }

  List<Widget> _status(WorkerSimulation s) {
    return [
      InfoCard(
        images: const [CardImage(icon: Icons.science_outlined)],
        title: 'Simulación • ${s.itineraryName ?? ''} • ${s.direction == 'ida' ? 'Ida' : 'Regreso'}',
        chip: Chip2(s.running ? 'En curso' : 'Terminada', s.running ? green : grey),
        lines: [
          s.simulatedVehicle ? 'Vehículo simulado${s.speedFactor > 1 ? ' (×${s.speedFactor})' : ''}' : 'Vehículo real',
          'Empezó ${s.startedAt == null ? '' : formatDateTime(s.startedAt!)} • ${s.elapsedText}',
          'Viaje: ${s.tripStatus == null ? 'eliminado' : TripStatus.name(s.tripStatus!)}',
        ],
        onTap: () => _openLine(s),
      ),
      InfoCard(
        images: const [CardImage(icon: Icons.groups_outlined)],
        title: '${s.workers} ${s.workers == 1 ? 'trabajador simulado' : 'trabajadores simulados'}',
        lines: [
          s.countsText,
          '${s.normal} % viajan • ${s.late} % Llegada tarde • ${s.leftBehind} % No recogido • ${s.notGoing} % No viajaré',
          if (s.simulatedVehicle) '${s.sensors} ${s.sensors == 1 ? 'hace' : 'hacen'} de sensor',
        ],
      ),
      if (s.vehicleText != null)
        InfoCard(images: const [CardImage(icon: Icons.directions_bus_outlined)], title: 'Vehículo simulado', lines: [s.vehicleText!]),
      InfoCard(images: const [CardImage(icon: Icons.person_pin_circle_outlined)], title: 'Mi estado', lines: [WorkerState.name(s.myState)]),
      if (s.tripId != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: SizedBox(width: double.infinity, height: 48, child: primaryButton(context, 'Ver recorrido', Icons.timeline, () => _openLine(s))),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: dangerButton(context, 'Eliminar Simulación', Icons.delete_outline, () => runAction(context, () => _delete(s), label: 'Eliminando Simulación')),
        ),
      ),
    ];
  }
}
