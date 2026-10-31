import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../../services/templates.dart';
import '../auth/names_fields.dart';
import '../widgets/common.dart';

/// Formulario de una solicitud nueva. Devuelve true si se envió.
///
/// Con [worker] es una asignación directa de un superior a otro trabajador
/// (docs/08-version-2.md §8.5): queda aprobada al instante.
Future<bool> showApplicationForm(BuildContext context, String type, {Worker? worker}) async {
  final sent = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ApplicationFormScreen(type: type, worker: worker)));
  if (sent == true && context.mounted) await context.session.reloadMe();
  return sent == true;
}

class ApplicationFormScreen extends StatefulWidget {
  final String type;
  final Worker? worker;

  const ApplicationFormScreen({super.key, required this.type, this.worker});

  @override
  State<ApplicationFormScreen> createState() => _ApplicationFormScreenState();
}

class _ApplicationFormScreenState extends State<ApplicationFormScreen> {
  final _form = GlobalKey<FormState>();
  List<Itinerary> _itineraries = [];
  List<Stop> _stops = [];
  List<Named> _absenceTypes = [];
  String? _itineraryId;
  String? _stopId;
  String? _absenceTypeId;
  DateTimeRange? _range;
  final _observation = TextEditingController();
  final _childFirst = TextEditingController();
  final _childMiddle = TextEditingController();
  final _childFirstSurname = TextEditingController();
  final _childSecondSurname = TextEditingController();
  late final _childNames = NamesFields(firstName: _childFirst, middleName: _childMiddle, firstSurname: _childFirstSurname, secondSurname: _childSecondSurname);
  DateTime? _childBirthDate;
  int _childMaxAge = 16;
  ApiException? _error;

  bool get _assigning => widget.worker != null;

  bool get _needsItinerary => widget.type == ApplicationType.itineraryMembership || widget.type == ApplicationType.itineraryChief;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.api;
    final me = context.me;
    try {
      if (_needsItinerary) {
        final resources = await api.getAll('/itineraries', query: {'sort': 'name', 'filter[entity]': ?widget.worker?.entityId});
        // Un Jefe de itinerario solo asigna en el suyo.
        final itineraries = resources.map(Itinerary.from).where((i) => !_assigning || me.isChiefOf(i.id)).toList();
        setState(() {
          _itineraries = itineraries;
          if (itineraries.length == 1) _itineraryId = itineraries.first.id;
        });
        if (_itineraryId != null) await _loadStops(_itineraryId!);
      }
      if (widget.type == ApplicationType.absence) {
        final resources = await api.getAll('/absence-types');
        setState(() => _absenceTypes = resources.map(Named.from).toList());
      }
      if (widget.type == ApplicationType.childAddition) {
        // La edad máxima es un ajuste de cada Entidad.
        final settings = await api.getAll('/entity-settings');
        final setting = settings.where((s) => s.id == 'child_max_age').firstOrNull;
        setState(() => _childMaxAge = int.tryParse(setting?.string('value') ?? '') ?? 16);
      }
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _loadStops(String itineraryId) async {
    setState(() {
      _itineraryId = itineraryId;
      _stopId = null;
      _stops = [];
    });
    final links = await context.api.getAll('/itinerary-stops', query: {'filter[itinerary]': itineraryId, 'include': 'stop', 'sort': 'position'});
    setState(() => _stops = links.map((l) => ItineraryStop.from(l).stop!).toList());
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (widget.type == ApplicationType.absence && _range == null) {
      showMessage(context, 'Elige las fechas de la ausencia.');
      return;
    }
    if (widget.type == ApplicationType.childAddition && _childBirthDate == null) {
      showMessage(context, 'Elige la fecha de nacimiento del niño.');
      return;
    }
    setState(() => _error = null);
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    try {
      await context.api.post('/applications', resourceData('applications', attributes: {
        'type': widget.type,
        if (widget.type == ApplicationType.childAddition) ...{
          ...Session.nameAttributes(_childNames.value, prefix: 'child'),
          'childBirthDate': day(_childBirthDate!),
        },
        if (widget.type == ApplicationType.absence) ...{
          'startsOn': day(_range!.start),
          'endsOn': day(_range!.end),
          'observation': _observation.text.trim(),
        },
      }, relationships: {
        if (_needsItinerary) 'itinerary': ResourceId('itineraries', _itineraryId!),
        if (_needsItinerary) 'stop': ResourceId('stops', _stopId!),
        if (widget.type == ApplicationType.absence) 'absenceType': ResourceId('absence-types', _absenceTypeId!),
        if (_assigning) 'worker': ResourceId('workers', widget.worker!.id),
      }));
      if (mounted) {
        showMessage(context, _assigning ? 'Asignado' : 'Solicitud enviada');
        Navigator.pop(context, true);
      }
    } on ApiException catch (error) {
      setState(() => _error = error);
    }
  }

  /// Último día con derecho a viajar: el 31 de agosto siguiente a cumplir la edad máxima.
  DateTime _eligibleUntil(DateTime birth) {
    final limit = DateTime(birth.year + _childMaxAge, birth.month, birth.day);
    final endOfCourse = DateTime(limit.year, 8, 31);
    return limit.isAfter(endOfCourse) ? DateTime(limit.year + 1, 8, 31) : endOfCourse;
  }

  @override
  Widget build(BuildContext context) {
    final birth = _childBirthDate;
    final today = DateTime.now();
    final eligible = birth == null || !DateTime(today.year, today.month, today.day).isAfter(_eligibleUntil(birth));
    return Scaffold(
      appBar: AppBar(title: Text(_assigning ? '${ApplicationType.label(widget.type)} · ${widget.worker!.name.short}' : ApplicationType.label(widget.type))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_assigning)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Se asigna al momento, sin solicitud. El trabajador recibirá un aviso.'),
            )
          else if (widget.type == ApplicationType.itineraryChief)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Si la aprueba un Jefe de Transporte, pasarás a viajar en ese itinerario y en esa parada.'),
            ),
          if (_needsItinerary) ...[
            DropdownButtonFormField<String>(
              initialValue: _itineraryId,
              decoration: const InputDecoration(labelText: 'Itinerario'),
              items: [for (final i in _itineraries) DropdownMenuItem(value: i.id, child: Text(i.name))],
              onChanged: (value) => value == null ? null : _loadStops(value),
              validator: (v) => v == null ? 'Elige el itinerario' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _stopId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Parada'),
              items: [for (final s in _stops) DropdownMenuItem(value: s.id, child: Text('${s.landmark} · ${s.street}', overflow: TextOverflow.ellipsis))],
              onChanged: (value) => setState(() => _stopId = value),
              validator: (v) => v == null ? 'Elige la parada' : null,
            ),
          ],
          if (widget.type == ApplicationType.childAddition) ...[
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Si son pareja y viajan en el mismo itinerario, solo uno de los dos debe declarar a los niños.'),
              ),
            ),
            const SizedBox(height: 12),
            _childNames,
            OutlinedButton.icon(
              icon: const Icon(Icons.cake_outlined),
              label: Text(birth == null ? 'Fecha de nacimiento' : 'Nació el ${formatDate(birth)}'),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: birth ?? DateTime(today.year - 5),
                  firstDate: DateTime(today.year - 30),
                  lastDate: today,
                  helpText: 'Fecha de nacimiento del niño',
                );
                if (picked != null) setState(() => _childBirthDate = picked);
              },
            ),
            if (birth != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  eligible
                      ? 'Puede viajar hasta el ${formatDate(_eligibleUntil(birth))}. Solo tú, tus jefes y el Administrador verán la fecha.'
                      : 'Ya no tiene derecho a viajar (lo tuvo hasta el ${formatDate(_eligibleUntil(birth))}).',
                  style: TextStyle(color: eligible ? null : Theme.of(context).colorScheme.error),
                ),
              ),
          ],
          if (widget.type == ApplicationType.absence) ...[
            DropdownButtonFormField<String>(
              initialValue: _absenceTypeId,
              decoration: const InputDecoration(labelText: 'Tipo de ausencia'),
              items: [for (final t in _absenceTypes) DropdownMenuItem(value: t.id, child: Text(t.name))],
              onChanged: (value) => setState(() => _absenceTypeId = value),
              validator: (v) => v == null ? 'Elige el tipo' : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(_range == null ? 'Elegir fechas' : '${formatDate(_range!.start)} → ${formatDate(_range!.end)}'),
              onPressed: () async {
                final now = DateTime.now();
                final range = await showDateRangePicker(context: context, firstDate: now.subtract(const Duration(days: 30)), lastDate: now.add(const Duration(days: 365)));
                if (range != null) setState(() => _range = range);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _observation, decoration: const InputDecoration(labelText: 'Observación (opcional)'), maxLines: 2),
          ],
          if (widget.type == ApplicationType.driver || widget.type == ApplicationType.transportChief)
            Text(widget.type == ApplicationType.driver
                ? 'La aprueba un Jefe de Transporte, que después te asignará un vehículo.'
                : 'La aprueba el Administrador.'),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(onPressed: (widget.type == ApplicationType.childAddition && !eligible) ? null : _submit, child: Text(_assigning ? 'Asignar' : 'Enviar solicitud')),
        ]),
      ),
    );
  }
}
