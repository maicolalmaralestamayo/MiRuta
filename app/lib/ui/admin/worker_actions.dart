import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/api/memberships_api.dart';
import '../../services/api/roles_api.dart';
import '../widgets/common.dart';

/// Un trabajador de la lista de Gestión: la pertenencia (`workers`) con la
/// persona, su itinerario y su parada (include=user,entity,itinerary,stop).
class WorkerItem {
  final Worker worker;
  final Person? person;
  final String? itineraryName;
  final String? itineraryImageUrl;
  final String? stopLandmark;
  final String? stopStreet;
  final String? stopImageUrl;

  const WorkerItem(this.worker, {this.person, this.itineraryName, this.itineraryImageUrl, this.stopLandmark, this.stopStreet, this.stopImageUrl});

  factory WorkerItem.from(Resource r) {
    final user = r.related('user');
    final itinerary = r.related('itinerary');
    final stop = r.related('stop');
    return WorkerItem(
      Worker.from(r),
      person: user == null ? null : Person.from(user),
      itineraryName: itinerary?.string('name'),
      itineraryImageUrl: itinerary?.string('imageUrl'),
      stopLandmark: stop?.string('landmark'),
      stopStreet: stop?.string('street'),
      stopImageUrl: stop?.string('imageUrl'),
    );
  }

  String get id => worker.id;

  /// Abreviaturas de las Entidades de la persona (línea 2 de su tarjeta).
  List<String> get entities {
    final own = person?.entities ?? const <String>[];
    if (own.isNotEmpty) return own;
    final abbreviation = worker.entity?.abbreviation;
    return abbreviation == null ? const [] : [abbreviation];
  }

  bool get hasItinerary => worker.itineraryId != null;

  static const include = 'user,entity,itinerary,stop';
}

/// Asigna itinerario y parada (siempre juntos) a uno o varios trabajadores de
/// [entity] (members.assign). Devuelve true si se asignó.
Future<bool> assignItineraryAndStop(BuildContext context, List<Worker> workers, Entity entity) async {
  final me = context.me;
  final api = context.api;
  final memberships = MembershipsApi(api);
  List<Itinerary> itineraries;
  try {
    itineraries = (await memberships.itineraries(entity.id)).where((i) => me.can(Op.membersAssign, entityId: entity.id, itineraryId: i.id)).toList();
  } catch (error) {
    if (context.mounted) showError(context, error);
    return false;
  }
  if (!context.mounted) return false;
  if (itineraries.isEmpty) {
    showMessage(context, 'No hay itinerarios que pueda asignar en ${entity.abbreviation}.');
    return false;
  }
  final itinerary = await pickFrom<Itinerary>(context, 'Itinerario', itineraries, (i) => i.name, subtitle: (i) => plural(i.memberCount, 'trabajador', 'trabajadores'));
  if (itinerary == null || !context.mounted) return false;
  List<Stop> stops;
  try {
    stops = await memberships.stopsOf(itinerary.id);
  } catch (error) {
    if (context.mounted) showError(context, error);
    return false;
  }
  if (!context.mounted) return false;
  if (stops.isEmpty) {
    showMessage(context, 'El itinerario ${itinerary.name} no tiene paradas.');
    return false;
  }
  final stop = await pickFrom<Stop>(context, 'Parada en ${itinerary.name}', stops, (s) => s.landmark, subtitle: (s) => s.street);
  if (stop == null || !context.mounted) return false;
  return runAction(context, () async {
    for (final w in workers) {
      await api.patch('/workers/${w.id}', resourceData('workers', id: w.id, relationships: {
        'itinerary': ResourceId('itineraries', itinerary.id),
        'stop': ResourceId('stops', stop.id),
      }));
    }
  }, success: workers.length == 1 ? 'Itinerario y parada asignados.' : 'Itinerario y parada asignados a ${plural(workers.length, 'trabajador', 'trabajadores')}.');
}

/// Quita el itinerario y la parada (members.assign).
Future<bool> removeItineraryAndStop(BuildContext context, List<Worker> workers) async {
  final ok = await confirm(context, 'Quitar itinerario y parada',
      workers.length == 1 ? '¿Quitarle el itinerario y la parada a ${workers.first.fullName}?' : '¿Quitarles el itinerario y la parada a ${plural(workers.length, 'trabajador', 'trabajadores')}?',
      accept: 'Quitar', destructive: true);
  if (!ok || !context.mounted) return false;
  final api = context.api;
  return runAction(context, () async {
    for (final w in workers) {
      await api.delete('/workers/${w.id}/itinerary');
    }
  }, success: 'Itinerario y parada quitados.');
}

/// Asigna un rol directamente (roles.assign) a uno o varios trabajadores de
/// [entity]. Si el rol es de itinerario, se elige el itinerario.
Future<bool> assignRole(BuildContext context, List<Worker> workers, Entity entity) async {
  final api = context.api;
  List<Role> roles;
  try {
    roles = (await RolesApi(api).all()).where((r) => !r.isAdministrator && !r.isDefault).toList();
  } catch (error) {
    if (context.mounted) showError(context, error);
    return false;
  }
  if (!context.mounted) return false;
  final role = await pickFrom<Role>(context, 'Rol', roles, (r) => r.name, subtitle: (r) => r.itineraryScoped ? 'De un itinerario' : 'De la Entidad');
  if (role == null || !context.mounted) return false;
  String? itineraryId;
  if (role.itineraryScoped) {
    List<Itinerary> itineraries;
    try {
      itineraries = await MembershipsApi(api).itineraries(entity.id);
    } catch (error) {
      if (context.mounted) showError(context, error);
      return false;
    }
    if (!context.mounted) return false;
    final itinerary = await pickFrom<Itinerary>(context, '${role.name}: itinerario', itineraries, (i) => i.name);
    if (itinerary == null || !context.mounted) return false;
    itineraryId = itinerary.id;
  }
  return runAction(context, () async {
    for (final w in workers) {
      await RolesApi(api).assign(workerId: w.id, roleId: role.id, itineraryId: itineraryId);
    }
  }, success: 'Rol ${role.name} asignado.');
}

/// Quita roles (roles.assign).
Future<bool> removeRoles(BuildContext context, Worker worker, List<HeldRole> roles) async {
  final ok = await confirm(context, 'Quitar rol', '¿Quitarle a ${worker.fullName} ${roles.length == 1 ? 'el rol ${roles.first.name}' : 'los roles ${roles.map((r) => r.name).join(', ')}'}? Se le avisará.',
      accept: 'Quitar rol', destructive: true);
  if (!ok || !context.mounted) return false;
  final api = context.api;
  return runAction(context, () async {
    for (final r in roles) {
      await RolesApi(api).remove(r.id);
    }
  }, success: roles.length == 1 ? 'Rol quitado.' : 'Roles quitados.');
}

/// Desactiva o reactiva pertenencias (workers.deactivate): conserva su
/// itinerario y sus roles.
Future<bool> setWorkersActive(BuildContext context, List<Worker> workers, bool active) {
  final api = context.api;
  return runAction(context, () async {
    for (final w in workers) {
      await api.patch('/workers/${w.id}', resourceData('workers', id: w.id, attributes: {'active': active}));
    }
  }, success: active ? 'Reactivado.' : 'Desactivado.');
}

/// Da de baja de la Entidad (entities.assign_members): pierde allí su
/// itinerario, su parada y sus roles.
Future<bool> removeFromEntity(BuildContext context, List<Worker> workers) {
  final api = context.api;
  return runAction(context, () async {
    for (final w in workers) {
      await api.delete('/workers/${w.id}');
    }
  }, success: workers.length == 1 ? 'Dado de baja de la Entidad.' : '${plural(workers.length, 'trabajador dado', 'trabajadores dados')} de baja.');
}
