import 'package:flutter/material.dart';

import '../../models/models.dart';

/// Los nombres y apellidos (cuentas e hijos). El segundo nombre es opcional
/// (docs/09, Generales).
class NamesFields extends StatelessWidget {
  final TextEditingController firstName;
  final TextEditingController middleName;
  final TextEditingController firstSurname;
  final TextEditingController secondSurname;
  final ValueChanged<String>? onChanged;

  const NamesFields({super.key, required this.firstName, required this.middleName, required this.firstSurname, required this.secondSurname, this.onChanged});

  PersonName get value => PersonName(
        firstName: firstName.text.trim(),
        middleName: middleName.text.trim(),
        firstSurname: firstSurname.text.trim(),
        secondSurname: secondSurname.text.trim(),
      );

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController controller, String label, String hint, {String? required}) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(labelText: label, hintText: hint),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: onChanged,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: required == null ? null : (v) => v == null || v.trim().isEmpty ? required : null,
          ),
        );
    return Column(children: [
      field(firstName, 'Primer nombre', 'p. ej. Ana', required: 'Escriba el primer nombre'),
      field(middleName, 'Segundo nombre', 'p. ej. María'),
      field(firstSurname, 'Primer apellido', 'p. ej. Pérez', required: 'Escriba el primer apellido'),
      field(secondSurname, 'Segundo apellido', 'p. ej. García', required: 'Escriba el segundo apellido'),
    ]);
  }
}
