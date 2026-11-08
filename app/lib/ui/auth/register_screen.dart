import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../../core/username.dart';
import '../../models/models.dart';
import '../widgets/common.dart';
import 'names_fields.dart';
import 'password_fields.dart';

/// Registro (docs/11 §11.5): nombres, apellidos y carné; usuario y
/// contraseña ya propuestos por el sistema y modificables. Sin Entidad: se
/// solicita después desde Inicio («Aún no tiene Entidad»).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  /// Texto exacto si el carné ya está registrado (docs/11 §11.5). El servidor
  /// lo devuelve igual (409 IDENTITY_CARD_TAKEN); este es por si no llega.
  static const identityCardTaken =
      'Alguien ya se registró con este carné de identidad. Si fue usted, emplee la opción Olvidé usuario/contraseña. '
      'Si no fue usted, comuníquese con el Administrador de la aplicación, o su Jefe de itinerario.';

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _firstSurname = TextEditingController();
  final _secondSurname = TextEditingController();
  final _identityCard = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  ApiException? _error;

  /// null = aún no se sabe; false = quien se registre será el Administrador.
  bool? _adminExists;

  /// El usuario lo escribió la persona: ya no se propone otro.
  bool _usernameEdited = false;
  Timer? _suggestTimer;

  late final _names = NamesFields(firstName: _firstName, middleName: _middleName, firstSurname: _firstSurname, secondSurname: _secondSurname, onChanged: (_) => _scheduleSuggestion());

  @override
  void initState() {
    super.initState();
    context.api.get('/registration-status').then((d) {
      if (mounted) setState(() => _adminExists = d.resource.boolean('adminExists'));
    }).catchError((_) {});
    _suggestPassword();
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    for (final c in [_firstName, _middleName, _firstSurname, _secondSurname, _identityCard, _username, _password, _confirmation]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _suggestPassword() async {
    try {
      final password = (await context.api.get('/password-suggestion')).resource.string('password') ?? '';
      if (!mounted || password.isEmpty) return;
      setState(() {
        _password.text = password;
        _confirmation.text = password;
      });
    } catch (_) {
      // Sin conexión: la escribe la persona.
    }
  }

  /// Propone el usuario al escribir los nombres (si la persona no lo cambió).
  void _scheduleSuggestion() {
    if (_usernameEdited) return;
    _suggestTimer?.cancel();
    _suggestTimer = Timer(const Duration(milliseconds: 600), _suggestUsername);
  }

  Future<void> _suggestUsername() async {
    final name = _names.value;
    if (name.firstName.isEmpty || name.firstSurname.isEmpty) return;
    try {
      final username = (await context.api.get('/username-suggestion', query: {
        'firstName': name.firstName,
        'middleName': name.middleName,
        'firstSurname': name.firstSurname,
        'secondSurname': name.secondSurname,
      })).resource.string('username') ?? '';
      if (mounted && !_usernameEdited && username.isNotEmpty) setState(() => _username.text = username);
    } catch (_) {
      // Sin conexión: lo escribe la persona.
    }
  }

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      final navigator = Navigator.of(context);
      await context.session.register(name: _names.value, identityCard: _identityCard.text, username: _username.text, password: _password.text);
      if (navigator.mounted) navigator.popUntil((route) => route.isFirst);
    } on ApiException catch (error) {
      setState(() => _error = error);
    }
  }

  String get _errorText {
    final error = _error!;
    if (error.hasCode('IDENTITY_CARD_TAKEN')) {
      final detail = error.errors.firstWhere((e) => e.code == 'IDENTITY_CARD_TAKEN').detail;
      return detail ?? RegisterScreen.identityCardTaken;
    }
    return error.message;
  }

  @override
  Widget build(BuildContext context) {
    final card = _identityCard.text.trim();
    final birth = IdentityCard.birthDate(card);
    final fieldErrors = _error == null ? false : (_error!.fieldError('/username') != null || _error!.fieldError('/identityCard') != null);
    return Scaffold(
      appBar: AppBar(title: const Text('Registrarme')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 16), children: [
          if (_adminExists == false) ...[
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const ListTile(
                leading: Icon(Icons.admin_panel_settings),
                title: Text('Primer registro'),
                subtitle: Text('Aún no hay Administrador: quien se registre primero será el Administrador de la aplicación.'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _names,
          Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 6), child: TextFormField(
            controller: _identityCard,
            decoration: InputDecoration(
              labelText: 'Carné de identidad',
              hintText: 'p. ej. 85031512345',
              prefixIcon: const Icon(Icons.badge_outlined),
              // El sexo y la fecha de nacimiento salen del carné (no se escriben).
              helperText: birth == null ? null : sexAndBirth(IdentityCard.sex(card), birth),
              errorText: _error?.hasCode('IDENTITY_CARD_TAKEN') == true ? null : _error?.fieldError('/identityCard'),
              errorMaxLines: 4,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(IdentityCard.length)],
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) => setState(() {
              if (_error?.fieldError('/identityCard') != null || _error?.hasCode('IDENTITY_CARD_TAKEN') == true) _error = null;
            }),
            validator: IdentityCard.validate,
          )),
          Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 6), child: TextFormField(
            controller: _username,
            decoration: InputDecoration(
              labelText: 'Nombre de usuario',
              helperText: 'Propuesto por el sistema; puede cambiarlo',
              prefixIcon: const Icon(Icons.alternate_email),
              errorText: _error?.fieldError('/username'),
              errorMaxLines: 3,
            ),
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [LengthLimitingTextInputFormatter(Username.maxLength)],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) {
              _usernameEdited = true;
              if (_error?.fieldError('/username') != null) setState(() => _error = null);
            },
            validator: validateUsername,
          )),
          Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: PasswordFields(password: _password, confirmation: _confirmation, initiallyVisible: true)),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: _suggestPassword, icon: const Icon(Icons.autorenew), label: const Text('Proponer otra contraseña')),
          ),
          if (_error != null && (!fieldErrors || _error!.hasCode('IDENTITY_CARD_TAKEN'))) ...[
            const SizedBox(height: 4),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_errorText, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ],
          const SizedBox(height: 20),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: BusyButton(onPressed: _register, icon: Icons.how_to_reg, label: 'Registrarme')),
        ]),
      ),
    );
  }
}
