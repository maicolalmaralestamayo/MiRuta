import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../profile/absence_screen.dart';
import '../widgets/busy.dart';
import '../widgets/common.dart';

/// Operaciones de Gestión que se usan desde varias pantallas (Inicio, listas
/// de Gestión y formularios): solicitudes, Entidades, itinerarios y paradas
/// de una persona, rol de Jefe, ausencias y rechazos (docs/11 §11.56 a
/// §11.60 y docs/13 §13.5). Se llaman dentro de una operación con spinner
/// (runAction o el menú Acciones) y terminan con su mensaje escueto.
class Ops {
  final BuildContext context;

  Ops(this.context);

  ApiClient get api => context.api;

  /// Mensaje escueto del resultado («Itinerario añadido»…).
  void done(String message) {
    if (context.mounted) showResult(ScaffoldMessenger.of(context), message);
  }

  Future<List<Entity>> entities() async => (await api.getAll('/entities')).map(Entity.from).toList();

  /// Itinerarios (de una Entidad, si se indica).
  Future<List<Itinerary>> itineraries({String? entityId}) async =>
      (await api.getAll('/itineraries', query: {'include': 'entity', 'filter[entity]': ?entityId})).map(Itinerary.from).toList();

  Future<List<Stop>> stopsOf(String itineraryId) async =>
      (await api.getAll('/stops', query: {'filter[itinerary]': itineraryId, 'sort': 'position'})).map(Stop.from).toList();

  /// Parada de un itinerario (null = sin parada; cancelar = [cancelled]).
  Future<({bool cancelled, Stop? stop})> pickStopOf(String itineraryId, {bool optional = true, String title = 'Elegir parada', String? current}) async {
    final stops = await stopsOf(itineraryId);
    if (!context.mounted) return (cancelled: true, stop: null);
    const none = Stop(id: '', landmark: 'Sin parada');
    final options = [if (optional) none, ...stops];
    final picked = await pickOne<Stop>(context, title, options, (s) => s.id.isEmpty ? 'Sin parada (la elegirá después)' : '${s.positionIn(itineraryId) ?? ''}. ${s.landmark}',
        subtitle: (s) => s.address, selected: options.where((s) => s.id == (current ?? '')).firstOrNull, search: stops.length > 8);
    if (picked == null) return (cancelled: true, stop: null);
    return (cancelled: false, stop: picked.id.isEmpty ? null : picked);
  }

  /// Elegir una persona (búsqueda por nombre, usuario o carné).
  Future<Person?> pickPerson(String title, {Map<String, dynamic> query = const {}, Set<String> exclude = const {}}) async {
    final people = (await api.getAll('/users', query: query)).map(Person.from).where((p) => !exclude.contains(p.id)).toList();
    if (!context.mounted) return null;
    return pickOne<Person>(context, title, people, (p) => p.fullName,
        subtitle: (p) => [p.username ?? '', if (p.identityCard != null) 'CI ${p.identityCard}'].where((s) => s.isNotEmpty).join(' • '), search: true);
  }

  // Solicitudes

  /// «Solicitar Entidad»: por su abreviatura, comprobada con GET entities/lookup.
  Future<bool> requestEntity() async {
    final abbreviation = await promptText(context, 'Solicitar Entidad', label: 'Abreviatura de la Entidad (p. ej. UMIM)', required: true, accept: 'Buscar', icon: Icons.search);
    if (abbreviation == null || !context.mounted) return false;
    final lookup = await api.get('/entities/lookup', query: {'filter[abbreviation]': abbreviation.toUpperCase()});
    final name = lookup.resource.string('name') ?? abbreviation;
    if (!context.mounted) return false;
    if (!await confirm(context, 'Solicitar Entidad', '¿Solicitar entrar en ${abbreviation.toUpperCase()} ($name)?', accept: 'Solicitar', icon: Icons.send, headerIcon: Icons.add_business_outlined)) {
      return false;
    }
    await api.post('/applications', resourceData('applications', attributes: {'type': 'entidad', 'entityAbbreviation': abbreviation.toUpperCase()}));
    done('Solicitud enviada');
    return true;
  }

  /// «Solicitar itinerario» (con parada opcional) en una de sus Entidades.
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
      final mine = me.placements.map((p) => p.itineraryId).toSet();
      final list = (await itineraries(entityId: entityId)).where((i) => i.active && !mine.contains(i.id)).toList();
      if (!context.mounted) return false;
      if (list.isEmpty) {
        showMessage(context, 'No hay otros itinerarios en esa Entidad.');
        return false;
      }
      target = await pickOne<Itinerary>(context, 'Elegir itinerario', list, (i) => i.name, subtitle: (i) => '${plural(i.stopCount, 'parada', 'paradas')} • ${plural(i.workerCount, 'trabajador', 'trabajadores')}');
      if (target == null) return false;
    }
    final stop = await pickStopOf(target.id);
    if (stop.cancelled) return false;
    await api.post('/applications', resourceData('applications', attributes: {'type': 'itinerario'}, relationships: {
      'itinerary': ResourceId('itineraries', target.id),
      if (stop.stop != null) 'stop': ResourceId('stops', stop.stop!.id),
    }));
    done('Solicitud enviada');
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
    done(applications.length == 1 ? 'Solicitud rechazada' : 'Solicitudes rechazadas');
    return true;
  }

  Future<bool> approve(List<Application> applications) async {
    for (final a in applications) {
      await api.patch('/applications/${a.id}', resourceData('applications', id: a.id, attributes: {'status': 'aprobada'}));
    }
    done(applications.length == 1 ? 'Solicitud aprobada' : 'Solicitudes aprobadas');
    return true;
  }

  /// Cancelar una solicitud propia pendiente (o eliminar una resuelta).
  Future<bool> withdraw(Application a) async {
    final ok = a.pending
        ? await confirm(context, 'Cancelar solicitud', '¿Cancelar su solicitud de entrar en ${a.isEntity ? a.entityAbbreviation ?? 'la Entidad' : a.itineraryName ?? 'el itinerario'}?',
            accept: 'Cancelar solicitud', icon: Icons.check, destructive: true, headerIcon: Icons.cancel_outlined, cancel: 'Volver', cancelIcon: Icons.arrow_back)
        : await confirm(context, 'Eliminar solicitud', '¿Quitar de la lista esta solicitud ya resuelta?',
            accept: 'Eliminar', icon: Icons.delete_outline, destructive: true, headerIcon: Icons.delete_outline, cancel: 'Volver', cancelIcon: Icons.arrow_back);
    if (!ok) return false;
    await api.delete('/applications/${a.id}');
    done(a.pending ? 'Solicitud cancelada' : 'Solicitud eliminada');
    return true;
  }

  /// Detalle de una solicitud con lo que se puede hacer con ella: resolverla
  /// ([canResolve]) o, si es suya, cancelarla o eliminarla. Devuelve true si cambió.
  Future<bool> showApplication(Application a, {required bool mine, required bool canResolve}) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(a.isEntity ? Icons.apartment : Icons.route, size: 32),
        title: Text('Solicitud de ${a.isEntity ? 'Entidad' : 'itinerario'}', textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!mine) Text('Persona: ${a.userName ?? ''}'),
          Text('Solicita: ${a.what}'),
          Text('Fecha: ${formatDateTime(a.createdAt)}'),
          Text('Estado: ${a.statusName}'),
          if (a.resolvedAt != null) Text('Resuelta: ${formatDateTime(a.resolvedAt)}${a.resolvedBy == null ? '' : ' por ${a.resolvedBy}'}'),
          if (a.denialReason != null) Text('Motivo: ${a.denialReason}'),
          if (a.resolutionNote != null && a.resolutionNote!.isNotEmpty) Text('Observación: ${a.resolutionNote}'),
        ]),
        actionsAlignment: MainAxisAlignment.end,
        actionsOverflowAlignment: OverflowBarAlignment.end,
        actions: [
          cancelButton(context, label: 'Volver', icon: Icons.arrow_back),
          if (canResolve && a.pending) ...[
            FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: red, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, 'reject'),
                icon: const Icon(Icons.block),
                label: const Text('Rechazar')),
            FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, 'approve'),
                icon: const Icon(Icons.check),
                label: const Text('Aprobar')),
          ],
          if (mine)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, 'withdraw'),
              icon: Icon(a.pending ? Icons.cancel_outlined : Icons.delete_outline),
              label: Text(a.pending ? 'Cancelar solicitud' : 'Eliminar'),
            ),
        ],
      ),
    );
    if (!context.mounted) return false;
    return switch (choice) {
      'approve' => await approve([a]),
      'reject' => await reject([a]),
      'withdraw' => await withdraw(a),
      _ => false,
    };
  }

  // Pertenencias de una persona

  /// «Asociar Entidad» (Administrador): añade las personas a una Entidad.
  Future<bool> associateEntity(List<String> userIds, {Set<String> exclude = const {}}) async {
    final list = (await entities()).where((e) => !exclude.contains(e.id)).toList();
    if (!context.mounted) return false;
    final entity = await pickOne<Entity>(context, 'Asociar Entidad', list, (e) => e.abbreviation, subtitle: (e) => e.name, search: list.length > 8);
    if (entity == null || !context.mounted) return false;
    for (final id in userIds) {
      await api.post('/workers', resourceData('workers', relationships: {'entity': ResourceId('entities', entity.id), 'user': ResourceId('users', id)}));
    }
    done('Entidad asociada');
    return true;
  }

  /// «Añadir itinerario»: a la persona, en un itinerario (de esa Entidad, si
  /// se indica), con parada opcional. El Jefe solo en el suyo.
  Future<bool> addItinerary(Me me, String userId, {String? entityId, Set<String> exclude = const {}}) async {
    var list = (await itineraries(entityId: entityId)).where((i) => i.entityId != null && !exclude.contains(i.id)).toList();
    if (!me.isAdmin) list = list.where((i) => i.id == me.chiefItineraryId).toList();
    if (!context.mounted) return false;
    if (list.isEmpty) {
      showMessage(context, 'No hay itinerarios que añadir.');
      return false;
    }
    final itinerary = await pickOne<Itinerary>(context, 'Añadir itinerario', list, (i) => i.name, subtitle: (i) => i.entityAbbreviation ?? '');
    if (itinerary == null || !context.mounted) return false;
    final stop = await pickStopOf(itinerary.id);
    if (stop.cancelled) return false;
    await api.post('/worker-itineraries', resourceData('worker-itineraries', relationships: {
      'user': ResourceId('users', userId),
      'itinerary': ResourceId('itineraries', itinerary.id),
      if (stop.stop != null) 'stop': ResourceId('stops', stop.stop!.id),
    }));
    done('Itinerario añadido');
    return true;
  }

  /// «Cambiar de parada» en uno de sus itinerarios.
  Future<bool> changeStop(Placement p) async {
    final stop = await pickStopOf(p.itineraryId, title: 'Parada en ${p.itineraryName}', current: p.stopId);
    if (stop.cancelled) return false;
    await api.patch('/worker-itineraries/${p.id}', resourceData('worker-itineraries', id: p.id, relationships: {'stop': stop.stop == null ? null : ResourceId('stops', stop.stop!.id)}));
    done('Parada cambiada');
    return true;
  }

  /// «Quitar del itinerario» (o «Salir del itinerario», la propia persona).
  Future<bool> removeFromItinerary(Placement p, {String? who}) async {
    final warning = p.isChief ? ' Perderá el rol de Jefe de itinerario.' : '';
    if (!await confirm(context, who == null ? 'Salir del itinerario' : 'Quitar del itinerario',
        '¿${who == null ? 'Salir de' : 'Quitar a $who de'} ${p.itineraryName}? Sigue en ${p.entityAbbreviation}.$warning',
        accept: who == null ? 'Salir' : 'Quitar', icon: Icons.logout, destructive: true, headerIcon: Icons.route)) {
      return false;
    }
    await api.delete('/worker-itineraries/${p.id}');
    done('Itinerario quitado');
    return true;
  }

  /// «Asignar rol de Jefe» / «Quitar rol de Jefe» (Administrador).
  Future<bool> setChief(Placement p, bool chief) async {
    await api.patch('/worker-itineraries/${p.id}', resourceData('worker-itineraries', id: p.id, attributes: {'isChief': chief}));
    done(chief ? 'Jefe asignado' : 'Rol de Jefe quitado');
    return true;
  }

  /// «Sacar de la Entidad» (Administrador) o «Salir de la Entidad» (la propia persona).
  Future<bool> leaveEntity(Membership m, {String? who}) async {
    if (!await confirm(context, who == null ? 'Salir de la Entidad' : 'Sacar de la Entidad',
        '¿${who == null ? 'Salir de' : 'Sacar a $who de'} ${m.entityAbbreviation}? Se pierden allí sus itinerarios, paradas, jefatura, ausencias y solicitudes pendientes.',
        accept: who == null ? 'Salir' : 'Sacar', icon: Icons.logout, destructive: true, headerIcon: Icons.apartment)) {
      return false;
    }
    await api.delete('/workers/${m.workerId}');
    done(who == null ? 'Salió de la Entidad' : 'Persona sacada de la Entidad');
    return true;
  }

  /// Declarar ausencia (docs/11 §11.61): de sí mismo o, para Administrador
  /// y Jefe, de otra persona, en uno o varios de sus itinerarios.
  Future<bool> declareAbsence(String userId, List<Placement> placements, {String? who, Set<String>? initial}) async {
    if (placements.isEmpty) {
      showMessage(context, 'Hace falta tener algún itinerario: la ausencia se declara por itinerario.');
      return false;
    }
    final types = (await api.getAll('/absence-types', query: {'filter[active]': 'true'})).map(NomenclatorItem.from).toList();
    if (!context.mounted) return false;
    return await Navigator.of(context).push<bool>(MaterialPageRoute(
            builder: (_) => AbsenceScreen(userId: userId, placements: placements, types: types, who: who, initial: initial))) ==
        true;
  }

  /// «Terminar ausencia» (docs/11 §11.61): termina ayer (vuelve a viajar
  /// desde hoy); si aún no había empezado, se elimina.
  Future<bool> endAbsence(List<Absence> absences) async {
    var absence = absences.first;
    if (absences.length > 1) {
      final picked = await pickOne<Absence>(context, 'Terminar ausencia', absences, (a) => a.typeName, subtitle: (a) => '${a.itineraryNames} • ${absencePeriod(a)}');
      if (picked == null) return false;
      absence = picked;
    }
    if (!context.mounted) return false;
    if (!await confirm(context, 'Terminar ausencia', '¿Terminar su ausencia (${absence.typeName}) en ${absence.itineraryNames}? Desde hoy vuelve a contar como pasajero.',
        accept: 'Terminar', icon: Icons.event_available, headerIcon: Icons.event_available)) {
      return false;
    }
    final today = DateTime.now();
    final yesterday = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 1));
    final starts = absence.startsOn;
    if (starts == null || starts.isAfter(yesterday)) {
      await api.delete('/absences/${absence.id}');
    } else {
      await api.patch('/absences/${absence.id}', resourceData('absences', id: absence.id, attributes: {'endsOn': apiDay(yesterday)}));
    }
    done('Ausencia terminada');
    return true;
  }
}

/// «desde lun. 16-11-26, indefinida» / «del lun. 16-11-26 al vie. 20-11-26».
String absencePeriod(Absence a) =>
    a.endsOn == null ? 'desde ${formatDate(a.startsOn)}, indefinida' : 'del ${formatDate(a.startsOn)} al ${formatDate(a.endsOn)}';
