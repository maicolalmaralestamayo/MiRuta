import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../../core/card_number.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../widgets/common.dart';

/// Formulario de una solicitud nueva. Devuelve true si se envió.
Future<bool> showApplicationForm(BuildContext context, String type) async {
  final sent = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ApplicationFormScreen(type: type)));
  if (sent == true && context.mounted) await context.session.reloadMe();
  return sent == true;
}

class ApplicationFormScreen extends StatefulWidget {
  final String type;

  const ApplicationFormScreen({super.key, required this.type});

  @override
  State<ApplicationFormScreen> createState() => _ApplicationFormScreenState();
}

class _ApplicationFormScreenState extends State<ApplicationFormScreen> {
  final _form = GlobalKey<FormState>();
  List<Itinerary> _itineraries = [];
  List<Stop> _stops = [];
  List<Rank> _ranks = [];
  List<Named> _absenceTypes = [];
  String? _itineraryId;
  String? _stopId;
  String? _rankId;
  String? _absenceTypeId;
  DateTimeRange? _range;
  final _observation = TextEditingController();
  final _childFirst = TextEditingController();
  final _childLast = TextEditingController();
  final _childCard = TextEditingController();
  int _childMaxAge = 16;
  bool _busy = false;
  ApiException? _error;

  bool get _needsItinerary => widget.type == ApplicationType.itineraryMembership || widget.type == ApplicationType.itineraryChief;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.api;
    try {
      if (_needsItinerary) {
        final resources = await api.getAll('/itineraries', query: {'sort': 'name'});
        setState(() => _itineraries = resources.map(Itinerary.from).toList());
      }
      if (widget.type == ApplicationType.rankChange) {
        final resources = await api.getAll('/ranks', query: {'sort': 'precedence'});
        setState(() => _ranks = resources.map(Rank.from).toList());
      }
      if (widget.type == ApplicationType.absence) {
        final resources = await api.getAll('/absence-types');
        setState(() => _absenceTypes = resources.map(Named.from).toList());
      }
      if (widget.type == ApplicationType.childAddition) {
        final setting = await api.get('/settings/child_max_age');
        setState(() => _childMaxAge = int.tryParse(setting.resource.string('value') ?? '') ?? 16);
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
    setState(() {
      _busy = true;
      _error = null;
    });
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    try {
      await context.api.post('/applications', resourceData('applications', attributes: {
        'type': widget.type,
        if (widget.type == ApplicationType.childAddition) ...{
          'childFirstName': _childFirst.text.trim(),
          'childLastName': _childLast.text.trim(),
          'childCardNumber': _childCard.text.trim(),
        },
        if (widget.type == ApplicationType.absence) ...{
          'startsOn': day(_range!.start),
          'endsOn': day(_range!.end),
          'observation': _observation.text.trim(),
        },
      }, relationships: {
        if (_needsItinerary) 'itinerary': ResourceId('itineraries', _itineraryId!),
        if (_needsItinerary) 'stop': ResourceId('stops', _stopId!),
        if (widget.type == ApplicationType.rankChange) 'rank': ResourceId('ranks', _rankId!),
        if (widget.type == ApplicationType.absence) 'absenceType': ResourceId('absence-types', _absenceTypeId!),
      }));
      if (mounted) {
        showMessage(context, 'Solicitud enviada');
        Navigator.pop(context, true);
      }
    } on ApiException catch (error) {
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final childCard = CardNumber.tryParse(_childCard.text);
    return Scaffold(
      appBar: AppBar(title: Text(ApplicationType.label(widget.type))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.type == ApplicationType.itineraryChief)
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
          if (widget.type == ApplicationType.rankChange)
            DropdownButtonFormField<String>(
              initialValue: _rankId,
              decoration: const InputDecoration(labelText: 'Jerarquía nueva'),
              items: [for (final r in _ranks) DropdownMenuItem(value: r.id, child: Text(r.name))],
              onChanged: (value) => setState(() => _rankId = value),
              validator: (v) => v == null ? 'Elige la jerarquía' : null,
            ),
          if (widget.type == ApplicationType.childAddition) ...[
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Si son pareja y viajan en el mismo itinerario, solo uno de los dos debe declarar a los niños.'),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _childFirst, decoration: const InputDecoration(labelText: 'Nombre del niño'), validator: (v) => v!.trim().isEmpty ? 'Obligatorio' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _childLast, decoration: const InputDecoration(labelText: 'Apellidos del niño'), validator: (v) => v!.trim().isEmpty ? 'Obligatorio' : null),
            const SizedBox(height: 12),
            TextFormField(
              controller: _childCard,
              decoration: InputDecoration(
                labelText: 'Carné del niño',
                helperText: childCard == null
                    ? 'Solo tú y el Administrador podrán verlo'
                    : (childCard.isEligible(_childMaxAge)
                        ? 'Puede viajar hasta el ${formatDate(childCard.eligibleUntil(_childMaxAge))}'
                        : 'Ya no tiene derecho a viajar (hasta el ${formatDate(childCard.eligibleUntil(_childMaxAge))})'),
                errorText: _error?.fieldError('/childCardNumber'),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
              onChanged: (_) => setState(() {}),
              validator: (value) {
                final error = validateCard(value);
                if (error != null) return error;
                return CardNumber.tryParse(value)!.isEligible(_childMaxAge) ? null : 'El niño ya no tiene derecho a viajar';
              },
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
          FilledButton(onPressed: _busy ? null : _submit, child: const Text('Enviar solicitud')),
        ]),
      ),
    );
  }
}
