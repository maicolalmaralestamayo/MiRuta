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
      final limits = [
        if (definition.minValue != null) 'mínimo ${definition.minValue}',
        if (definition.maxValue != null) 'máximo ${definition.maxValue}',
      ].join(', ');
      return showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(definition.name),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(helperText: limits.isEmpty ? null : limits),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, int.tryParse(controller.text)), child: const Text('Guardar')),
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
                Text(
                  'Variables: {itinerario} {tipo} {matricula} {chofer} {capacidad} {fecha_salida} {hora_salida} {punto_salida} '
                  '{fecha_regreso} {hora_regreso} {punto_regreso} {parada} {hora} {paradas_restantes} {cambios}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Guardar')),
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
