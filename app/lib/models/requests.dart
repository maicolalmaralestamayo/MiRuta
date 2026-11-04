/// Solicitudes y ausencias (docs/11 §11.6, §11.12; docs/04-api.md).
library;

import '../core/json_api.dart';
import 'person.dart';

/// Tipos de solicitud de la 3.0. Los hijos, las ausencias y las bajas ya no
/// se solicitan: se hacen directamente.
abstract final class ApplicationType {
  static const entityMembership = 'entity_membership';
  static const itineraryMembership = 'itinerary_membership';
  static const role = 'role';

  static String label(String type) => const {
        entityMembership: 'Entrar en una Entidad',
        itineraryMembership: 'Itinerario y parada',
        role: 'Rol',
      }[type] ?? type;
}

abstract final class ApplicationStatus {
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const cancelled = 'cancelled';

  static String label(String status) => const {
        pending: 'Pendiente',
        approved: 'Aprobada',
        rejected: 'Rechazada',
        cancelled: 'Cancelada',
      }[status] ?? status;
}

/// Solicitud (recurso `applications`): entrar en una Entidad, itinerario y
/// parada, o un rol.
class Application {
  final String id;
  final String type;
  final String status;
  final String? resolutionNote;
  final DateTime? resolvedAt;
  final DateTime? createdAt;
  final String? userId;
  final String? applicantName;
  final String? entityId;
  final String? entityAbbreviation;
  final String? itineraryId;
  final String? itineraryName;
  final String? stopId;
  final String? stopLandmark;
  final String? roleId;
  final String? roleName;

  /// Quien la consulta puede aprobarla o rechazarla.
  final bool canResolve;

  /// La persona que la pide, si vino incluida (include=user).
  final Person? applicant;

  const Application({
    required this.id,
    required this.type,
    required this.status,
    this.resolutionNote,
    this.resolvedAt,
    this.createdAt,
    this.userId,
    this.applicantName,
    this.entityId,
    this.entityAbbreviation,
    this.itineraryId,
    this.itineraryName,
    this.stopId,
    this.stopLandmark,
    this.roleId,
    this.roleName,
    this.canResolve = false,
    this.applicant,
  });

  factory Application.from(Resource r) {
    final user = r.related('user');
    return Application(
      id: r.id,
      type: r.string('type') ?? '',
      status: r.string('status') ?? ApplicationStatus.pending,
      resolutionNote: r.string('resolutionNote'),
      resolvedAt: r.date('resolvedAt'),
      createdAt: r.date('createdAt'),
      userId: r.relId('user')?.id,
      applicantName: r.string('applicantName'),
      entityId: r.relId('entity')?.id,
      entityAbbreviation: r.string('entityAbbreviation'),
      itineraryId: r.relId('itinerary')?.id,
      itineraryName: r.string('itineraryName'),
      stopId: r.relId('stop')?.id,
      stopLandmark: r.string('stopLandmark'),
      roleId: r.relId('role')?.id,
      roleName: r.string('roleName'),
      canResolve: r.boolean('canResolve'),
      applicant: user == null ? null : Person.from(user),
    );
  }

  bool get isPending => status == ApplicationStatus.pending;

  /// Qué se pide, en una línea: «UMIM», «Ruta Playa • Coppelia», «Chofer».
  String get subject => switch (type) {
        ApplicationType.entityMembership => entityAbbreviation ?? '',
        ApplicationType.itineraryMembership => [itineraryName, stopLandmark].whereType<String>().join(' • '),
        _ => roleName ?? '',
      };
}

/// Ausencia declarada por la persona, sin aprobación (recurso `absences`).
class Absence {
  final String id;
  final String? workerId;
  final String? absenceTypeId;
  final String? absenceTypeName;
  final String startsOn;
  final String? endsOn;
  final bool indefinite;
  final String? note;

  const Absence({required this.id, this.workerId, this.absenceTypeId, this.absenceTypeName, required this.startsOn, this.endsOn, this.indefinite = false, this.note});

  factory Absence.from(Resource r) => Absence(
        id: r.id,
        workerId: r.relId('worker')?.id,
        absenceTypeId: r.relId('absenceType')?.id,
        absenceTypeName: r.related('absenceType')?.string('name'),
        startsOn: r.string('startsOn') ?? '',
        endsOn: r.string('endsOn'),
        indefinite: r.boolean('indefinite') || r.string('endsOn') == null,
        note: r.string('note'),
      );

  DateTime get start => DateTime.parse(startsOn);

  DateTime? get end => endsOn == null ? null : DateTime.parse(endsOn!);

  /// Cubre ese día.
  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(start) && (end == null || !d.isAfter(end!));
  }
}
