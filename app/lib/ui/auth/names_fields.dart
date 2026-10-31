import 'package:flutter/material.dart';

import '../../models/models.dart';

/// Los cuatro nombres, todos obligatorios (cuentas e hijos).
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
    Widget field(TextEditingController controller, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(labelText: label),
            textCapitalization: TextCapitalization.words,
            onChanged: onChanged,
            validator: (v) => v == null || v.trim().isEmpty ? 'Escribe el $label'.replaceFirst('el Primer', 'el primer').replaceFirst('el Segundo', 'el segundo') : null,
          ),
        );
    return Column(children: [
      field(firstName, 'Primer nombre'),
      field(middleName, 'Segundo nombre'),
      field(firstSurname, 'Primer apellido'),
      field(secondSurname, 'Segundo apellido'),
    ]);
  }
}
