import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

/// «Declarar ausencia» (docs/11 §11.61, maqueta G23 n.º 4): tipo, desde,
/// hasta (opcional: vacío = indefinida) y los itinerarios afectados (uno o
/// varios de la persona, de cualquiera de sus Entidades). Devuelve true si se
/// declaró.
class AbsenceScreen extends StatefulWidget {
  final String userId;
  final List<Placement> placements;
  final List<NomenclatorItem> types;

  /// Nombre de la persona si la declara otro (Administrador o Jefe).
  final String? who;

  /// Itinerarios marcados al abrir (por omisión, todos).
  final Set<String>? initial;

  const AbsenceScreen({super.key, required this.userId, required this.placements, required this.types, this.who, this.initial});

  @override
  State<AbsenceScreen> createState() => _AbsenceScreenState();
}

class _AbsenceScreenState extends State<AbsenceScreen> {
  NomenclatorItem? _type;
  DateTime _from = DateTime.now();
  DateTime? _to;
  final _note = TextEditingController();
  late final Set<String> _itineraries = {...(widget.initial ?? widget.placements.map((p) => p.itineraryId))};
  bool _dirty = false;

  Future<DateTime?> _pick(DateTime initial) =>
      showDatePicker(context: context, initialDate: initial, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100));

  void _touch(VoidCallback change) => setState(() {
        change();
        _dirty = true;
      });

  Future<void> _save() async {
    if (_type == null) {
      showMessage(context, 'Elija el tipo de ausencia.');
      return;
    }
    if (_itineraries.isEmpty) {
      showMessage(context, 'Marque al menos un itinerario.');
      return;
    }
    if (_to != null && _to!.isBefore(DateTime(_from.year, _from.month, _from.day))) {
      showMessage(context, '«Hasta» no puede ser anterior a «Desde».');
      return;
    }
    final api = context.api;
    final ok = await runAction(context, () async {
      await api.post('/absences', {
        'data': {
          'type': 'absences',
          'attributes': {
            'startsOn': apiDay(_from),
            'endsOn': _to == null ? null : apiDay(_to!),
            if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
          },
          'relationships': {
            'user': {'data': ResourceId('users', widget.userId).toJson()},
            'absenceType': {'data': ResourceId('absence-types', _type!.id).toJson()},
            'itineraries': {
              'data': [for (final id in _itineraries) ResourceId('itineraries', id).toJson()],
            },
          },
        },
      });
    }, success: 'Ausencia declarada');
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return LeaveGuard(
      dirty: () => _dirty,
      child: AppScaffold.list(
        title: widget.who == null ? 'Declarar ausencia' : 'Ausencia de ${widget.who}',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: DropdownButtonFormField<NomenclatorItem>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Tipo de ausencia'),
              items: [for (final type in widget.types) DropdownMenuItem(value: type, child: Text(type.name))],
              onChanged: (v) => _touch(() => _type = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: InkWell(
              onTap: () async {
                final d = await _pick(_from);
                if (d != null) _touch(() => _from = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Desde', prefixIcon: Icon(Icons.event)),
                child: Text(formatDate(_from)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: InkWell(
              onTap: () async {
                final d = await _pick(_to ?? _from);
                if (d != null) _touch(() => _to = d);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Hasta (opcional, vacío = indefinida)',
                  prefixIcon: const Icon(Icons.event_available),
                  suffixIcon: _to == null ? null : IconButton(tooltip: 'Sin fecha de fin', icon: const Icon(Icons.clear), onPressed: () => _touch(() => _to = null)),
                ),
                child: Text(_to == null ? 'Indefinida (hasta que la termine)' : formatDate(_to)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Text('Itinerarios afectados', style: t.textTheme.titleSmall!.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
          ),
          if (widget.placements.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No tiene itinerarios: la ausencia se declara por itinerario.')),
          for (final p in widget.placements)
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              value: _itineraries.contains(p.itineraryId),
              title: Text(p.itineraryName),
              subtitle: Text(p.entityAbbreviation),
              onChanged: (v) => _touch(() => v == true ? _itineraries.add(p.itineraryId) : _itineraries.remove(p.itineraryId)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Nota (opcional)'),
              maxLines: 2,
              textInputAction: TextInputAction.done,
              onChanged: (_) => _dirty = true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FilledButton.icon(onPressed: widget.placements.isEmpty ? null : _save, icon: const Icon(Icons.event_busy), label: const Text('Declarar ausencia')),
          ),
        ],
      ),
    );
  }
}
