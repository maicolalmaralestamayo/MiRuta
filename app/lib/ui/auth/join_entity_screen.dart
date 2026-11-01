import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../widgets/common.dart';
import 'entity_field.dart';

/// Paso 2 del registro, «Otros datos del registro» (docs/09 §4), obligatorio
/// salvo para el Administrador: la Entidad (su abreviatura), el Pase, el sexo
/// (Masculino por defecto) y la jerarquía.
class JoinEntityScreen extends StatefulWidget {
  const JoinEntityScreen({super.key});

  @override
  State<JoinEntityScreen> createState() => _JoinEntityScreenState();
}

class _JoinEntityScreenState extends State<JoinEntityScreen> {
  final _form = GlobalKey<FormState>();
  final _abbreviation = TextEditingController();
  final _pass = TextEditingController();
  String? _sex = 'M';
  String? _rankId;
  List<Rank> _ranks = [];
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _loadRanks();
  }

  Future<void> _loadRanks() async {
    try {
      final resources = await context.api.getAll('/ranks', query: {'sort': 'sortOrder,name'});
      if (mounted) setState(() => _ranks = resources.map(Rank.from).toList());
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _join() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await context.session.joinEntity(abbreviation: _abbreviation.text, pass: int.parse(_pass.text), sex: _sex!, rankId: _rankId!);
    } on ApiException catch (error) {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Otros datos del registro'), actions: [
        IconButton(tooltip: 'Cerrar sesión', icon: const Icon(Icons.logout), onPressed: () => context.session.logout()),
      ]),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          EntityAbbreviationField(controller: _abbreviation),
          const SizedBox(height: 12),
          PassField(controller: _pass),
          const SizedBox(height: 12),
          FormField<String>(
            validator: (_) => _sex == null ? 'Indique el sexo' : null,
            builder: (state) => InputDecorator(
              decoration: InputDecoration(labelText: 'Sexo', errorText: state.errorText, border: InputBorder.none),
              child: SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'F', label: Text('Femenino')), ButtonSegment(value: 'M', label: Text('Masculino'))],
                selected: {?_sex},
                emptySelectionAllowed: true,
                onSelectionChanged: (value) => setState(() => _sex = value.isEmpty ? null : value.first),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _rankId,
            decoration: const InputDecoration(labelText: 'Jerarquía'),
            items: [for (final rank in _ranks) DropdownMenuItem(value: rank.id, child: Text(rank.name))],
            onChanged: (value) => setState(() => _rankId = value),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (v) => v == null ? 'Elija la jerarquía' : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(onPressed: _join, showErrors: false, icon: const Icon(Icons.how_to_reg), child: const Text('Completar registro')),
          const SizedBox(height: 24),
          const DeveloperChatButton(),
        ]),
      ),
    );
  }
}
