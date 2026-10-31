import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../widgets/common.dart';

/// Abreviatura de la Entidad: se escribe (no hay lista) y la app muestra su
/// nombre para confirmar (docs/08-version-2.md §8.2).
class EntityAbbreviationField extends StatefulWidget {
  final TextEditingController controller;

  /// Sin sesión se identifica la instalación.
  final bool guest;

  const EntityAbbreviationField({super.key, required this.controller, this.guest = false});

  @override
  State<EntityAbbreviationField> createState() => _EntityAbbreviationFieldState();
}

class _EntityAbbreviationFieldState extends State<EntityAbbreviationField> {
  String? _name;
  String? _error;
  bool _busy = false;

  Future<void> _lookup() async {
    final abbreviation = widget.controller.text.trim();
    if (abbreviation.length < 2) return;
    setState(() {
      _busy = true;
      _error = null;
      _name = null;
    });
    try {
      final document = await context.api.get('/entities/lookup', query: {'abbreviation': abbreviation}, guest: widget.guest);
      if (mounted) setState(() => _name = document.resource.string('name'));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        if (!focused) _lookup();
      },
      child: TextFormField(
        controller: widget.controller,
        decoration: InputDecoration(
          labelText: 'Abreviatura de tu Entidad',
          prefixIcon: const Icon(Icons.apartment_outlined),
          helperText: _name ?? 'Pregúntala a tu superior si no la sabes',
          helperStyle: _name == null ? null : TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
          errorText: _error,
          errorMaxLines: 3,
          suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(12), child: BusyIndicator()) : IconButton(icon: const Icon(Icons.search), onPressed: _lookup),
        ),
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')), LengthLimitingTextInputFormatter(15)],
        onChanged: (_) {
          if (_name != null || _error != null) setState(() => _name = _error = null);
        },
        onFieldSubmitted: (_) => _lookup(),
        validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Escribe la abreviatura' : null,
      ),
    );
  }
}

/// Pase: número del trabajador dentro de su Entidad.
class PassField extends StatelessWidget {
  final TextEditingController controller;

  const PassField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Pase', prefixIcon: Icon(Icons.badge_outlined)),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
        validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Escribe tu Pase' : null,
      );
}
