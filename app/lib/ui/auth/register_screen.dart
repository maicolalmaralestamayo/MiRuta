import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../../core/username.dart';
import '../widgets/common.dart';
import 'names_fields.dart';
import 'password_fields.dart';
import 'person_fields.dart';

/// Registro (docs/11 §11.5 y §11.67): nombres, apellidos, correo electrónico,
/// sexo (por omisión Masculino) y fecha de nacimiento (opcional); usuario y
/// contraseña ya propuestos por el sistema y modificables. Sin Entidad: se
/// solicita después desde Inicio.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  /// Texto si el correo ya está registrado. El servidor lo devuelve igual
  /// (409 EMAIL_TAKEN); este es por si no llega.
  static const emailTaken =
      'Alguien ya se registró con este correo electrónico. Si fue usted, emplee la opción Olvidé usuario/contraseña. '
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
  final _email = TextEditingController();
  String _sex = 'M';
  DateTime? _birthDate;
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
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    for (final c in [_firstName, _middleName, _firstSurname, _secondSurname, _email, _username, _password, _confirmation]) {
      c.dispose();
    }
    super.dispose();
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
      await context.session.register(name: _names.value, email: _email.text, sex: _sex, birthDate: _birthDate, username: _username.text, password: _password.text);
      if (navigator.mounted) navigator.popUntil((route) => route.isFirst);
    } on ApiException catch (error) {
      setState(() => _error = error);
    }
  }

  String get _errorText {
    final error = _error!;
    if (error.hasCode('EMAIL_TAKEN')) {
      final detail = error.errors.firstWhere((e) => e.code == 'EMAIL_TAKEN').detail;
      return detail ?? RegisterScreen.emailTaken;
    }
    return error.message;
  }

  @override
  Widget build(BuildContext context) {
    final fieldErrors = _error == null ? false : (_error!.fieldError('/username') != null || _error!.fieldError('/email') != null);
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
          EmailField(
            controller: _email,
            errorText: _error?.hasCode('EMAIL_TAKEN') == true ? null : _error?.fieldError('/email'),
            onChanged: (_) {
              if (_error?.fieldError('/email') != null || _error?.hasCode('EMAIL_TAKEN') == true) setState(() => _error = null);
            },
          ),
          SexField(value: _sex, onChanged: (v) => setState(() => _sex = v)),
          BirthDateField(value: _birthDate, onChanged: (v) => setState(() => _birthDate = v)),
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
            textInputAction: TextInputAction.next,
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
          // La contraseña la escribe la persona: la app solo comprueba los requisitos (docs/11 §11.56).
          Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: PasswordFields(password: _password, confirmation: _confirmation)),
          if (_error != null && (!fieldErrors || _error!.hasCode('EMAIL_TAKEN'))) ...[
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
