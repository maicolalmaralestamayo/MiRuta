import 'package:flutter/material.dart';

import '../../models/models.dart';

/// Pide un valor nuevo para un ajuste según su tipo. Devuelve null si se cancela.
Future<Object?> editSettingValue(BuildContext context, SettingDefinition definition, String current) async {
  switch (definition.valueType) {
    case 'boolean':
      return current == '1' ? false : true;

    case 'option':
      return showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(definition.name),
          children: [
            RadioGroup<String>(
              groupValue: current,
              onChanged: (value) => Navigator.pop(context, value),
              child: Column(children: [
                for (final option in definition.options.entries) RadioListTile<String>(value: option.key, title: Text(option.value)),
              ]),
            ),
          ],
        ),
      );

    case 'time':
      final parts = current.split(':');
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 0, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0),
      );
      return time == null ? null : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    case 'integer':
      final controller = TextEditingController(text: current);
      final form = GlobalKey<FormState>();
      final min = definition.minValue;
      final max = definition.maxValue;
      String? validate(String? text) {
        final n = int.tryParse((text ?? '').trim());
        if (n == null) return 'Escriba un número entero.';
        if (min != null && n < min) return 'El valor mínimo es $min.';
        if (max != null && n > max) return 'El valor máximo es $max.';
        return null;
      }

      return showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(definition.name),
          content: Form(
            key: form,
            child: TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(labelText: 'Valor', hintText: 'p. ej. ${definition.defaultValue}'),
              validator: validate,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton.icon(
              icon: const Icon(Icons.save),
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(context, int.parse(controller.text.trim()));
              },
              label: const Text('Guardar ajuste'),
            ),
          ],
        ),
      );

    default:
      final controller = TextEditingController(text: current);
      return showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(definition.name),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: controller, maxLines: 5, autofocus: true),
              if (definition.key.endsWith('_template')) ...[
                const SizedBox(height: 8),
                // {fecha_salida}, {hora_salida}… son los datos del viaje de ida;
                // {fecha_regreso}, {hora_regreso}… los del viaje de regreso.
                Text(
                  'Variables: {itinerario} {tipo} {matricula} {chofer} {capacidad} {fecha_salida} {hora_salida} {punto_salida} '
                  '{fecha_regreso} {hora_regreso} {punto_regreso} {parada} {hora} {paradas_restantes} {cambios}\n'
                  '(las de "salida" son del viaje de ida; las de "regreso", del viaje de regreso)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton.icon(icon: const Icon(Icons.save), onPressed: () => Navigator.pop(context, controller.text), label: const Text('Guardar ajuste')),
          ],
        ),
      );
  }
}

/// Texto legible del valor de un ajuste.
String describeSetting(SettingDefinition definition, String value) {
  switch (definition.valueType) {
    case 'boolean':
      return value == '1' ? 'Sí' : 'No';
    case 'option':
      return definition.options[value] ?? value;
    case 'string':
      return value.length > 60 ? '${value.substring(0, 60)}…' : value;
    default:
      return value;
  }
}
