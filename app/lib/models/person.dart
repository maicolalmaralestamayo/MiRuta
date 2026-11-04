/// La persona (recurso `users`), su carné y sus hijos (docs/11 §11.2, §11.11).
library;

import '../core/json_api.dart';

/// Los cuatro nombres de una persona (cuentas e hijos).
class PersonName {
  final String firstName;
  final String middleName;
  final String firstSurname;
  final String secondSurname;

  const PersonName({this.firstName = '', this.middleName = '', this.firstSurname = '', this.secondSurname = ''});

  factory PersonName.from(Resource? r) => PersonName(
        firstName: r?.string('firstName') ?? '',
        middleName: r?.string('middleName') ?? '',
        firstSurname: r?.string('firstSurname') ?? '',
        secondSurname: r?.string('secondSurname') ?? '',
      );

  String get full => [firstName, middleName, firstSurname, secondSurname].where((part) => part.isNotEmpty).join(' ');

  /// Primer nombre y primer apellido, para listas y chats.
  String get short => [firstName, firstSurname].where((part) => part.isNotEmpty).join(' ');

  String get initials => '${firstName.isEmpty ? '' : firstName[0]}${firstSurname.isEmpty ? '' : firstSurname[0]}'.toUpperCase();

  /// Atributos JSON:API (el segundo nombre vacío se envía como null).
  Map<String, dynamic> toAttributes() => {
        'firstName': firstName.trim(),
        'middleName': middleName.trim().isEmpty ? null : middleName.trim(),
        'firstSurname': firstSurname.trim(),
        'secondSurname': secondSurname.trim(),
      };
}

/// Carné de identidad cubano (docs/11 §11.2; misma regla que api/app/Support/IdentityCard.php):
/// 11 dígitos; `AAMMDD` = nacimiento; 7.º dígito = siglo (9 → 1800, 0–5 → 1900,
/// 6–8 → 2000); penúltimo dígito par = masculino, impar = femenino.
class IdentityCard {
  static const length = 11;

  /// Fecha de nacimiento, o null si el carné no es válido.
  static DateTime? birthDate(String? card, {DateTime? today}) {
    final text = (card ?? '').trim();
    if (!RegExp(r'^\d{11}$').hasMatch(text)) return null;
    final yy = int.parse(text.substring(0, 2));
    final mm = int.parse(text.substring(2, 4));
    final dd = int.parse(text.substring(4, 6));
    final century = int.parse(text[6]);
    final base = century == 9 ? 1800 : (century <= 5 ? 1900 : 2000);
    final year = base + yy;
    final date = DateTime(year, mm, dd);
    if (date.year != year || date.month != mm || date.day != dd) return null;
    final now = today ?? DateTime.now();
    if (date.isAfter(DateTime(now.year, now.month, now.day))) return null;
    return date;
  }

  /// 'M' o 'F', o null si el carné no es válido.
  static String? sex(String? card) {
    if (birthDate(card) == null) return null;
    return int.parse(card!.trim()[9]).isEven ? 'M' : 'F';
  }

  static bool isValid(String? card) => birthDate(card) != null;

  /// Mensaje del campo (null si es válido).
  static String? validate(String? card) {
    final text = (card ?? '').trim();
    if (text.isEmpty) return 'Escriba el carné de identidad';
    if (!RegExp(r'^\d{11}$').hasMatch(text)) return 'El carné de identidad debe tener 11 dígitos';
    if (!isValid(text)) return 'Los 6 primeros dígitos del carné no son una fecha de nacimiento válida';
    return null;
  }
}

String sexLabel(String? sex) => const {'M': 'Masculino', 'F': 'Femenino'}[sex] ?? '';

/// Una persona (recurso `users`). El usuario, el carné y los datos de la
/// contraseña solo llegan para ella misma, el Administrador y quien pueda verlos.
class Person {
  final String id;
  final String? username;
  final PersonName name;
  final String? sex;
  final String? birthDate;
  final String? identityCard;
  final String? photoUrl;
  final bool isAdmin;
  final bool hasPhone;
  final bool active;
  final bool mustChangePassword;
  final bool currentPasswordRequired;
  final DateTime? passwordExpiresAt;
  final int? printedQrVersion;

  /// Abreviaturas de sus Entidades (línea 2 de su tarjeta, docs/11 §11.3).
  final List<String> entities;

  const Person({
    required this.id,
    this.username,
    this.name = const PersonName(),
    this.sex,
    this.birthDate,
    this.identityCard,
    this.photoUrl,
    this.isAdmin = false,
    this.hasPhone = true,
    this.active = true,
    this.mustChangePassword = false,
    this.currentPasswordRequired = true,
    this.passwordExpiresAt,
    this.printedQrVersion,
    this.entities = const [],
  });

  factory Person.from(Resource r) => Person(
        id: r.id,
        username: r.string('username'),
        name: PersonName.from(r),
        sex: r.string('sex'),
        birthDate: r.string('birthDate'),
        identityCard: r.string('identityCard'),
        photoUrl: r.string('photoUrl'),
        isAdmin: r.boolean('isAdmin'),
        hasPhone: r.attributes['hasPhone'] != false,
        active: r.attributes['active'] != false,
        mustChangePassword: r.boolean('mustChangePassword'),
        currentPasswordRequired: r.attributes['currentPasswordRequired'] != false,
        passwordExpiresAt: r.date('passwordExpiresAt'),
        printedQrVersion: r.integer('printedQrVersion'),
        entities: ((r.attributes['entities'] as List?) ?? const []).map((e) => '$e').toList(),
      );

  String get fullName => name.full;

  /// "UMIM • DPTRANS" o «Sin Entidad».
  String get entitiesLine => entities.isEmpty ? 'Sin Entidad' : entities.join(' • ');
}

/// Hijo (recurso `children`, docs/11 §11.11). Es de la persona, no de una Entidad.
class Child {
  final String id;
  final PersonName name;
  final String? sex;
  final String? birthDate;
  final String? eligibleUntil;
  final bool eligible;
  final bool active;
  final String? photoUrl;

  /// Solo para sus padres (y children.manage all).
  final String? identityCard;

  /// Quién lo tiene declarado: [(id, nombre)]. Solo para sus padres.
  final List<({String id, String fullName})> parents;

  const Child({
    required this.id,
    this.name = const PersonName(),
    this.sex,
    this.birthDate,
    this.eligibleUntil,
    this.eligible = true,
    this.active = true,
    this.photoUrl,
    this.identityCard,
    this.parents = const [],
  });

  factory Child.from(Resource r) => Child(
        id: r.id,
        name: PersonName.from(r),
        sex: r.string('sex'),
        birthDate: r.string('birthDate'),
        eligibleUntil: r.string('eligibleUntil'),
        eligible: r.attributes['eligible'] != false,
        active: r.attributes['active'] != false,
        photoUrl: r.string('photoUrl'),
        identityCard: r.string('identityCard'),
        parents: [
          for (final p in (r.meta['parents'] as List? ?? const []))
            (id: '${(p as Map)['id']}', fullName: '${p['fullName'] ?? ''}'),
        ],
      );

  String get fullName => name.full;

  /// Se muestra en Inicio: activo y con derecho a viajar.
  bool get travels => active && eligible;
}
