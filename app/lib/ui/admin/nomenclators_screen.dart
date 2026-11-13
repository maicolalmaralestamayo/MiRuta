import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/busy.dart';
import '../widgets/common.dart';
import '../widgets/data_view.dart';
import '../widgets/marks.dart';

IconData nomenclatorIcon(String type) => switch (type) {
      'vehicle-types' => Icons.directions_bus,
      'absence-types' => Icons.event_busy,
      'conversation-topics' => Icons.forum_outlined,
      'denial-reasons' => Icons.block,
      _ => Icons.report_outlined,
    };

/// Nomencladores (docs/11 §11.26 y §11.31, maqueta G18 n.º 17): una sección
/// plegable por nomenclador. Lo que está en uso no se elimina: se propone
/// desactivarlo (§11.29).
///
/// Desde Gestión se abre un solo nomenclador ([only]) desde su tarjeta
/// (docs/11 §11.56 y §11.59).
class NomenclatorsScreen extends StatefulWidget {
  final Nomenclator? only;

  const NomenclatorsScreen({super.key, this.only});

  @override
  State<NomenclatorsScreen> createState() => _NomenclatorsScreenState();
}

class _NomenclatorsScreenState extends State<NomenclatorsScreen> {
  final _view = GlobalKey<DataViewState<Map<String, List<NomenclatorItem>>>>();
  final _marks = Marks();

  List<Nomenclator> get _list => widget.only == null ? Nomenclator.all : [widget.only!];

  Future<Map<String, List<NomenclatorItem>>> _load() async {
    final api = context.read<Session>().api;
    return {for (final n in _list) n.type: (await api.getAll('/${n.type}')).map(NomenclatorItem.from).toList()};
  }

  Future<void> _open(Nomenclator n, [NomenclatorItem? item]) async {
    await push(context, NomenclatorForm(nomenclator: n, item: item));
    _view.currentState?.reload();
  }

  Future<void> _delete(Nomenclator n, List<NomenclatorItem> items) async {
    if (!await confirmDelete(context, items.length == 1 ? '«${items.first.name}»' : '${items.length} elementos de ${n.title}')) return;
    if (!mounted) return;
    var deleted = 0;
    final api = context.read<Session>().api;
    final inUse = <NomenclatorItem>[];
    for (final item in items) {
      try {
        await api.delete('/${n.type}/${item.id}');
        deleted++;
      } on ApiException catch (error) {
        if (error.hasCode('NOMENCLATOR_IN_USE')) {
          inUse.add(item);
        } else {
          rethrow;
        }
      }
    }
    if (inUse.isNotEmpty && mounted) {
      final deactivate = await confirm(context, 'En uso', '${inUse.map((i) => '«${i.name}»').join(', ')} ${inUse.length == 1 ? 'está' : 'están'} en uso y no se ${inUse.length == 1 ? 'puede' : 'pueden'} eliminar. ¿Desactivar${inUse.length == 1 ? 'lo' : 'los'}?',
          accept: 'Desactivar', icon: Icons.toggle_off_outlined);
      if (deactivate) {
        for (final item in inUse) {
          await api.patch('/${n.type}/${item.id}', resourceData(n.type, id: item.id, attributes: {'active': false}));
        }
        if (mounted) showResult(ScaffoldMessenger.of(context), n.done('desactivad', plural: inUse.length > 1));
      }
    }
    if (deleted > 0 && inUse.isEmpty && mounted) showResult(ScaffoldMessenger.of(context), n.done('eliminad', plural: deleted > 1));
    _marks.clear();
    _view.currentState?.reload();
  }

  List<ActionItem> _actions() {
    final data = _view.currentState?.data ?? const {};
    if (!_marks.active) return [for (final n in _list) ActionItem(nomenclatorIcon(n.type), 'Crear ${n.singular}', () => _open(n))];
    final n = _list.firstWhere((n) => n.type == _marks.type);
    final items = data[n.type] ?? const [];
    final marked = _marks.of(n.type, items, (i) => i.id);
    return [
      ...markActions(_marks, items.map((i) => i.id)),
      if (marked.length == 1) ActionItem(Icons.edit_outlined, 'Editar', () => _open(n, marked.first)),
      ActionItem(Icons.delete_outline, 'Eliminar', () => _delete(n, marked), destructive: true),
    ];
  }

  String _line(NomenclatorItem i) => switch (i.kind) {
        'vehicle-types' => '${i.seats} asientos • ${i.standing} de pie • ${i.total} en total',
        'denial-reasons' => '${switch (i.applicationType) { 'entidad' => 'Solicitudes de Entidad', 'itinerario' => 'Solicitudes de itinerario', _ => 'Todas las solicitudes' }} • usado ${i.usageCount}',
        _ => '${i.description ?? ''}${i.description == null ? '' : ' • '}usado ${i.usageCount}',
      };

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.only?.title ?? 'Nomencladores',
      tab: MainTab.management,
      marks: _marks,
      actions: _actions,
      body: DataView<Map<String, List<NomenclatorItem>>>(
        key: _view,
        load: _load,
        builder: (context, data, reload) => ListView(padding: const EdgeInsets.only(bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
          for (final n in _list)
            FoldSection<NomenclatorItem>(
              storageKey: 'nomencladores.${n.type}',
              title: n.title,
              items: data[n.type] ?? const [],
              initiallyOpen: widget.only != null || n == Nomenclator.vehicleTypes,
              builder: (i) => ListenableBuilder(
                listenable: _marks,
                builder: (context, _) => InfoCard(
                  images: [CardImage(icon: nomenclatorIcon(n.type), dim: !i.active)],
                  title: i.name,
                  lines: [_line(i)],
                  chip: i.active ? null : const Chip2('Desactivado', grey),
                  dim: !i.active,
                  selected: _marks.isMarked(n.type, i.id),
                  onTap: () => _marks.active && _marks.type == n.type ? _marks.toggle(n.type, i.id) : _open(n, i),
                  onLongPress: () => _marks.toggle(n.type, i.id),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Formulario de un elemento de nomenclador.
class NomenclatorForm extends StatefulWidget {
  final Nomenclator nomenclator;
  final NomenclatorItem? item;

  const NomenclatorForm({super.key, required this.nomenclator, this.item});

  @override
  State<NomenclatorForm> createState() => _NomenclatorFormState();
}

class _NomenclatorFormState extends State<NomenclatorForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name);
  late final _description = TextEditingController(text: widget.item?.description);
  late final _observation = TextEditingController(text: widget.item?.observation);
  late final _seats = TextEditingController(text: '${widget.item?.seats ?? 0}');
  late final _standing = TextEditingController(text: '${widget.item?.standing ?? 0}');
  late String? _applicationType = widget.item?.applicationType;
  late bool _active = widget.item?.active ?? true;
  late final List<Object?> _initial = _snapshot();
  bool _leaving = false;

  List<Object?> _snapshot() => [_name.text, _description.text, _observation.text, _seats.text, _standing.text, _applicationType, _active];

  bool get _dirty => !_leaving && !listEquals(_initial, _snapshot());

  @override
  void initState() {
    super.initState();
    _initial;
  }

  String get _type => widget.nomenclator.type;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final attributes = {
      'name': _name.text.trim(),
      'description': t(_description),
      'observation': t(_observation),
      'active': _active,
      if (_type == 'vehicle-types') ...{'seats': int.tryParse(_seats.text) ?? 0, 'standing': int.tryParse(_standing.text) ?? 0},
      if (_type == 'denial-reasons') 'applicationType': _applicationType,
    };
    final api = context.read<Session>().api;
    final ok = await runAction(context, () async {
      if (widget.item == null) {
        await api.post('/$_type', resourceData(_type, attributes: attributes));
      } else {
        await api.patch('/$_type/${widget.item!.id}', resourceData(_type, id: widget.item!.id, attributes: attributes));
      }
    }, success: widget.nomenclator.done(widget.item == null ? 'cread' : 'actualizad'));
    if (ok && mounted) {
      _leaving = true;
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = (int.tryParse(_seats.text) ?? 0) + (int.tryParse(_standing.text) ?? 0);
    return LeaveGuard(
      dirty: () => _dirty,
      child: AppScaffold(
      title: widget.nomenclator.title,
      tab: MainTab.management,
      actions: () => [ActionItem(Icons.save_outlined, 'Guardar', _save)],
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 96), children: [
          FormText(controller: _name, label: 'Nombre', validator: (v) => requiredText(v, 'Escriba el nombre')),
          FormText(controller: _description, label: 'Descripción', maxLines: 2),
          FormText(controller: _observation, label: 'Observación', maxLines: 2, last: _type != 'vehicle-types'),
          if (_type == 'vehicle-types') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: TextFormField(
                controller: _seats,
                decoration: const InputDecoration(labelText: 'Asientos'),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: TextFormField(
                controller: _standing,
                decoration: const InputDecoration(labelText: 'De pie'),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
              ),
            ),
            FormText(key: ValueKey(total), label: 'Total', value: '$total', readOnly: true),
          ],
          if (_type == 'denial-reasons')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: DropdownButtonFormField<String?>(
                initialValue: _applicationType,
                decoration: const InputDecoration(labelText: 'Tipo de solicitud'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Las dos')),
                  DropdownMenuItem(value: 'entidad', child: Text('Entidad')),
                  DropdownMenuItem(value: 'itinerario', child: Text('Itinerario')),
                ],
                onChanged: (v) => setState(() => _applicationType = v),
              ),
            ),
          ActiveSwitch(value: _active, onChanged: (v) => setState(() => _active = v)),
        ]),
      ),
    ),
    );
  }
}
