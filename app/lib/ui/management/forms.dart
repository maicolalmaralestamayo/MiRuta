import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/json_api.dart';
import '../../core/username.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../auth/password_fields.dart';
import '../navigation.dart';
import '../profile/children_screen.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/busy.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'ops.dart';
import 'tiles.dart';

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
  return runAction(context, () => context.api.upload(path, field, file.path), success: 'Imagen guardada');
}

// ---------------------------------------------------------------------------
// Abrir un objeto por su id (desde Inicio y desde las relaciones)
// ---------------------------------------------------------------------------

Future<bool?> openEntity(BuildContext context, String id) async {
  Entity? entity;
  final ok = await runAction(context, () async => entity = Entity.from((await context.api.get('/entities/$id')).resource));
  if (!ok || entity == null || !context.mounted) return null;
  return push<bool>(context, EntityForm(entity: entity));
}

Future<bool?> openItinerary(BuildContext context, String id) async {
  Itinerary? itinerary;
  final ok = await runAction(context, () async => itinerary = Itinerary.from((await context.api.get('/itineraries/$id', query: {'include': 'entity'})).resource));
  if (!ok || itinerary == null || !context.mounted) return null;
  return push<bool>(context, ItineraryForm(itinerary: itinerary));
}

Future<bool?> openStop(BuildContext context, String id) async {
  Stop? stop;
  final ok = await runAction(context, () async => stop = Stop.from((await context.api.get('/stops/$id')).resource));
  if (!ok || stop == null || !context.mounted) return null;
  return push<bool>(context, StopForm(stop: stop));
}

Future<bool?> openWorker(BuildContext context, String userId, {Person? person}) => push<bool>(context, WorkerForm(userId: userId, person: person));

// ---------------------------------------------------------------------------
// Base de los formularios
// ---------------------------------------------------------------------------

/// Base de los formularios (docs/11 §11.56 a §11.59): los campos del objeto
/// con el interruptor «Activado», sus relaciones debajo (cargadas aparte y
/// gestionadas desde ellas), «Salir sin guardar» si hay cambios, el teclado
/// recorre los campos y Guardar y Eliminar en el menú Acciones.
abstract class _FormState<T extends StatefulWidget> extends State<T> {
  final form = GlobalKey<FormState>();
  bool active = true;
  List<Object?>? _initial;
  bool _leaving = false;

  /// Datos relacionados cargados (o el error al cargarlos).
  bool relationsLoading = false;
  Object? relationsError;

  bool get canEdit;

  bool get isNew;

  /// «Itinerario», «Parada»… para los mensajes («Itinerario creado»).
  String get noun;

  bool get feminine => false;

  /// Valores editables, para saber si hay cambios sin guardar.
  List<Object?> snapshot();

  Future<void> save();

  Future<void> remove() async {}

  bool get canDelete => false;

  /// Carga las relaciones del objeto (y lo recarga el botón Actualizar).
  Future<void> loadRelations() async {}

  ApiClient get api => context.api;

  Me get me => context.read<Session>().me!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) markClean();
    });
    if (!isNew) WidgetsBinding.instance.addPostFrameCallback((_) => reloadRelations());
  }

  void markClean() => _initial = snapshot();

  bool get dirty => !_leaving && canEdit && _initial != null && !listEquals(_initial, snapshot());

  Future<void> reloadRelations() async {
    if (!mounted) return;
    setState(() => relationsLoading = true);
    try {
      await loadRelations();
      relationsError = null;
    } catch (error) {
      relationsError = error;
    }
    if (mounted) setState(() => relationsLoading = false);
  }

  String done(String verb) => '$noun ${feminine ? '${verb}a' : '${verb}o'}';

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    final ok = await runAction(context, save, success: done(isNew ? 'cread' : 'actualizad'));
    if (ok && mounted) {
      _leaving = true;
      Navigator.pop(context, true);
    }
  }

  /// Elimina con [path] tras confirmar (con sus consecuencias).
  Future<void> deleteWith(String path, String what, String consequences) async {
    if (!await confirmDelete(context, what, consequences: consequences) || !mounted) return;
    final ok = await runAction(context, () => api.delete(path), success: done('eliminad'));
    if (ok && mounted) {
      _leaving = true;
      Navigator.pop(context, true);
    }
  }

  /// Operación de una relación (con spinner): al terminar recarga las relaciones.
  Future<void> relation(Future<bool> Function() action) async {
    var changed = false;
    await runAction(context, () async => changed = await action());
    if (changed && mounted) {
      await reloadRelations();
      if (mounted) await context.read<Session>().reloadMe().catchError((_) {});
    }
  }

  /// Abre otro formulario y, al volver, recarga las relaciones.
  Future<void> open(Future<bool?> Function() opener) async {
    await opener();
    if (mounted) await reloadRelations();
  }

  List<ActionItem> actions() => [
        if (canEdit) ActionItem(Icons.save_outlined, 'Guardar', _save),
        if (canDelete && !isNew) ActionItem(Icons.delete_outline, 'Eliminar', remove, destructive: true),
      ];

  String? text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  /// Pantalla del formulario con sus campos y sus relaciones.
  Widget formScaffold({required String title, required List<Widget> fields, List<Widget> relations = const [], List<ActionItem> Function()? extra}) {
    return LeaveGuard(
      dirty: () => dirty,
      child: AppScaffold(
        title: title,
        tab: MainTab.management,
        actions: () => [...actions(), ...?extra?.call()],
        onRefresh: isNew ? null : reloadRelations,
        body: Form(
          key: form,
          onChanged: () => setState(() {}),
          child: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
            ...fields,
            if (isNew && relations.isNotEmpty)
              const HintText('Guarde primero para ver y gestionar sus relaciones.')
            else if (relationsError != null && !relationsLoading)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(child: Text(errorText(relationsError))),
                  TextButton.icon(onPressed: reloadRelations, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
                ]),
              )
            else ...[
              if (relationsLoading) const LinearProgressIndicator(minHeight: 2),
              ...relations,
            ],
          ]),
        ),
      ),
    );
  }
}

/// Campo que elige de una lista (↕), p. ej. la Entidad del itinerario.
class SelectField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const SelectField({super.key, required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, suffixIcon: Icon(onTap == null ? Icons.lock_outline : Icons.unfold_more, size: onTap == null ? 18 : null)),
            child: Text(value),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Entidad: sus itinerarios, sus trabajadores y sus solicitudes
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
  List<Itinerary> _itineraries = const [];
  List<Worker> _workers = const [];
  List<Application> _applications = const [];

  Entity? get _e => widget.entity;

  @override
  void initState() {
    active = widget.entity?.active ?? true;
    _imageUrl = widget.entity?.imageUrl;
    super.initState();
  }

  @override
  bool get canEdit => context.read<Session>().me!.isAdmin;

  @override
  bool get isNew => _e == null;

  @override
  String get noun => 'Entidad';

  @override
  bool get feminine => true;

  @override
  bool get canDelete => me.isAdmin;

  @override
  List<Object?> snapshot() => [_abbreviation.text, _number.text, _name.text, _description.text, _observation.text, active];

  @override
  Future<void> loadRelations() async {
    final id = _e!.id;
    final results = await Future.wait([
      api.getAll('/itineraries', query: {'filter[entity]': id, 'include': 'entity'}),
      api.getAll('/workers', query: {'filter[entity]': id, 'include': 'user'}),
      api.getAll('/applications', query: {'filter[entity]': id, 'filter[type]': 'entidad', 'filter[status]': 'pendiente', 'include': 'user,entity'}),
    ]);
    _itineraries = results[0].map(Itinerary.from).toList();
    _workers = results[1].map(Worker.from).toList();
    _applications = results[2].map(Application.from).where((a) => a.userId != me.userId || me.isAdmin).toList();
  }

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
      await api.patch('/entities/${_e!.id}', resourceData('entities', id: _e!.id, attributes: attributes));
    }
  }

  @override
  Future<void> remove() => deleteWith('/entities/${_e!.id}', 'la Entidad ${_e!.abbreviation}',
      'Sus itinerarios se conservan, sin Entidad. Las personas no se eliminan: quedan sin esa Entidad (y sin sus itinerarios en ella).');

  /// «Adicionar persona»: una que ya tiene cuenta o registrar una nueva.
  Future<void> _addPerson() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.person_add_alt_1, size: 32),
        title: const Text('Adicionar persona', textAlign: TextAlign.center),
        content: const Text('¿La persona ya tiene cuenta en MiRuta?', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          cancelButton(context),
          TextButton.icon(onPressed: () => Navigator.pop(context, 'new'), icon: const Icon(Icons.badge_outlined), label: const Text('Registrar nueva')),
          FilledButton.icon(onPressed: () => Navigator.pop(context, 'existing'), icon: const Icon(Icons.search), label: const Text('Elegir')),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'new') {
      await open(() => push<bool>(context, RegisterWorkerForm(entity: _e)));
      return;
    }
    await relation(() async {
      final person = await Ops(context).pickPerson('Adicionar persona a ${_e!.abbreviation}', exclude: _workers.map((w) => w.person.id).toSet());
      if (person == null) return false;
      await api.post('/workers', resourceData('workers', relationships: {'entity': ResourceId('entities', _e!.id), 'user': ResourceId('users', person.id)}));
      if (mounted) Ops(context).done('Persona adicionada');
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final edit = canEdit;
    final admin = me.isAdmin;
    return formScaffold(
      title: 'Entidad',
      extra: () => [
        if (!isNew && me.membershipIn(_e!.id) != null && !admin)
          ActionItem(Icons.logout, 'Salir de la Entidad', () => relation(() => Ops(context).leaveEntity(me.membershipIn(_e!.id)!))),
      ],
      fields: [
        PhotoHeader(
          url: _imageUrl,
          icon: Icons.apartment,
          onTap: edit && !isNew
              ? () async {
                  if (await pickAndUpload(context, '/entities/${_e!.id}/image', 'image')) {
                    final r = (await api.get('/entities/${_e!.id}')).resource;
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
        FormText(controller: _observation, label: 'Observación', readOnly: !edit, maxLines: 3, last: true),
        ActiveSwitch(value: active, onChanged: edit ? (v) => setState(() => active = v) : null),
      ],
      relations: isNew
          ? const [SizedBox()]
          : [
              FoldSection<Itinerary>(
                storageKey: 'form.entidad.itinerarios',
                title: 'Itinerarios',
                items: _itineraries,
                emptyText: 'No tiene itinerarios.',
                builder: (i) => itineraryTile(i, showEntity: false, chief: me.isChiefOf(i.id), onTap: () => open(() => push<bool>(context, ItineraryForm(itinerary: i)))),
              ),
              if (admin) RelationButton(Icons.add_road, 'Crear itinerario', () => open(() => push<bool>(context, ItineraryForm(entityId: _e!.id, entityAbbreviation: _e!.abbreviation)))),
              FoldSection<Worker>(
                storageKey: 'form.entidad.trabajadores',
                title: 'Trabajadores',
                items: _workers,
                emptyText: 'No tiene trabajadores.',
                builder: (w) => workerTile(w, onTap: () => open(() => openWorker(context, w.person.id, person: w.person))),
              ),
              if (admin) RelationButton(Icons.person_add_alt_1, 'Adicionar persona', _addPerson),
              if (admin || _applications.isNotEmpty)
                FoldSection<Application>(
                  storageKey: 'form.entidad.solicitudes',
                  title: 'Solicitudes',
                  items: _applications,
                  emptyText: 'No hay solicitudes pendientes.',
                  builder: (a) => applicationTile(a, mine: a.userId == me.userId,
                      onTap: () => relation(() => Ops(context).showApplication(a, mine: a.userId == me.userId, canResolve: admin))),
                ),
            ],
    );
  }
}

// ---------------------------------------------------------------------------
// Itinerario: su Entidad, sus paradas (en orden), sus trabajadores y sus solicitudes
// ---------------------------------------------------------------------------

class ItineraryForm extends StatefulWidget {
  final Itinerary? itinerary;

  /// Entidad del itinerario nuevo (opcional: puede no tener).
  final String? entityId;
  final String? entityAbbreviation;

  const ItineraryForm({super.key, this.itinerary, this.entityId, this.entityAbbreviation});

  @override
  State<ItineraryForm> createState() => _ItineraryFormState();
}

class _ItineraryFormState extends _FormState<ItineraryForm> {
  late final _name = TextEditingController(text: widget.itinerary?.name);
  late final _description = TextEditingController(text: widget.itinerary?.description);
  late final _observation = TextEditingController(text: widget.itinerary?.observation);
  late String? _entityId = widget.itinerary == null ? widget.entityId : widget.itinerary!.entityId;
  late String? _entityName = widget.itinerary == null ? widget.entityAbbreviation : widget.itinerary!.entityAbbreviation;
  String? _imageUrl;
  List<Stop> _stops = const [];
  List<Placement> _workers = const [];
  List<Application> _applications = const [];

  Itinerary? get _i => widget.itinerary;

  @override
  void initState() {
    active = widget.itinerary?.active ?? true;
    _imageUrl = widget.itinerary?.imageUrl;
    super.initState();
  }

  @override
  bool get canEdit => context.read<Session>().me!.isAdmin;

  @override
  bool get isNew => _i == null;

  @override
  String get noun => 'Itinerario';

  @override
  bool get canDelete => me.isAdmin;

  bool get _manages => !isNew && (me.isAdmin || me.isChiefOf(_i!.id));

  @override
  List<Object?> snapshot() => [_name.text, _description.text, _observation.text, active, _entityId];

  @override
  Future<void> loadRelations() async {
    final id = _i!.id;
    final results = await Future.wait([
      api.getAll('/stops', query: {'filter[itinerary]': id, 'sort': 'position'}),
      api.getAll('/worker-itineraries', query: {'filter[itinerary]': id}),
      api.getAll('/applications', query: {'filter[itinerary]': id, 'filter[status]': 'pendiente', 'include': 'user,entity,itinerary,stop'}),
    ]);
    _stops = results[0].map(Stop.from).toList();
    _workers = results[1].map(Placement.from).toList();
    _applications = results[2].map(Application.from).toList();
  }

  Future<void> _pickEntity() async {
    final list = await Ops(context).entities();
    if (!mounted) return;
    const none = Entity(id: '', abbreviation: 'Sin Entidad');
    final options = [none, ...list];
    final e = await pickOne<Entity>(context, 'Entidad', options, (e) => e.abbreviation, subtitle: (e) => e.name, selected: options.where((e) => e.id == (_entityId ?? '')).firstOrNull);
    if (e == null) return;
    setState(() {
      _entityId = e.id.isEmpty ? null : e.id;
      _entityName = e.id.isEmpty ? null : e.abbreviation;
    });
  }

  @override
  Future<void> save() async {
    final attributes = {'name': _name.text.trim(), 'description': text(_description), 'observation': text(_observation), 'active': active};
    final entity = _entityId == null ? null : ResourceId('entities', _entityId!);
    if (isNew) {
      await api.post('/itineraries', resourceData('itineraries', attributes: attributes, relationships: {'entity': entity}));
      return;
    }
    if (_entityId != _i!.entityId && _workers.isNotEmpty) {
      final message = _entityId == null
          ? 'Sin Entidad, sus ${_workers.length} personas saldrán del itinerario. ¿Seguir?'
          : 'Sus ${_workers.length} personas pasarán con él a $_entityName (entrarán en esa Entidad). ¿Seguir?';
      if (!await confirm(context, 'Cambiar de Entidad', message, accept: 'Cambiar', icon: Icons.swap_horiz, headerIcon: Icons.apartment)) {
        throw StateError('No se guardó: la Entidad sigue igual.');
      }
    }
    await api.patch('/itineraries/${_i!.id}', resourceData('itineraries', id: _i!.id, attributes: attributes, relationships: {
      if (_entityId != _i!.entityId) 'entity': entity,
    }));
  }

  @override
  Future<void> remove() => deleteWith('/itineraries/${_i!.id}', 'el itinerario ${_i!.name}',
      'Sus personas salen de él (pierden su parada y la jefatura en él); se eliminan sus viajes y solicitudes. Las paradas se conservan.');

  Future<void> _reorder(int from, int to) async {
    final ordered = [..._stops];
    ordered.insert(to, ordered.removeAt(from));
    setState(() => _stops = ordered);
    await relation(() async {
      await api.patch('/itineraries/${_i!.id}/relationships/stops', {
        'data': [for (final s in ordered) ResourceId('stops', s.id).toJson()],
      });
      if (mounted) Ops(context).done('Orden guardado');
      return true;
    });
  }

  /// «Adicionar parada»: una existente o una nueva.
  Future<void> _addStop() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.add_location_alt_outlined, size: 32),
        title: const Text('Adicionar parada', textAlign: TextAlign.center),
        content: const Text('¿Añadir una parada que ya existe o crear una nueva?', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          cancelButton(context),
          TextButton.icon(onPressed: () => Navigator.pop(context, 'new'), icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Crear nueva')),
          FilledButton.icon(onPressed: () => Navigator.pop(context, 'existing'), icon: const Icon(Icons.search), label: const Text('Existente')),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'new') {
      await open(() => push<bool>(context, StopForm(itineraryId: _i!.id)));
      return;
    }
    await relation(() async {
      final all = (await api.getAll('/stops')).map(Stop.from).where((s) => s.positionIn(_i!.id) == null).toList();
      if (!mounted) return false;
      final stop = await pickOne<Stop>(context, 'Adicionar parada', all, (s) => s.landmark, subtitle: (s) => s.address, search: true);
      if (stop == null) return false;
      await api.post('/itinerary-stops', resourceData('itinerary-stops', relationships: {
        'itinerary': ResourceId('itineraries', _i!.id),
        'stop': ResourceId('stops', stop.id),
      }));
      if (mounted) Ops(context).done('Parada adicionada');
      return true;
    });
  }

  Future<bool> _removeStop() async {
    final stop = await pickOne<Stop>(context, 'Quitar parada del itinerario', _stops, (s) => '${s.positionIn(_i!.id) ?? ''}. ${s.landmark}', subtitle: (s) => s.address);
    if (stop == null || !mounted) return false;
    if (!await confirm(context, 'Quitar parada', '¿Quitar ${stop.landmark} de ${_i!.name}? La parada se conserva; quien la tenía en este itinerario queda sin parada.',
        accept: 'Quitar', icon: Icons.playlist_remove, destructive: true, headerIcon: Icons.place)) {
      return false;
    }
    final link = stop.linkIn(_i!.id);
    if (link != null) await api.delete('/itinerary-stops/${link.itineraryStopId}');
    if (mounted) Ops(context).done('Parada quitada');
    return true;
  }

  /// «Adicionar persona» al itinerario: el Administrador, cualquiera (entra
  /// en su Entidad); el Jefe, las de su Entidad. Parada opcional.
  Future<bool> _addPerson() async {
    if (_i!.entityId == null) {
      showMessage(context, 'Asocie primero una Entidad al itinerario.');
      return false;
    }
    final ops = Ops(context);
    final person = await ops.pickPerson('Adicionar persona a ${_i!.name}',
        query: me.isAdmin ? const {} : {'filter[entity]': _i!.entityId}, exclude: _workers.map((p) => p.userId ?? '').toSet());
    if (person == null || !mounted) return false;
    final stop = await ops.pickStopOf(_i!.id);
    if (stop.cancelled) return false;
    await api.post('/worker-itineraries', resourceData('worker-itineraries', relationships: {
      'user': ResourceId('users', person.id),
      'itinerary': ResourceId('itineraries', _i!.id),
      if (stop.stop != null) 'stop': ResourceId('stops', stop.stop!.id),
    }));
    ops.done('Persona adicionada');
    return true;
  }

  Future<bool> _assignChief() async {
    final p = await pickOne<Placement>(context, 'Jefe de ${_i!.name}', _workers, (p) => p.userName ?? '', subtitle: (p) => p.isChief ? 'Ya es Jefe' : (p.stopLandmark ?? 'Sin parada'));
    if (p == null || !mounted) return false;
    return Ops(context).setChief(p, !p.isChief);
  }

  @override
  Widget build(BuildContext context) {
    final edit = canEdit;
    final manages = _manages;
    final draggable = manages && _stops.length > 1;
    return formScaffold(
      title: 'Itinerario',
      extra: () => [
        if (manages && _stops.isNotEmpty) ActionItem(Icons.playlist_remove, 'Quitar parada', () => relation(_removeStop)),
        if (!isNew && me.isAdmin && _workers.isNotEmpty) ActionItem(Icons.badge_outlined, 'Asignar o quitar Jefe', () => relation(_assignChief)),
      ],
      fields: [
        PhotoHeader(
          url: _imageUrl,
          icon: Icons.route,
          onTap: edit && !isNew
              ? () async {
                  if (await pickAndUpload(context, '/itineraries/${_i!.id}/image', 'image')) {
                    final r = (await api.get('/itineraries/${_i!.id}')).resource;
                    if (mounted) setState(() => _imageUrl = r.string('imageUrl'));
                  }
                }
              : null,
        ),
        FormText(controller: _name, label: 'Nombre', hint: 'p. ej. Ruta Playa', readOnly: !edit, validator: (v) => requiredText(v, 'Escriba el nombre')),
        SelectField(label: 'Entidad', value: _entityName ?? 'Sin Entidad', onTap: edit ? _pickEntity : null),
        FormText(controller: _description, label: 'Descripción', readOnly: !edit, maxLines: 3),
        FormText(controller: _observation, label: 'Observación', readOnly: !edit, maxLines: 3, last: true),
        ActiveSwitch(value: active, onChanged: edit ? (v) => setState(() => active = v) : null),
      ],
      relations: isNew
          ? const [SizedBox()]
          : [
              FoldSection<Stop>(
                storageKey: 'form.itinerario.paradas',
                title: draggable ? 'Paradas (arrastre para ordenar)' : 'Paradas',
                items: _stops,
                paginate: false,
                emptyText: 'No tiene paradas.',
                builder: (s) => stopTile(s, position: s.positionIn(_i!.id), extra: s.address, onTap: () => open(() => push<bool>(context, StopForm(stop: s)))),
                child: draggable
                    ? ReorderableListView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        onReorderItem: _reorder,
                        children: [
                          for (var i = 0; i < _stops.length; i++)
                            KeyedSubtree(
                              key: ValueKey(_stops[i].id),
                              child: stopTile(_stops[i],
                                  position: i + 1,
                                  extra: _stops[i].address,
                                  trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
                                  onTap: () => open(() => push<bool>(context, StopForm(stop: _stops[i])))),
                            ),
                        ],
                      )
                    : null,
              ),
              if (manages) RelationButton(Icons.add_location_alt_outlined, 'Adicionar parada', _addStop),
              FoldSection<Placement>(
                storageKey: 'form.itinerario.trabajadores',
                title: 'Trabajadores',
                items: _workers,
                emptyText: 'No tiene trabajadores.',
                builder: (p) => placementPersonTile(p, onTap: () => open(() => openWorker(context, p.userId ?? ''))),
              ),
              if (manages) RelationButton(Icons.person_add_alt_1, 'Adicionar persona', () => relation(_addPerson)),
              if (manages || _applications.isNotEmpty)
                FoldSection<Application>(
                  storageKey: 'form.itinerario.solicitudes',
                  title: 'Solicitudes',
                  items: _applications,
                  emptyText: 'No hay solicitudes pendientes.',
                  builder: (a) => applicationTile(a, mine: a.userId == me.userId,
                      onTap: () => relation(() => Ops(context).showApplication(a, mine: a.userId == me.userId, canResolve: manages))),
                ),
            ],
    );
  }
}

// ---------------------------------------------------------------------------
// Parada: sus itinerarios y sus trabajadores
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
  late Stop? _stop = widget.stop;
  List<Placement> _workers = const [];

  @override
  void initState() {
    active = widget.stop?.active ?? true;
    _imageUrl = widget.stop?.imageUrl;
    _latitude = widget.latitude ?? widget.stop?.latitude;
    _longitude = widget.longitude ?? widget.stop?.longitude;
    super.initState();
  }

  @override
  bool get canEdit {
    final me = context.read<Session>().me!;
    if (me.isAdmin) return true;
    if (me.chiefItineraryId == null) return false;
    return widget.stop == null || widget.stop!.positionIn(me.chiefItineraryId) != null;
  }

  @override
  bool get isNew => widget.stop == null;

  @override
  String get noun => 'Parada';

  @override
  bool get feminine => true;

  @override
  bool get canDelete => canEdit;

  // Las coordenadas que vienen ya puestas (compartidas) también son un cambio.
  @override
  List<Object?> snapshot() => [_landmark.text, _street.text, _cross1.text, _cross2.text, active, isNew ? null : _latitude, isNew ? null : _longitude];

  @override
  bool get dirty => super.dirty || (!_leaving && isNew && widget.latitude != null && _initial != null);

  @override
  Future<void> loadRelations() async {
    final id = widget.stop!.id;
    final stop = Stop.from((await api.get('/stops/$id')).resource);
    final workers = (await api.getAll('/worker-itineraries', query: {'filter[stop]': id})).map(Placement.from).toList();
    _stop = stop;
    _workers = workers;
  }

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
  Future<void> remove() => deleteWith('/stops/${widget.stop!.id}', 'la parada ${widget.stop!.landmark}',
      'Quien la tenía queda sin parada (conserva su itinerario). Si la usa otro itinerario, el Jefe no puede eliminarla: solo quitarla del suyo.');

  /// «Asociar itinerario»: el Administrador, cualquiera; el Jefe, el suyo.
  Future<bool> _associate() async {
    final stop = _stop!;
    var list = (await Ops(context).itineraries()).where((i) => stop.positionIn(i.id) == null).toList();
    if (!me.isAdmin) list = list.where((i) => i.id == me.chiefItineraryId).toList();
    if (!mounted) return false;
    if (list.isEmpty) {
      showMessage(context, 'No hay itinerarios que asociar.');
      return false;
    }
    final itinerary = await pickOne<Itinerary>(context, 'Asociar itinerario', list, (i) => i.name, subtitle: (i) => i.entityAbbreviation ?? 'Sin Entidad', search: list.length > 8);
    if (itinerary == null) return false;
    await api.post('/itinerary-stops', resourceData('itinerary-stops', relationships: {
      'itinerary': ResourceId('itineraries', itinerary.id),
      'stop': ResourceId('stops', stop.id),
    }));
    if (mounted) Ops(context).done('Itinerario asociado');
    return true;
  }

  Future<bool> _dissociate() async {
    final links = _stop!.itineraries.where((l) => me.isAdmin || me.isChiefOf(l.itineraryId)).toList();
    final link = await pickOne<StopLink>(context, 'Quitar de un itinerario', links, (l) => l.name, subtitle: (l) => l.entityAbbreviation ?? 'Sin Entidad');
    if (link == null || !mounted) return false;
    if (!await confirm(context, 'Quitar del itinerario', '¿Quitar ${_stop!.landmark} de ${link.name}? La parada se conserva (aunque quede sin itinerario).',
        accept: 'Quitar', icon: Icons.playlist_remove, destructive: true, headerIcon: Icons.route)) {
      return false;
    }
    await api.delete('/itinerary-stops/${link.itineraryStopId}');
    if (mounted) Ops(context).done('Itinerario quitado');
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final edit = canEdit;
    final manages = !isNew && (me.isAdmin || me.chiefItineraryId != null);
    final links = _stop?.itineraries ?? const <StopLink>[];
    return formScaffold(
      title: 'Parada',
      extra: () => [
        if (manages && links.any((l) => me.isAdmin || me.isChiefOf(l.itineraryId))) ActionItem(Icons.playlist_remove, 'Quitar de un itinerario', () => relation(_dissociate)),
      ],
      fields: [
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
        FormText(controller: _cross2, label: 'Entrecalle 2', readOnly: !edit, last: true),
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
      ],
      relations: isNew
          ? const [SizedBox()]
          : [
              FoldSection<StopLink>(
                storageKey: 'form.parada.itinerarios',
                title: 'Itinerarios',
                items: links,
                emptyText: 'No está en ningún itinerario.',
                builder: (l) => InfoCard(
                  images: const [CardImage(icon: Icons.route)],
                  title: l.name,
                  lines: ['${l.entityAbbreviation ?? 'Sin Entidad'} • parada ${l.position}'],
                  onTap: () => open(() => openItinerary(context, l.itineraryId)),
                ),
              ),
              if (manages) RelationButton(Icons.playlist_add, 'Asociar itinerario', () => relation(_associate)),
              FoldSection<Placement>(
                storageKey: 'form.parada.trabajadores',
                title: 'Trabajadores',
                items: _workers,
                emptyText: 'Nadie la tiene como parada.',
                builder: (p) => placementPersonTile(p, line: '${p.entityAbbreviation} • ${p.itineraryName}', onTap: () => open(() => openWorker(context, p.userId ?? ''))),
              ),
            ],
    );
  }
}

// ---------------------------------------------------------------------------
// Trabajador: sus Entidades (con sus itinerarios y paradas) y sus hijos
// ---------------------------------------------------------------------------

class WorkerForm extends StatefulWidget {
  final String userId;

  /// Datos ya conocidos (se recargan con sus relaciones).
  final Person? person;

  const WorkerForm({super.key, required this.userId, this.person});

  @override
  State<WorkerForm> createState() => _WorkerFormState();
}

class _WorkerFormState extends _FormState<WorkerForm> {
  late Person _p = widget.person ?? Person(id: widget.userId);
  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _firstSurname = TextEditingController();
  final _secondSurname = TextEditingController();
  final _card = TextEditingController();
  final _username = TextEditingController();
  List<Child> _children = const [];
  bool _loaded = false;

  @override
  void initState() {
    _fill(_p);
    super.initState();
  }

  void _fill(Person p) {
    _first.text = p.name.firstName;
    _middle.text = p.name.middleName;
    _firstSurname.text = p.name.firstSurname;
    _secondSurname.text = p.name.secondSurname;
    _card.text = p.identityCard ?? '';
    _username.text = p.username ?? '';
    active = p.memberships.isEmpty || p.memberships.every((m) => m.active);
  }

  bool get _admin => context.read<Session>().me!.isAdmin;

  bool get _self => context.read<Session>().me!.userId == widget.userId;

  /// Jefe de un itinerario de esta persona.
  bool get _chiefOfHer => _p.memberships.any((m) => m.itineraries.any((p) => me.isChiefOf(p.itineraryId)));

  bool get _canActivate => _p.memberships.isNotEmpty && (_admin || _chiefOfHer);

  @override
  bool get canEdit => _loaded && (_admin || _canActivate);

  @override
  bool get isNew => false;

  @override
  String get noun => 'Trabajador';

  @override
  bool get canDelete => _admin && !_p.isAdmin;

  @override
  List<Object?> snapshot() => [_first.text, _middle.text, _firstSurname.text, _secondSurname.text, _card.text, _username.text, active];

  @override
  Future<void> loadRelations() async {
    final person = Person.from((await api.get('/users/${widget.userId}')).resource);
    final children = (await api.getAll('/children', query: {'filter[parent]': widget.userId})).map(Child.from).toList();
    final wasDirty = dirty;
    _p = person;
    _children = children;
    if (!_loaded || !wasDirty) {
      _fill(person);
      _loaded = true;
      markClean();
    }
  }

  @override
  Future<void> save() async {
    if (_admin) {
      await api.patch('/users/${_p.id}', resourceData('users', id: _p.id, attributes: {
        ...PersonName(firstName: _first.text, middleName: _middle.text, firstSurname: _firstSurname.text, secondSurname: _secondSurname.text).toAttributes(),
        if (_card.text.trim().isNotEmpty) 'identityCard': _card.text.trim(),
        if (_username.text.trim().isNotEmpty) 'username': Username.normalize(_username.text),
      }));
    }
    if (_canActivate) {
      for (final m in _p.memberships.where((m) => m.active != active && (_admin || m.itineraries.any((p) => me.isChiefOf(p.itineraryId))))) {
        await api.patch('/workers/${m.workerId}', resourceData('workers', id: m.workerId, attributes: {'active': active}));
      }
    }
  }

  @override
  Future<void> remove() => deleteWith('/users/${_p.id}', 'a ${_p.fullName}', 'Se elimina la persona con su cuenta, sus pertenencias y sus solicitudes.');

  // Relaciones

  bool _canAddIn(Membership m) => _admin || me.placements.any((p) => p.isChief && p.entityId == m.entityId);

  bool _canChange(Placement p) => _admin || _self || me.isChiefOf(p.itineraryId);

  Future<bool> _placementOptions(Placement p) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(title: Text(p.itineraryName, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text('${p.entityAbbreviation} • ${p.stopLandmark ?? 'Sin parada'}')),
          ListTile(leading: const Icon(Icons.route), title: const Text('Ver el itinerario'), onTap: () => Navigator.pop(context, 'open')),
          if (_canChange(p)) ListTile(leading: const Icon(Icons.where_to_vote_outlined), title: const Text('Cambiar de parada'), onTap: () => Navigator.pop(context, 'stop')),
          if (_admin) ListTile(leading: const Icon(Icons.badge_outlined), title: Text(p.isChief ? 'Quitar rol de Jefe' : 'Asignar rol de Jefe'), onTap: () => Navigator.pop(context, 'chief')),
          if (_canChange(p))
            ListTile(leading: const Icon(Icons.logout, color: red), title: Text(_self ? 'Salir del itinerario' : 'Quitar del itinerario', style: const TextStyle(color: red)), onTap: () => Navigator.pop(context, 'remove')),
        ]),
      ),
    );
    if (!mounted) return false;
    final ops = Ops(context);
    switch (choice) {
      case 'open':
        await open(() => openItinerary(context, p.itineraryId));
        return false;
      case 'stop':
        return ops.changeStop(p);
      case 'chief':
        return ops.setChief(p, !p.isChief);
      case 'remove':
        return ops.removeFromItinerary(p, who: _self ? null : _p.fullName);
    }
    return false;
  }

  Future<bool> _membershipOptions(Membership m) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(title: Text(m.entityAbbreviation, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(m.entityName)),
          ListTile(leading: const Icon(Icons.apartment), title: const Text('Ver la Entidad'), onTap: () => Navigator.pop(context, 'open')),
          if (_admin || _self || _chiefOfHer) ListTile(leading: const Icon(Icons.event_busy), title: const Text('Declarar ausencia'), onTap: () => Navigator.pop(context, 'absence')),
          if (_admin || _self)
            ListTile(
              leading: const Icon(Icons.logout, color: red),
              title: Text(_self ? 'Salir de la Entidad' : 'Sacar de la Entidad', style: const TextStyle(color: red)),
              onTap: () => Navigator.pop(context, 'leave'),
            ),
        ]),
      ),
    );
    if (!mounted) return false;
    final ops = Ops(context);
    switch (choice) {
      case 'open':
        await open(() => openEntity(context, m.entityId));
        return false;
      case 'absence':
        return ops.declareAbsence([m], who: _self ? null : _p.fullName);
      case 'leave':
        return ops.leaveEntity(m, who: _self ? null : _p.fullName);
    }
    return false;
  }

  Future<void> _openChild([Child? child]) => open(() => push<bool>(context, ChildForm(child: child, parentId: widget.userId)));

  @override
  Widget build(BuildContext context) {
    final edit = _admin && _loaded;
    final card = _card.text.trim();
    final ops = Ops(context);
    final canChildren = _admin || _self;
    return formScaffold(
      title: 'Trabajador',
      extra: () => [
        if (_admin) ActionItem(Icons.add_business_outlined, 'Asociar Entidad', () => relation(() => ops.associateEntity([widget.userId], exclude: _p.memberships.map((m) => m.entityId).toSet()))),
        if (_admin || me.chiefItineraryId != null)
          ActionItem(Icons.add_road, 'Añadir itinerario', () => relation(() => ops.addItinerary(me, widget.userId, exclude: {for (final m in _p.memberships) ...m.itineraries.map((p) => p.itineraryId)}))),
        if (canChildren) ActionItem(Icons.person_add_alt_1, 'Añadir hijo', _openChild),
      ],
      fields: [
        PhotoHeader(url: _p.photoUrl, icon: Icons.person),
        FormText(controller: _first, label: 'Primer nombre', readOnly: !edit, capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el primer nombre')),
        FormText(controller: _middle, label: 'Segundo nombre', readOnly: !edit, capitalization: TextCapitalization.words),
        FormText(controller: _firstSurname, label: 'Primer apellido', readOnly: !edit, capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el primer apellido')),
        FormText(controller: _secondSurname, label: 'Segundo apellido', readOnly: !edit, capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el segundo apellido')),
        if (_p.identityCard != null)
          FormText(controller: _card, label: 'Carné de identidad', icon: Icons.badge_outlined, readOnly: !edit, keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)], validator: IdentityCard.validate, last: _p.username == null),
        if (_p.sex != null || _p.birthDate != null || card.isNotEmpty)
          FormText(key: ValueKey('sex$card'), label: 'Sexo y nacimiento', value: sexAndBirth(_p.sex ?? IdentityCard.sex(card), _p.birthDate ?? IdentityCard.birthDate(card)), readOnly: true),
        if (_p.username != null) FormText(controller: _username, label: 'Usuario', icon: Icons.alternate_email, readOnly: !edit, validator: validateUsername, last: true),
        if (_p.memberships.isNotEmpty) ActiveSwitch(value: active, onChanged: _canActivate ? (v) => setState(() => active = v) : null),
      ],
      relations: [
        FoldSection<Membership>(
          storageKey: 'form.trabajador.entidades',
          title: 'Entidades',
          items: _p.memberships,
          paginate: false,
          emptyText: 'No pertenece a ninguna Entidad.',
          builder: (m) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            membershipTile(m, onTap: () => relation(() => _membershipOptions(m))),
            for (final p in m.itineraries) placementTile(p, indent: true, onTap: () => relation(() => _placementOptions(p))),
            if (_canAddIn(m))
              RelationButton(Icons.add_road, 'Añadir itinerario en ${m.entityAbbreviation}', indent: true,
                  () => relation(() => ops.addItinerary(me, widget.userId, entityId: m.entityId, exclude: m.itineraries.map((p) => p.itineraryId).toSet()))),
          ]),
        ),
        if (_admin)
          RelationButton(Icons.add_business_outlined, 'Asociar Entidad',
              () => relation(() => ops.associateEntity([widget.userId], exclude: _p.memberships.map((m) => m.entityId).toSet()))),
        FoldSection<Child>(
          storageKey: 'form.trabajador.hijos',
          title: 'Hijos',
          items: _children,
          emptyText: 'No tiene hijos declarados.',
          builder: (c) => childTile(c, onTap: canChildren ? () => _openChild(c) : null),
        ),
        if (canChildren) RelationButton(Icons.person_add_alt_1, 'Añadir hijo', () => _openChild()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Registrar trabajador (Administrador)
// ---------------------------------------------------------------------------

/// «Registrar trabajador» (Administrador): persona nueva en una Entidad. El
/// Administrador escribe el usuario y la contraseña (la app no los propone,
/// docs/11 §11.56; solo comprueba los requisitos); la persona deberá cambiar
/// la contraseña al entrar.
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
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  Entity? _entity;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _entity = widget.entity;
  }

  bool get _dirty => !_done && [_first, _middle, _firstSurname, _secondSurname, _card, _username, _password].any((c) => c.text.trim().isNotEmpty);

  Future<void> _pickEntity() async {
    final list = await Ops(context).entities();
    if (!mounted) return;
    final e = await pickOne<Entity>(context, 'Entidad', list, (e) => e.abbreviation, subtitle: (e) => e.name, search: list.length > 8);
    if (e != null) setState(() => _entity = e);
  }

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    if (_entity == null) {
      showMessage(context, 'Elija la Entidad.');
      return;
    }
    JsonApiDocument? document;
    final ok = await runAction(context, () async {
      document = await context.api.post('/workers', resourceData('workers', attributes: {
        ...PersonName(firstName: _first.text, middleName: _middle.text, firstSurname: _firstSurname.text, secondSurname: _secondSurname.text).toAttributes(),
        'identityCard': _card.text.trim(),
        'username': Username.normalize(_username.text),
        'password': _password.text,
      }, relationships: {'entity': ResourceId('entities', _entity!.id)}));
    });
    if (!ok || !mounted) return;
    final meta = document!.meta;
    _done = true;
    showResult(ScaffoldMessenger.of(context), meta['created'] == false ? 'Ya tenía cuenta: Entidad asociada' : 'Trabajador registrado');
    if (meta['created'] != false) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.how_to_reg, size: 32, color: green),
          title: const Text('Trabajador registrado', textAlign: TextAlign.center),
          content: SelectableText('Comuníquele sus datos de acceso (deberá cambiar la contraseña al entrar):\n\nUsuario: ${meta['username']}\nContraseña: ${_password.text}'),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: 'Usuario: ${meta['username']}\nContraseña: ${_password.text}')),
              icon: const Icon(Icons.copy),
              label: const Text('Copiar'),
            ),
            FilledButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.check), label: const Text('Aceptar')),
          ],
        ),
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final card = _card.text.trim();
    return LeaveGuard(
      dirty: () => _dirty,
      child: AppScaffold(
        title: 'Registrar trabajador',
        tab: MainTab.management,
        actions: () => [ActionItem(Icons.person_add_alt_1, 'Registrar', _register)],
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 120), children: [
            SelectField(label: 'Entidad', value: _entity?.abbreviation ?? 'Elija la Entidad', onTap: widget.entity == null ? _pickEntity : null),
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
                textInputAction: TextInputAction.next,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                validator: IdentityCard.validate,
              ),
            ),
            FormText(controller: _username, label: 'Usuario', icon: Icons.alternate_email, capitalization: TextCapitalization.none, validator: validateUsername),
            Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 6), child: PasswordFields(password: _password, confirmation: _repeat)),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Si el carné ya tiene cuenta, solo se le añade la Entidad. La persona deberá cambiar la contraseña al entrar.'),
            ),
          ]),
        ),
      ),
    );
  }
}
