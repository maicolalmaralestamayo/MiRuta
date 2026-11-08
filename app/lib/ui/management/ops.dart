import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// Operaciones de Gestión que se usan desde varias pantallas (Inicio,
/// Gestión, formularios): solicitudes, cambios de Entidad / itinerario /
/// parada, rol de Jefe, ausencias y rechazos (docs/11 §11.26 y docs/13 §13.5).
class Ops {
  final BuildContext context;

  Ops(this.context);

  ApiClient get api => context.api;

  Future<List<Entity>> entities() async => (await api.getAll('/entities')).map(Entity.from).toList();

  Future<List<Itinerary>> itineraries({String? entityId}) async =>
      (await api.getAll('/itineraries', query: {'include': 'entity', 'filter[entity]': ?entityId})).map(Itinerary.from).toList();

  Future<List<Stop>> stopsOf(String itineraryId) async =>
      (await api.getAll('/stops', query: {'filter[itinerary]': itineraryId, 'sort': 'position'})).map(Stop.from).toList();

  /// Parada opcional de un itinerario (null = sin parada; cancelar = [cancelled]).
  Future<({bool cancelled, Stop? stop})> _pickStop(String itineraryId, {bool optional = true, String title = 'Elegir parada'}) async {
    final stops = await stopsOf(itineraryId);
    if (!context.mounted) return (cancelled: true, stop: null);
    const none = Stop(id: '', landmark: 'Sin parada');
    final options = [if (optional) none, ...stops];
    final picked = await pickOne<Stop>(context, title, options, (s) => s.id.isEmpty ? 'Sin parada (la elegirá después)' : '${s.positionIn(itineraryId) ?? ''}. ${s.landmark}',
        subtitle: (s) => s.address);
    if (picked == null) return (cancelled: true, stop: null);
    return (cancelled: false, stop: picked.id.isEmpty ? null : picked);
  }

  // Solicitudes

  /// «Solicitar Entidad»: por su abreviatura, comprobada con GET entities/lookup.
  Future<bool> requestEntity() async {
    final abbreviation = await promptText(context, 'Solicitar Entidad', label: 'Abreviatura de la Entidad (p. ej. UMIM)', required: true, accept: 'Buscar', icon: Icons.search);
    if (abbreviation == null || !context.mounted) return false;
    final lookup = await api.get('/entities/lookup', query: {'filter[abbreviation]': abbreviation.toUpperCase()});
    final name = lookup.resource.string('name') ?? abbreviation;
    if (!context.mounted) return false;
    if (!await confirm(context, 'Solicitar Entidad', '¿Solicitar entrar en ${abbreviation.toUpperCase()} ($name)?', accept: 'Solicitar', icon: Icons.send)) return false;
    await api.post('/applications', resourceData('applications', attributes: {'type': 'entidad', 'entityAbbreviation': abbreviation.toUpperCase()}));
    if (context.mounted) showMessage(context, 'Solicitud enviada. Le avisaremos cuando la resuelvan.');
    return true;
  }

  /// «Solicitar Itinerario» (con parada opcional) en una de sus Entidades.
  Future<bool> requestItinerary(Me me, {Itinerary? itinerary}) async {
    var target = itinerary;
    if (target == null) {
      if (me.memberships.isEmpty) {
        showMessage(context, 'Primero solicite entrar en una Entidad.');
        return false;
      }
      var entityId = me.memberships.first.entityId;
      if (me.memberships.length > 1) {
        final m = await pickOne<Membership>(context, 'Elegir Entidad', me.memberships, (m) => m.entityAbbreviation, subtitle: (m) => m.entityName);
        if (m == null) return false;
        entityId = m.entityId;
      }
      final list = await itineraries(entityId: entityId);
      if (!context.mounted) return false;
      target = await pickOne<Itinerary>(context, 'Elegir itinerario', list.where((i) => i.active).toList(), (i) => i.name, subtitle: (i) => '${plural(i.stopCount, 'parada', 'paradas')} • ${plural(i.workerCount, 'trabajador', 'trabajadores')}');
      if (target == null) return false;
    }
    final stop = await _pickStop(target.id);
    if (stop.cancelled) return false;
    await api.post('/applications', resourceData('applications', attributes: {'type': 'itinerario'}, relationships: {
      'itinerary': ResourceId('itineraries', target.id),
      if (stop.stop != null) 'stop': ResourceId('stops', stop.stop!.id),
    }));
    if (context.mounted) showMessage(context, 'Solicitud enviada. Le avisaremos cuando la resuelvan.');
    return true;
  }

  /// Rechazar solicitudes con el motivo del nomenclador y una observación.
  Future<bool> reject(List<Application> applications) async {
    final types = applications.map((a) => a.type).toSet();
    final reasons = (await api.getAll('/denial-reasons', query: {'filter[active]': 'true', if (types.length == 1) 'filter[applicationType]': types.first}))
        .map(NomenclatorItem.from)
        .toList();
    if (!context.mounted) return false;
    final reason = await pickOne<NomenclatorItem>(context, 'Motivo del rechazo', reasons, (r) => r.name, subtitle: (r) => r.description ?? '');
    if (reason == null || !context.mounted) return false;
    final note = await promptText(context, 'Observación (opcional)', label: 'Observación', maxLines: 3, accept: 'Rechazar', icon: Icons.block);
    if (note == null) return false;
    for (final a in applications) {
      await api.patch('/applications/${a.id}', resourceData('applications', id: a.id, attributes: {
        'status': 'rechazada',
        if (note.isNotEmpty) 'resolutionNote': note,
      }, relationships: {'denialReason': ResourceId('denial-reasons', reason.id)}));
    }
    return true;
  }

  Future<void> approve(List<Application> applications) async {
    for (final a in applications) {
      await api.patch('/applications/${a.id}', resourceData('applications', id: a.id, attributes: {'status': 'aprobada'}));
    }
  }

  // Personas

  /// «Cambiar de parada»: el itinerario se muestra (solo lectura) en el título.
  Future<bool> changeStop(Worker worker) async {
    if (worker.itineraryId == null) {
      showMessage(context, 'Esa persona no tiene itinerario: use «Cambiar de itinerario».');
      return false;
    }
    final stop = await _pickStop(worker.itineraryId!, title: 'Parada en ${worker.itineraryName ?? 'su itinerario'}');
    if (stop.cancelled) return false;
    await api.patch('/workers/${worker.id}', resourceData('workers', id: worker.id, relationships: {'stop': stop.stop == null ? null : ResourceId('stops', stop.stop!.id)}));
    return true;
  }

  /// «Cambiar de itinerario» (con parada opcional). El Jefe solo hacia el suyo.
  Future<bool> changeItinerary(Me me, List<Worker> workers) async {
    final entityIds = workers.map((w) => w.entityId).toSet();
    if (entityIds.length != 1 || entityIds.first == null) {
      showMessage(context, 'Marque personas de una misma Entidad.');
      return false;
    }
    var list = await itineraries(entityId: entityIds.first);
    if (!me.isAdmin) list = list.where((i) => i.id == me.chiefItineraryId).toList();
    if (!context.mounted) return false;
    const none = Itinerary(id: '', name: 'Sin itinerario');
    final target = await pickOne<Itinerary>(context, 'Cambiar de itinerario', [if (me.isAdmin) none, ...list], (i) => i.id.isEmpty ? 'Sin itinerario (sacar del itinerario)' : i.name);
    if (target == null || !context.mounted) return false;
    if (workers.any((w) => w.isChief && w.itineraryId != target.id)) {
      if (!await confirm(context, 'Cambiar de itinerario', 'Quien es Jefe de itinerario y cambia de itinerario pierde el rol de Jefe. ¿Seguir?', accept: 'Cambiar', icon: Icons.swap_horiz)) return false;
    }
    Stop? stop;
    if (target.id.isNotEmpty) {
      final picked = await _pickStop(target.id);
      if (picked.cancelled) return false;
      stop = picked.stop;
    }
    for (final w in workers) {
      await api.patch('/workers/${w.id}', resourceData('workers', id: w.id, relationships: {
        'itinerary': target.id.isEmpty ? null : ResourceId('itineraries', target.id),
        'stop': stop == null ? null : ResourceId('stops', stop.id),
      }));
    }
    return true;
  }

  /// «Cambiar de Entidad» (Administrador): itinerario y parada opcionales.
  /// A quien no tiene Entidad se le añade una.
  Future<bool> changeEntity(List<Worker> workers) async {
    final list = await entities();
    if (!context.mounted) return false;
    final entity = await pickOne<Entity>(context, 'Cambiar de Entidad', list, (e) => e.abbreviation, subtitle: (e) => e.name);
    if (entity == null || !context.mounted) return false;
    final itineraryList = await itineraries(entityId: entity.id);
    if (!context.mounted) return false;
    const none = Itinerary(id: '', name: 'Sin itinerario');
    final itinerary = await pickOne<Itinerary>(context, 'Itinerario (opcional)', [none, ...itineraryList], (i) => i.id.isEmpty ? 'Sin itinerario' : i.name);
    if (itinerary == null) return false;
    Stop? stop;
    if (itinerary.id.isNotEmpty) {
      final picked = await _pickStop(itinerary.id);
      if (picked.cancelled) return false;
      stop = picked.stop;
    }
    if (!context.mounted) return false;
    if (!await confirm(context, 'Cambiar de Entidad', 'Al cambiar de Entidad se pierden el itinerario, la parada y el rol de Jefe que tenía en la anterior. ¿Seguir?',
        accept: 'Cambiar', icon: Icons.swap_horiz)) {
      return false;
    }
    for (final w in workers) {
      final relationships = <String, ResourceId?>{
        'entity': ResourceId('entities', entity.id),
        if (itinerary.id.isNotEmpty) 'itinerary': ResourceId('itineraries', itinerary.id),
        if (stop != null) 'stop': ResourceId('stops', stop.id),
      };
      if (w.hasMembership) {
        await api.patch('/workers/${w.id}', resourceData('workers', id: w.id, relationships: relationships));
      } else {
        await api.post('/workers', resourceData('workers', relationships: {...relationships, 'user': ResourceId('users', w.person.id)}));
      }
    }
    return true;
  }

  /// «Asignar rol» de Jefe de itinerario (Administrador): se le pone en ese itinerario.
  Future<bool> assignChief(Worker worker) async {
    if (worker.entityId == null) return false;
    final list = await itineraries(entityId: worker.entityId);
    if (!context.mounted) return false;
    final target = await pickOne<Itinerary>(context, 'Jefe de itinerario de…', list, (i) => i.name, selected: list.where((i) => i.id == worker.itineraryId).firstOrNull);
    if (target == null || !context.mounted) return false;
    if (worker.itineraryId != null && worker.itineraryId != target.id) {
      if (!await confirm(context, 'Asignar rol', 'El Jefe viaja en su itinerario: ${worker.person.fullName} pasará de ${worker.itineraryName ?? 'su itinerario'} a ${target.name}. ¿Seguir?',
          accept: 'Asignar', icon: Icons.badge_outlined)) {
        return false;
      }
    }
    await api.patch('/workers/${worker.id}', resourceData('workers', id: worker.id, attributes: {'isChief': true}, relationships: {
      if (worker.itineraryId != target.id) 'itinerary': ResourceId('itineraries', target.id),
    }));
    return true;
  }

  /// Declarar ausencia (de sí mismo o, para Administrador y Jefe, de otra persona).
  Future<bool> declareAbsence(String workerId, {String? who}) async {
    final types = (await api.getAll('/absence-types', query: {'filter[active]': 'true'})).map(NomenclatorItem.from).toList();
    if (!context.mounted) return false;
    final result = await showDialog<bool>(context: context, builder: (_) => _AbsenceDialog(api: api, workerId: workerId, types: types, who: who));
    return result == true;
  }
}

class _AbsenceDialog extends StatefulWidget {
  final ApiClient api;
  final String workerId;
  final List<NomenclatorItem> types;
  final String? who;

  const _AbsenceDialog({required this.api, required this.workerId, required this.types, this.who});

  @override
  State<_AbsenceDialog> createState() => _AbsenceDialogState();
}

class _AbsenceDialogState extends State<_AbsenceDialog> {
  NomenclatorItem? _type;
  DateTime _from = DateTime.now();
  DateTime? _to;
  final _note = TextEditingController();
  bool _busy = false;

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(context: context, initialDate: initial, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.who == null ? 'Declarar ausencia' : 'Ausencia de ${widget.who}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<NomenclatorItem>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Tipo de ausencia'),
            items: [for (final t in widget.types) DropdownMenuItem(value: t, child: Text(t.name))],
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: const Text('Desde'),
            subtitle: Text(formatDate(_from)),
            onTap: () async {
              final d = await _pick(_from);
              if (d != null) setState(() => _from = d);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_available),
            title: const Text('Hasta'),
            subtitle: Text(_to == null ? 'Sin fecha de fin (indefinida)' : formatDate(_to)),
            trailing: _to == null ? null : IconButton(tooltip: 'Sin fecha de fin', icon: const Icon(Icons.clear), onPressed: () => setState(() => _to = null)),
            onTap: () async {
              final d = await _pick(_to ?? _from);
              if (d != null) setState(() => _to = d);
            },
          ),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Nota'), maxLines: 2),
        ]),
      ),
      actions: [
        cancelButton(context),
        FilledButton.icon(
          onPressed: _busy || _type == null
              ? null
              : () async {
                  setState(() => _busy = true);
                  final ok = await runAction(context, () => widget.api.post('/absences', resourceData('absences', attributes: {
                        'startsOn': apiDay(_from),
                        'endsOn': _to == null ? null : apiDay(_to!),
                        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
                      }, relationships: {
                        'worker': ResourceId('workers', widget.workerId),
                        'absenceType': ResourceId('absence-types', _type!.id),
                      })), success: 'Ausencia declarada.');
                  if (!context.mounted) return;
                  if (ok) {
                    Navigator.pop(context, true);
                  } else {
                    setState(() => _busy = false);
                  }
                },
          icon: const Icon(Icons.event_busy),
          label: const Text('Declarar'),
        ),
      ],
    );
  }
}
