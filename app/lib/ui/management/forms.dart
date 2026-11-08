import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/json_api.dart';
import '../../core/username.dart';
import '../../models/models.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'ops.dart';

/// Elige una foto (cámara o galería) y la sube como multipart.
Future<bool> pickAndUpload(BuildContext context, String path, String field) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(children: [
        ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Hacer una foto'), onTap: () => Navigator.pop(context, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Elegir de la galería'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ]),
    ),
  );
  if (source == null) return false;
  final file = await ImagePicker().pickImage(source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
  if (file == null || !context.mounted) return false;
  return runAction(context, () => context.api.upload(path, field, file.path), success: 'Imagen guardada.');
}

/// Base de los formularios de consulta y edición (docs/11 §11.24): solo los
/// campos propios del objeto, sin datos de otras tablas, y el interruptor
/// «Activado»; Guardar y Eliminar en el menú Acciones.
abstract class _FormState<T extends StatefulWidget> extends State<T> {
  final form = GlobalKey<FormState>();
  bool active = true;

  bool get canEdit;

  bool get isNew;

  Future<void> save();

  Future<void> remove() async {}

  bool get canDelete => false;

  ApiClient get api => context.api;

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    if (await runAction(context, save, success: 'Guardado.') && mounted) Navigator.pop(context, true);
  }

  Future<void> _remove() async {
    await remove();
  }

  List<ActionItem> actions() => [
        if (canEdit) ActionItem(Icons.save_outlined, 'Guardar', _save),
        if (canDelete && !isNew) ActionItem(Icons.delete_outline, 'Eliminar', _remove, destructive: true),
      ];

  String? text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
}

// ---------------------------------------------------------------------------
// Entidad
// ---------------------------------------------------------------------------

class EntityForm extends StatefulWidget {
  final Entity? entity;

  const EntityForm({super.key, this.entity});

  @override
  State<EntityForm> createState() => _EntityFormState();
}

class _EntityFormState extends _FormState<EntityForm> {
  late final _abbreviation = TextEditingController(text: widget.entity?.abbreviation);
  late final _number = TextEditingController(text: widget.entity?.number);
  late final _name = TextEditingController(text: widget.entity?.name);
  late final _description = TextEditingController(text: widget.entity?.description);
  late final _observation = TextEditingController(text: widget.entity?.observation);
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    active = widget.entity?.active ?? true;
    _imageUrl = widget.entity?.imageUrl;
  }

  @override
  bool get canEdit => context.me.isAdmin;

  @override
  bool get isNew => widget.entity == null;

  @override
  bool get canDelete => context.me.isAdmin;

  @override
  Future<void> save() async {
    final attributes = {
      'abbreviation': _abbreviation.text.trim().toUpperCase(),
      'number': text(_number),
      'name': _name.text.trim(),
      'description': text(_description),
      'observation': text(_observation),
      'active': active,
    };
    if (isNew) {
      await api.post('/entities', resourceData('entities', attributes: attributes));
    } else {
      await api.patch('/entities/${widget.entity!.id}', resourceData('entities', id: widget.entity!.id, attributes: attributes));
    }
  }

  @override
  Future<void> remove() async {
    if (!await confirmDelete(context, 'la Entidad ${widget.entity!.abbreviation}',
        consequences: 'Se eliminan sus itinerarios (con sus viajes y solicitudes). Las personas no se eliminan: quedan sin esa Entidad. Las paradas se conservan.')) {
      return;
    }
    if (mounted && await runAction(context, () => api.delete('/entities/${widget.entity!.id}'), success: 'Entidad eliminada.') && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final edit = canEdit;
    return AppScaffold(
      title: 'Entidad',
      tab: MainTab.management,
      actions: actions,
      body: Form(
        key: form,
        child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          PhotoHeader(
            url: _imageUrl,
            icon: Icons.apartment,
            onTap: edit && !isNew
                ? () async {
                    if (await pickAndUpload(context, '/entities/${widget.entity!.id}/image', 'image')) {
                      final r = (await api.get('/entities/${widget.entity!.id}')).resource;
                      if (mounted) setState(() => _imageUrl = r.string('imageUrl'));
                    }
                  }
                : null,
          ),
          FormText(controller: _abbreviation, label: 'Abreviatura', hint: 'p. ej. UMIM', readOnly: !edit, capitalization: TextCapitalization.characters, validator: (v) => requiredText(v, 'Escriba la abreviatura')),
          FormText(controller: _number, label: 'Número', hint: '4 dígitos', readOnly: !edit, keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              validator: (v) => (v ?? '').isEmpty || RegExp(r'^\d{4}$').hasMatch(v!) ? null : 'El número tiene 4 dígitos'),
          FormText(controller: _name, label: 'Nombre', readOnly: !edit, validator: (v) => requiredText(v, 'Escriba el nombre')),
          FormText(controller: _description, label: 'Descripción', readOnly: !edit, maxLines: 3),
          FormText(controller: _observation, label: 'Observación', readOnly: !edit, maxLines: 3),
          ActiveSwitch(value: active, onChanged: edit ? (v) => setState(() => active = v) : null),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Itinerario
// ---------------------------------------------------------------------------

class ItineraryForm extends StatefulWidget {
  final Itinerary? itinerary;

  /// Entidad del itinerario nuevo.
  final String? entityId;

  const ItineraryForm({super.key, this.itinerary, this.entityId});

  @override
  State<ItineraryForm> createState() => _ItineraryFormState();
}

class _ItineraryFormState extends _FormState<ItineraryForm> {
  late final _name = TextEditingController(text: widget.itinerary?.name);
  late final _description = TextEditingController(text: widget.itinerary?.description);
  late final _observation = TextEditingController(text: widget.itinerary?.observation);
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    active = widget.itinerary?.active ?? true;
    _imageUrl = widget.itinerary?.imageUrl;
  }

  @override
  bool get canEdit => context.me.isAdmin;

  @override
  bool get isNew => widget.itinerary == null;

  @override
  bool get canDelete => context.me.isAdmin;

  @override
  Future<void> save() async {
    final attributes = {'name': _name.text.trim(), 'description': text(_description), 'observation': text(_observation), 'active': active};
    if (isNew) {
      await api.post('/itineraries', resourceData('itineraries', attributes: attributes, relationships: {'entity': ResourceId('entities', widget.entityId!)}));
    } else {
      await api.patch('/itineraries/${widget.itinerary!.id}', resourceData('itineraries', id: widget.itinerary!.id, attributes: attributes));
    }
  }

  @override
  Future<void> remove() async {
    if (!await confirmDelete(context, 'el itinerario ${widget.itinerary!.name}',
        consequences: 'Sus personas quedan sin itinerario, parada ni jefatura; se eliminan sus viajes. Las paradas se conservan.')) {
      return;
    }
    if (mounted && await runAction(context, () => api.delete('/itineraries/${widget.itinerary!.id}'), success: 'Itinerario eliminado.') && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final edit = canEdit;
    return AppScaffold(
      title: 'Itinerario',
      tab: MainTab.management,
      actions: actions,
      body: Form(
        key: form,
        child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          PhotoHeader(
            url: _imageUrl,
            icon: Icons.route,
            onTap: edit && !isNew
                ? () async {
                    if (await pickAndUpload(context, '/itineraries/${widget.itinerary!.id}/image', 'image')) {
                      final r = (await api.get('/itineraries/${widget.itinerary!.id}')).resource;
                      if (mounted) setState(() => _imageUrl = r.string('imageUrl'));
                    }
                  }
                : null,
          ),
          FormText(controller: _name, label: 'Nombre', hint: 'p. ej. Ruta Playa', readOnly: !edit, validator: (v) => requiredText(v, 'Escriba el nombre')),
          FormText(controller: _description, label: 'Descripción', readOnly: !edit, maxLines: 3),
          FormText(controller: _observation, label: 'Observación', readOnly: !edit, maxLines: 3),
          ActiveSwitch(value: active, onChanged: edit ? (v) => setState(() => active = v) : null),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Parada
// ---------------------------------------------------------------------------

class StopForm extends StatefulWidget {
  final Stop? stop;

  /// Itinerario al que se añade la parada nueva (opcional para el Administrador).
  final String? itineraryId;

  /// Coordenadas ya puestas (ubicación compartida desde otra app).
  final double? latitude;
  final double? longitude;

  const StopForm({super.key, this.stop, this.itineraryId, this.latitude, this.longitude});

  @override
  State<StopForm> createState() => _StopFormState();
}

class _StopFormState extends _FormState<StopForm> {
  late final _landmark = TextEditingController(text: widget.stop?.landmark);
  late final _street = TextEditingController(text: widget.stop?.street);
  late final _cross1 = TextEditingController(text: widget.stop?.crossStreet1);
  late final _cross2 = TextEditingController(text: widget.stop?.crossStreet2);
  double? _latitude;
  double? _longitude;
  String? _imageUrl;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    active = widget.stop?.active ?? true;
    _imageUrl = widget.stop?.imageUrl;
    _latitude = widget.latitude ?? widget.stop?.latitude;
    _longitude = widget.longitude ?? widget.stop?.longitude;
  }

  @override
  bool get canEdit {
    final me = context.me;
    if (me.isAdmin) return true;
    if (me.chiefItineraryId == null) return false;
    return isNew || widget.stop!.positionIn(me.chiefItineraryId) != null;
  }

  @override
  bool get isNew => widget.stop == null;

  @override
  bool get canDelete => canEdit;

  /// «Usar mi ubicación actual» (se pulsa estando en la parada).
  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw StateError('Permita a MiRuta usar la ubicación.');
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
        throw StateError('Active la ubicación (GPS) y vuelva a intentarlo.');
      }
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 30)));
      setState(() {
        _latitude = double.parse(position.latitude.toStringAsFixed(6));
        _longitude = double.parse(position.longitude.toStringAsFixed(6));
      });
    } catch (error) {
      if (mounted) showError(context, error is StateError ? error : StateError('No se pudo obtener la ubicación.'));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Future<void> save() async {
    if (_latitude == null || _longitude == null) {
      throw StateError('Falta la ubicación: pulse «Usar mi ubicación actual» o compártala desde otra app.');
    }
    final attributes = {
      'landmark': _landmark.text.trim(),
      'street': _street.text.trim(),
      'crossStreet1': text(_cross1),
      'crossStreet2': text(_cross2),
      'latitude': _latitude,
      'longitude': _longitude,
      'active': active,
    };
    if (isNew) {
      await api.post('/stops', resourceData('stops', attributes: attributes, relationships: {
        if (widget.itineraryId != null) 'itinerary': ResourceId('itineraries', widget.itineraryId!),
      }));
    } else {
      await api.patch('/stops/${widget.stop!.id}', resourceData('stops', id: widget.stop!.id, attributes: attributes));
    }
  }

  @override
  Future<void> remove() async {
    if (!await confirmDelete(context, 'la parada ${widget.stop!.landmark}',
        consequences: 'Quien la tenía queda sin parada (conserva su itinerario). Si la usa otro itinerario, el Jefe no puede eliminarla: solo quitarla del suyo.')) {
      return;
    }
    if (mounted && await runAction(context, () => api.delete('/stops/${widget.stop!.id}'), success: 'Parada eliminada.') && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final edit = canEdit;
    return AppScaffold(
      title: 'Parada',
      tab: MainTab.management,
      actions: actions,
      body: Form(
        key: form,
        child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          PhotoHeader(
            url: _imageUrl,
            icon: Icons.place,
            onTap: edit && !isNew
                ? () async {
                    if (await pickAndUpload(context, '/stops/${widget.stop!.id}/image', 'image')) {
                      final r = (await api.get('/stops/${widget.stop!.id}')).resource;
                      if (mounted) setState(() => _imageUrl = r.string('imageUrl'));
                    }
                  }
                : null,
          ),
          FormText(controller: _landmark, label: 'Punto de referencia', hint: 'p. ej. Coppelia', readOnly: !edit, validator: (v) => requiredText(v, 'Escriba el punto de referencia')),
          FormText(controller: _street, label: 'Calle', hint: 'p. ej. Calle 23', readOnly: !edit, validator: (v) => requiredText(v, 'Escriba la calle')),
          FormText(controller: _cross1, label: 'Entrecalle 1', readOnly: !edit),
          FormText(controller: _cross2, label: 'Entrecalle 2', readOnly: !edit),
          FormText(key: ValueKey('lat$_latitude'), label: 'Latitud', value: _latitude?.toStringAsFixed(5) ?? '', readOnly: true),
          FormText(key: ValueKey('lon$_longitude'), label: 'Longitud', value: _longitude?.toStringAsFixed(5) ?? '', readOnly: true),
          if (edit)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: OutlinedButton.icon(
                onPressed: _locating ? null : _useCurrentLocation,
                icon: _locating ? const BusyIndicator(size: 18) : const Icon(Icons.my_location),
                label: const Text('Usar mi ubicación actual'),
              ),
            ),
          ActiveSwitch(value: active, onChanged: edit ? (v) => setState(() => active = v) : null),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trabajador (persona)
// ---------------------------------------------------------------------------

class WorkerForm extends StatefulWidget {
  final Worker worker;

  const WorkerForm({super.key, required this.worker});

  @override
  State<WorkerForm> createState() => _WorkerFormState();
}

class _WorkerFormState extends _FormState<WorkerForm> {
  Person get _p => widget.worker.person;
  late final _first = TextEditingController(text: _p.name.firstName);
  late final _middle = TextEditingController(text: _p.name.middleName);
  late final _firstSurname = TextEditingController(text: _p.name.firstSurname);
  late final _secondSurname = TextEditingController(text: _p.name.secondSurname);
  late final _card = TextEditingController(text: _p.identityCard);
  late final _username = TextEditingController(text: _p.username);

  @override
  void initState() {
    super.initState();
    active = widget.worker.active;
  }

  bool get _admin => context.me.isAdmin;

  bool get _canActivate => widget.worker.hasMembership && (_admin || context.me.isChiefOf(widget.worker.itineraryId));

  @override
  bool get canEdit => _admin || _canActivate;

  @override
  bool get isNew => false;

  @override
  bool get canDelete => _admin && !_p.isAdmin;

  @override
  Future<void> save() async {
    if (_admin) {
      await api.patch('/users/${_p.id}', resourceData('users', id: _p.id, attributes: {
        ...PersonName(firstName: _first.text, middleName: _middle.text, firstSurname: _firstSurname.text, secondSurname: _secondSurname.text).toAttributes(),
        if (_card.text.trim().isNotEmpty) 'identityCard': _card.text.trim(),
        if (_username.text.trim().isNotEmpty) 'username': Username.normalize(_username.text),
      }));
    }
    if (_canActivate && active != widget.worker.active) {
      await api.patch('/workers/${widget.worker.id}', resourceData('workers', id: widget.worker.id, attributes: {'active': active}));
    }
  }

  @override
  Future<void> remove() async {
    if (!await confirmDelete(context, 'a ${_p.fullName}', consequences: 'Se elimina la persona con su cuenta, sus pertenencias y sus solicitudes.')) return;
    if (mounted && await runAction(context, () => api.delete('/users/${_p.id}'), success: 'Persona eliminada.') && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final edit = _admin;
    final card = _card.text.trim();
    return AppScaffold(
      title: 'Trabajador',
      tab: MainTab.management,
      actions: actions,
      body: Form(
        key: form,
        child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          PhotoHeader(url: _p.photoUrl, icon: Icons.person),
          FormText(controller: _first, label: 'Primer nombre', readOnly: !edit, capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el primer nombre')),
          FormText(controller: _middle, label: 'Segundo nombre', readOnly: !edit, capitalization: TextCapitalization.words),
          FormText(controller: _firstSurname, label: 'Primer apellido', readOnly: !edit, capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el primer apellido')),
          FormText(controller: _secondSurname, label: 'Segundo apellido', readOnly: !edit, capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el segundo apellido')),
          if (_p.identityCard != null)
            FormText(controller: _card, label: 'Carné de identidad', icon: Icons.badge_outlined, readOnly: !edit, keyboard: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)], validator: IdentityCard.validate),
          FormText(label: 'Sexo y nacimiento', value: sexAndBirth(_p.sex ?? IdentityCard.sex(card), _p.birthDate ?? IdentityCard.birthDate(card)), readOnly: true),
          if (_p.username != null) FormText(controller: _username, label: 'Usuario', icon: Icons.alternate_email, readOnly: !edit, validator: validateUsername),
          if (widget.worker.hasMembership) ActiveSwitch(value: active, onChanged: _canActivate ? (v) => setState(() => active = v) : null),
        ]),
      ),
    );
  }
}

/// «Registrar trabajador» (Administrador): persona nueva en una Entidad; el
/// sistema propone usuario y contraseña, que deberá cambiar al entrar.
class RegisterWorkerForm extends StatefulWidget {
  final Entity? entity;

  const RegisterWorkerForm({super.key, this.entity});

  @override
  State<RegisterWorkerForm> createState() => _RegisterWorkerFormState();
}

class _RegisterWorkerFormState extends State<RegisterWorkerForm> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _firstSurname = TextEditingController();
  final _secondSurname = TextEditingController();
  final _card = TextEditingController();
  Entity? _entity;

  @override
  void initState() {
    super.initState();
    _entity = widget.entity;
  }

  Future<void> _pickEntity() async {
    final list = await Ops(context).entities();
    if (!mounted) return;
    final e = await pickOne<Entity>(context, 'Entidad', list, (e) => e.abbreviation, subtitle: (e) => e.name);
    if (e != null) setState(() => _entity = e);
  }

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    if (_entity == null) {
      showMessage(context, 'Elija la Entidad.');
      return;
    }
    final document = await context.api.post('/workers', resourceData('workers', attributes: {
      ...PersonName(firstName: _first.text, middleName: _middle.text, firstSurname: _firstSurname.text, secondSurname: _secondSurname.text).toAttributes(),
      'identityCard': _card.text.trim(),
    }, relationships: {'entity': ResourceId('entities', _entity!.id)}));
    if (!mounted) return;
    final meta = document.meta;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(meta['created'] == false ? 'Ya estaba registrada' : 'Trabajador registrado'),
        content: SelectableText(meta['created'] == false
            ? 'Esa persona ya tenía cuenta: se le añadió la Entidad ${_entity!.abbreviation}.'
            : 'Comuníquele sus datos de acceso (deberá cambiar la contraseña al entrar):\n\nUsuario: ${meta['username']}\nContraseña: ${meta['password']}'),
        actions: [
          if (meta['created'] != false)
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: 'Usuario: ${meta['username']}\nContraseña: ${meta['password']}')),
              icon: const Icon(Icons.copy),
              label: const Text('Copiar'),
            ),
          FilledButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.check), label: const Text('Aceptar')),
        ],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final card = _card.text.trim();
    return AppScaffold(
      title: 'Registrar trabajador',
      tab: MainTab.management,
      actions: () => [ActionItem(Icons.person_add_alt_1, 'Registrar', _register)],
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 96), children: [
          SelectorCard(icon: Icons.apartment, title: _entity?.abbreviation ?? 'Elija la Entidad', lines: ['Entidad', if (_entity != null) _entity!.name], onTap: _pickEntity),
          FormText(controller: _first, label: 'Primer nombre', capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el primer nombre')),
          FormText(controller: _middle, label: 'Segundo nombre', capitalization: TextCapitalization.words),
          FormText(controller: _firstSurname, label: 'Primer apellido', capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el primer apellido')),
          FormText(controller: _secondSurname, label: 'Segundo apellido', capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el segundo apellido')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: TextFormField(
              controller: _card,
              decoration: InputDecoration(
                labelText: 'Carné de identidad',
                prefixIcon: const Icon(Icons.badge_outlined),
                helperText: IdentityCard.birthDate(card) == null ? null : sexAndBirth(IdentityCard.sex(card), IdentityCard.birthDate(card)),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: (_) => setState(() {}),
              validator: IdentityCard.validate,
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('El sistema propone el usuario y la contraseña; la persona deberá cambiar la contraseña al entrar.'),
          ),
        ]),
      ),
    );
  }
}
