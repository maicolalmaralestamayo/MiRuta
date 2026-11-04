import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../core/username.dart';
import '../../models/models.dart';
import '../../services/api/accounts_api.dart';
import '../../services/templates.dart';
import '../auth/names_fields.dart';
import '../navigation.dart';
import '../qr/printed_qr.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'management.dart';
import 'worker_actions.dart';
import 'worker_form_screen.dart';

/// Registrar a una persona en una Entidad (el Administrador, docs/11 §11.5 y
/// §11.9): nombres y apellidos, carné, si tiene teléfono, y el usuario y la
/// contraseña propuestos por el sistema, que se pueden cambiar. Si el carné
/// ya existe no se crea otra cuenta: se le añade la Entidad, ya aprobada.
class RegisterWorkerScreen extends StatefulWidget {
  final Entity entity;

  const RegisterWorkerScreen({super.key, required this.entity});

  @override
  State<RegisterWorkerScreen> createState() => _RegisterWorkerScreenState();
}

class _RegisterWorkerScreenState extends State<RegisterWorkerScreen> {
  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _firstSurname = TextEditingController();
  final _secondSurname = TextEditingController();
  final _identityCard = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _hasPhone = true;

  /// Quien registra cambió el usuario propuesto: ya no se propone otro solo.
  bool _usernameEdited = false;
  Timer? _debounce;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _suggestPassword();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_firstName, _middleName, _firstSurname, _secondSurname, _identityCard, _username, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  PersonName get _name => PersonName(
        firstName: _firstName.text.trim(),
        middleName: _middleName.text.trim(),
        firstSurname: _firstSurname.text.trim(),
        secondSurname: _secondSurname.text.trim(),
      );

  Future<void> _suggestPassword() async {
    try {
      final password = await AccountsApi(context.api).passwordSuggestion();
      if (mounted) setState(() => _password.text = password);
    } catch (_) {
      // Sin propuesta: la escribe quien registra.
    }
  }

  Future<void> _suggestUsername({bool force = false}) async {
    if (_usernameEdited && !force) return;
    final name = _name;
    if (name.firstName.isEmpty || name.firstSurname.isEmpty) return;
    try {
      final username = await AccountsApi(context.api).usernameSuggestion(name);
      if (!mounted || username.isEmpty) return;
      setState(() {
        _username.text = username;
        if (force) _usernameEdited = false;
      });
    } catch (_) {}
  }

  void _namesChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _suggestUsername);
  }

  Future<void> _register() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final api = context.api;
    try {
      final document = await api.post('/workers', resourceData('workers', attributes: {
        ..._name.toAttributes(),
        'identityCard': _identityCard.text.trim(),
        'hasPhone': _hasPhone,
        'username': Username.normalize(_username.text),
        'password': _password.text,
      }, relationships: {'entity': ResourceId('entities', widget.entity.id)}));
      final resource = document.resource;
      if (!mounted) return;
      await Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => RegisteredWorkerScreen(
          item: WorkerItem.from(resource),
          entity: widget.entity,
          accountCreated: resource.meta['accountCreated'] != false,
          username: resource.meta['username'] as String?,
          password: resource.meta['password'] as String?,
        ),
      ));
    } on ApiException catch (error) {
      setState(() => _error = error);
      _form.currentState!.validate();
      if (_fieldErrors(error).isEmpty && mounted) showError(context, error);
    }
  }

  Map<String, String> _fieldErrors(ApiException error) => {
        for (final field in ['/identityCard', '/username', '/password', '/firstName', '/firstSurname', '/secondSurname'])
          if (error.fieldError(field) != null) field: error.fieldError(field)!,
      };

  @override
  Widget build(BuildContext context) {
    final card = _identityCard.text.trim();
    final birth = IdentityCard.birthDate(card);
    final errors = _error == null ? const <String, String>{} : _fieldErrors(_error!);
    return AppScaffold(
      title: 'Registrar persona',
      tab: MainTab.more,
      actions: [
        ActionItem(icon: Icons.how_to_reg, label: 'Registrar', onPressed: _register),
        ActionItem(icon: Icons.password, label: 'Proponer otra contraseña', onPressed: _suggestPassword),
        ActionItem(icon: Icons.alternate_email, label: 'Proponer el usuario', onPressed: () => _suggestUsername(force: true)),
      ],
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
          EntityCard(widget.entity),
          const SizedBox(height: 12),
          NamesFields(firstName: _firstName, middleName: _middleName, firstSurname: _firstSurname, secondSurname: _secondSurname, onChanged: _namesChanged),
          TextFormField(
            key: const ValueKey('identityCard'),
            controller: _identityCard,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(IdentityCard.length)],
            decoration: InputDecoration(labelText: 'Carné de identidad', prefixIcon: const Icon(Icons.badge_outlined), errorText: errors['/identityCard']),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: IdentityCard.validate,
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 12),
          ReadOnlyField(label: 'Sexo y nacimiento', value: birth == null ? '' : '${sexLabel(IdentityCard.sex(card))} • ${formatShortDate(birth)}'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tiene teléfono'),
            subtitle: Text(_hasPhone ? 'Usará el QR de la app.' : 'Se le generará un QR impreso, que no caduca.'),
            value: _hasPhone,
            onChanged: (v) => setState(() => _hasPhone = v),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('username'),
            controller: _username,
            decoration: InputDecoration(
              labelText: 'Usuario',
              prefixIcon: const Icon(Icons.alternate_email),
              helperText: 'Propuesto por el sistema; puede cambiarlo.',
              errorText: errors['/username'],
              suffixIcon: IconButton(tooltip: 'Proponer el usuario', icon: const Icon(Icons.refresh), onPressed: () => _suggestUsername(force: true)),
            ),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: validateUsername,
            onChanged: (_) => setState(() {
              _usernameEdited = true;
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('password'),
            controller: _password,
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: const Icon(Icons.password),
              helperText: 'Al entrar por primera vez tendrá que cambiarla.',
              errorText: errors['/password'],
              suffixIcon: IconButton(tooltip: 'Proponer otra contraseña', icon: const Icon(Icons.refresh), onPressed: _suggestPassword),
            ),
            validator: (v) => (v ?? '').isEmpty ? 'Escriba la contraseña' : null,
            onChanged: (_) => setState(() => _error = null),
          ),
          if (_error != null && errors.isEmpty) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          BusyButton(onPressed: _register, showErrors: false, icon: const Icon(Icons.how_to_reg), child: const Text('Registrar')),
        ]),
      ),
    );
  }
}

/// Después de registrar: la tarjeta de la persona, su usuario y su
/// contraseña con botones para copiarlos y compartirlos (docs/11 §11.5). Si
/// ya tenía cuenta, solo se dice que se le añadió la Entidad.
class RegisteredWorkerScreen extends StatelessWidget {
  final WorkerItem item;
  final Entity entity;
  final bool accountCreated;
  final String? username;
  final String? password;

  const RegisteredWorkerScreen({super.key, required this.item, required this.entity, required this.accountCreated, this.username, this.password});

  @override
  Widget build(BuildContext context) {
    final worker = item.worker;
    final canPrint = !worker.hasPhone && context.me.can(Op.workersPrintedQr, entityId: entity.id, itineraryId: worker.itineraryId);
    final credentials = accountCreated && username != null && password != null;
    return AppScaffold(
      title: accountCreated ? 'Persona registrada' : 'Entidad añadida',
      tab: MainTab.more,
      actions: [
        ActionItem(
          icon: Icons.share,
          label: 'Compartir usuario y contraseña',
          enabled: credentials,
          onPressed: () => SharePlus.instance.share(ShareParams(text: 'MiRuta\nUsuario: $username\nContraseña: $password\nAl entrar por primera vez deberá cambiar la contraseña.')),
        ),
        ActionItem(icon: Icons.qr_code_2, label: 'QR impreso', enabled: canPrint, onPressed: () => openPrintedQr(context, worker)),
        ActionItem(
          icon: Icons.badge_outlined,
          label: 'Ver ficha',
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => WorkerFormScreen(item: item, entity: entity))),
        ),
        ActionItem(
          icon: Icons.person_add_alt_1,
          label: 'Registrar otra persona',
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RegisterWorkerScreen(entity: entity))),
        ),
      ],
      body: ListView(padding: const EdgeInsets.only(top: 8, bottom: 96), children: [
        UserCard(fullName: worker.fullName, photoUrl: worker.photoUrl, entities: item.entities),
        const SizedBox(height: 8),
        if (credentials) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Comuníquele su usuario y su contraseña. Al entrar por primera vez deberá cambiar la contraseña.'),
          ),
          CopyShareField(label: 'Usuario', value: username!),
          CopyShareField(label: 'Contraseña', value: password!),
        ] else
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Ya tenía cuenta en MiRuta: no se creó otra. Se le añadió ${entity.abbreviation}, ya aprobada. '
              '${worker.hasPhone ? 'Se le avisó en su teléfono.' : 'Comuníqueselo usted.'}',
            ),
          ),
        if (canPrint)
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.tonalIcon(onPressed: () => openPrintedQr(context, worker), icon: const Icon(Icons.qr_code_2), label: const Text('QR impreso')),
          ),
      ]),
    );
  }
}
