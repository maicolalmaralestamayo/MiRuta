import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formats.dart';
import '../../models/models.dart';

/// Correo electrónico de la persona (docs/11 §11.67): sustituye al carné de
/// identidad; único en toda la base de datos (lo comprueba el servidor).
class EmailField extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  final bool readOnly;
  final bool last;
  final ValueChanged<String>? onChanged;

  const EmailField({super.key, required this.controller, this.errorText, this.readOnly = false, this.last = false, this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: TextFormField(
          controller: controller,
          readOnly: readOnly,
          decoration: InputDecoration(
            labelText: 'Correo electrónico',
            hintText: 'p. ej. nombre@correo.cu',
            prefixIcon: const Icon(Icons.mail_outline),
            errorText: errorText,
            errorMaxLines: 4,
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: last ? TextInputAction.done : TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [LengthLimitingTextInputFormatter(EmailAddress.maxLength)],
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onChanged: onChanged,
          validator: readOnly ? null : EmailAddress.validate,
        ),
      );
}

/// Sexo, escrito a mano (por omisión Masculino; docs/11 §11.67).
class SexField extends StatelessWidget {
  final String value;
  final ValueChanged<String>? onChanged;

  const SexField({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Sexo', border: InputBorder.none, contentPadding: EdgeInsets.zero),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'M', label: Text('Masculino')),
              ButtonSegment(value: 'F', label: Text('Femenino')),
            ],
            selected: {value == 'F' ? 'F' : 'M'},
            showSelectedIcon: false,
            onSelectionChanged: onChanged == null ? null : (s) => onChanged!(s.first),
          ),
        ),
      );
}

/// Fecha de nacimiento (opcional para las personas, obligatoria para los hijos).
class BirthDateField extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?>? onChanged;
  final bool required;

  const BirthDateField({super.key, required this.value, this.onChanged, this.required = false});

  Future<void> _pick(BuildContext context) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime(today.year - (required ? 6 : 30), today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: 'Fecha de nacimiento',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null) onChanged?.call(DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: FormField<DateTime>(
          initialValue: value,
          validator: (_) => required && value == null ? 'Elija la fecha de nacimiento' : null,
          builder: (state) => InkWell(
            onTap: onChanged == null ? null : () => _pick(context),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: required ? 'Fecha de nacimiento' : 'Fecha de nacimiento (opcional)',
                prefixIcon: const Icon(Icons.cake_outlined),
                errorText: state.errorText,
                suffixIcon: value != null && !required && onChanged != null
                    ? IconButton(tooltip: 'Quitar', icon: const Icon(Icons.close), onPressed: () => onChanged!(null))
                    : null,
              ),
              child: Text(value == null ? '' : formatDate(value)),
            ),
          ),
        ),
      );
}
