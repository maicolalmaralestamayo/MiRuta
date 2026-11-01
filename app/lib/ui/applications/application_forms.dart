import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../../services/templates.dart';
import '../theme.dart';
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

/// Un hijo del formulario "Declarar hijos" (docs/09 §11 y §38).
class _ChildBlock {
  final firstName = TextEditingController();
  final middleName = TextEditingController();
  final firstSurname = TextEditingController();
  final secondSurname = TextEditingController();
  DateTime? birthDate;

  bool get isEmpty =>
      birthDate == null && [firstName, middleName, firstSurname, secondSurname].every((c) => c.text.trim().isEmpty);

  Map<String, dynamic> toJson() => {
        'firstName': firstName.text.trim(),
        if (middleName.text.trim().isNotEmpty) 'middleName': middleName.text.trim(),
        'firstSurname': firstSurname.text.trim(),
        'secondSurname': secondSurname.text.trim(),
        'birthDate': birthDate!.toIso8601String().substring(0, 10),
      };

  void dispose() {
    for (final c in [firstName, middleName, firstSurname, secondSurname]) {
      c.dispose();
    }
  }
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
  bool _indefinite = false;
  DateTimeRange? _range;
  final _observation = TextEditingController();
  final List<_ChildBlock> _children = [_ChildBlock()];
  int _childMaxAge = 16;
  bool _submitted = false;
  ApiException? _error;

  bool get _assigning => widget.worker != null;

  bool get _needsItinerary => widget.type == ApplicationType.itineraryMembership || widget.type == ApplicationType.itineraryChief;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _observation.dispose();
    for (final child in _children) {
      child.dispose();
    }
    super.dispose();
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
    setState(() => _submitted = true);
    final valid = _form.currentState!.validate();
    if (!valid) return;
    if (widget.type == ApplicationType.absence && !_indefinite && _range == null) return;
    if (widget.type == ApplicationType.childAddition && _children.any((c) => c.birthDate == null || !_isEligible(c.birthDate!))) return;
    setState(() => _error = null);
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    try {
      await context.api.post('/applications', resourceData('applications', attributes: {
        'type': widget.type,
        if (widget.type == ApplicationType.childAddition) 'children': [for (final child in _children) child.toJson()],
        if (widget.type == ApplicationType.absence) ...{
          if (_indefinite) 'indefinite': true,
          if (!_indefinite) 'startsOn': day(_range!.start),
          if (!_indefinite) 'endsOn': day(_range!.end),
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

  bool _isEligible(DateTime birth) {
    final today = DateTime.now();
    return !DateTime(today.year, today.month, today.day).isAfter(_eligibleUntil(birth));
  }

  Future<void> _removeChild(_ChildBlock child) async {
    if (!child.isEmpty && !await confirmDelete(context, 'los datos de este hijo')) return;
    setState(() => _children.remove(child));
    child.dispose();
  }

  Widget _nameField(TextEditingController controller, String label, String hint, {bool required = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: label, hintText: hint),
          textCapitalization: TextCapitalization.words,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: required ? (v) => v == null || v.trim().isEmpty ? 'Escriba el ${label.toLowerCase()}' : null : null,
        ),
      );

  Widget _childBlock(int index, _ChildBlock child) {
    final today = DateTime.now();
    final birth = child.birthDate;
    String? birthError;
    if (birth == null && _submitted) birthError = 'Elija la fecha de nacimiento';
    if (birth != null && !_isEligible(birth)) birthError = 'Ya no tiene derecho a viajar (lo tuvo hasta el ${formatDate(_eligibleUntil(birth))})';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Hijo ${index + 1}', style: Theme.of(context).textTheme.titleSmall)),
            if (_children.length > 1)
              IconButton(
                tooltip: 'Quitar este hijo',
                icon: const Icon(Icons.delete, color: overloadColor),
                onPressed: () => _removeChild(child),
              )
            else
              const SizedBox(height: 48),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _nameField(child.firstName, 'Primer nombre', 'Pedro'),
              _nameField(child.middleName, 'Segundo nombre (opcional)', 'Luis', required: false),
              _nameField(child.firstSurname, 'Primer apellido', 'Pérez'),
              _nameField(child.secondSurname, 'Segundo apellido', 'García'),
              DateField(
                label: 'Fecha de nacimiento',
                value: birth,
                firstDate: DateTime(today.year - 30),
                lastDate: today,
                errorText: birthError,
                onChanged: (date) => setState(() => child.birthDate = date),
              ),
              if (birth != null && birthError == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 12),
                  child: Text('Derecho a viajar hasta el ${formatDate(_eligibleUntil(birth))}', style: Theme.of(context).textTheme.bodySmall),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  String get _title {
    final label = ApplicationType.label(widget.type);
    return _assigning ? '$label · ${widget.worker!.name.short}' : label;
  }

  String get _submitLabel {
    if (!_assigning) return 'Enviar solicitud';
    final label = ApplicationType.label(widget.type);
    return 'Asignar ${label[0].toLowerCase()}${label.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_needsItinerary) ...[
            DropdownButtonFormField<String>(
              initialValue: _itineraryId,
              decoration: const InputDecoration(labelText: 'Itinerario'),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              items: [for (final i in _itineraries) DropdownMenuItem(value: i.id, child: Text(i.name))],
              onChanged: (value) => value == null ? null : _loadStops(value),
              validator: (v) => v == null ? 'Elija el itinerario' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('stops-$_itineraryId'),
              initialValue: _stopId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Parada'),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              items: [for (final s in _stops) DropdownMenuItem(value: s.id, child: Text('${s.landmark} · ${s.street}', overflow: TextOverflow.ellipsis))],
              onChanged: (value) => setState(() => _stopId = value),
              validator: (v) => v == null ? 'Elija la parada' : null,
            ),
          ],
          if (widget.type == ApplicationType.childAddition) ...[
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Si son pareja y viajan en el mismo itinerario, solo uno de los dos debe declarar a los niños.'),
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _children.length; i++) _childBlock(i, _children[i]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Añadir otro hijo'),
              onPressed: _children.length >= 10 ? null : () => setState(() => _children.add(_ChildBlock())),
            ),
          ],
          if (widget.type == ApplicationType.absence) ...[
            DropdownButtonFormField<String>(
              initialValue: _absenceTypeId,
              decoration: const InputDecoration(labelText: 'Tipo de ausencia'),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              items: [for (final t in _absenceTypes) DropdownMenuItem(value: t.id, child: Text(t.name))],
              onChanged: (value) => setState(() => _absenceTypeId = value),
              validator: (v) => v == null ? 'Elija el tipo de ausencia' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<bool>(
              initialValue: _indefinite,
              decoration: const InputDecoration(labelText: 'Duración'),
              items: const [
                DropdownMenuItem(value: false, child: Text('Con fechas de inicio y fin')),
                DropdownMenuItem(value: true, child: Text('Ausencia indefinida')),
              ],
              onChanged: (value) => setState(() => _indefinite = value ?? false),
            ),
            if (!_indefinite) ...[
              const SizedBox(height: 12),
              DateRangeField(
                label: 'Fechas de la ausencia',
                value: _range,
                firstDate: now.subtract(const Duration(days: 30)),
                lastDate: now.add(const Duration(days: 365)),
                errorText: _submitted && _range == null ? 'Elija las fechas de inicio y fin' : null,
                onChanged: (range) => setState(() => _range = range),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _observation,
              decoration: const InputDecoration(labelText: 'Observación (opcional)', hintText: 'Licencia por enfermedad'),
              maxLines: 2,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(
            onPressed: _submit,
            icon: Icon(_assigning ? Icons.how_to_reg : Icons.send),
            child: Text(_submitLabel),
          ),
        ]),
      ),
    );
  }
}
