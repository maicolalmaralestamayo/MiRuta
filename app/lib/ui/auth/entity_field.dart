import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../widgets/common.dart';

/// Entidad (su abreviatura): se escribe (no hay lista) y la app muestra su
/// nombre debajo para confirmar (docs/08-version-2.md §8.2). Sin ayuda fija
/// (docs/09 §4).
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
          labelText: 'Entidad',
          hintText: 'p. ej. EMPRESA',
          prefixIcon: const Icon(Icons.apartment_outlined),
          // Solo el nombre de la Entidad encontrada, para confirmarla.
          helperText: _name,
          helperStyle: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
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
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Escriba la abreviatura de la Entidad (al menos 2 caracteres)' : null,
      ),
    );
  }
}
