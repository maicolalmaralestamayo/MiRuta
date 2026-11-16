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
import '../../services/shared_location.dart';
import '../../services/tracking/worker_tracker.dart' show GeoPoint;
import '../auth/password_fields.dart';
import '../navigation.dart';
import '../profile/children_screen.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../theme.dart';
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
  return runAction(context, () => context.api.upload(path, field, file.path), label: 'Actualizando Imagen');
}

// ---------------------------------------------------------------------------
// Abrir un objeto por su id (desde Inicio y desde las relaciones)
// ---------------------------------------------------------------------------

Future<bool?> openEntity(BuildContext context, String id) async {
  Entity? entity;
  final ok = await runAction(context, label: 'Consultando Entidad', () async => entity = Entity.from((await context.api.get('/entities/$id')).resource));
  if (!ok || entity == null || !context.mounted) return null;
  return push<bool>(context, EntityForm(entity: entity));
}

Future<bool?> openItinerary(BuildContext context, String id) async {
  Itinerary? itinerary;
  final ok = await runAction(context, label: 'Consultando Itinerario', () async => itinerary = Itinerary.from((await context.api.get('/itineraries/$id', query: {'include': 'entity'})).resource));
  if (!ok || itinerary == null || !context.mounted) return null;
  return push<bool>(context, ItineraryForm(itinerary: itinerary));
}

Future<bool?> openStop(BuildContext context, String id) async {
  Stop? stop;
  final ok = await runAction(context, label: 'Consultando Parada', () async => stop = Stop.from((await context.api.get('/stops/$id')).resource));
  if (!ok || stop == null || !context.mounted) return null;
  return push<bool>(context, StopForm(stop: stop));
}

Future<bool?> openWorker(BuildContext context, String userId, {Person? person}) => push<bool>(context, WorkerForm(userId: userId, person: person));

// ---------------------------------------------------------------------------
// Base de los formularios
// ---------------------------------------------------------------------------

/// Base de los formularios (docs/11 §11.56 a §11.59 y §11.65): los campos
/// del objeto con el interruptor «Activado» y sus relaciones debajo. Las
/// relaciones se eligen y se quitan en el propio formulario, al crear y al
/// actualizar, y quedan **pendientes** (marcadas) hasta Guardar, que lo guarda
/// todo de una vez con un solo spinner («Creando Parada» / «Actualizando
/// Parada»). Si se sale sin guardar, se pierden («Salir sin guardar»). Tras
/// guardar, el formulario sigue mostrando el registro guardado; «Crear
/// [Objeto]» en Acciones abre uno vacío del mismo tipo.
abstract class _FormState<T extends StatefulWidget> extends State<T> {
  final form = GlobalKey<FormState>();
  bool active = true;
  List<Object?>? _initial;
  bool _leaving = false;

  /// Relaciones elegidas o quitadas, pendientes de Guardar.
  final pending = <PendingOp>[];

  /// Id del registro recién creado (para guardar sus relaciones pendientes).
  String? createdId;

  /// Datos relacionados cargados (o el error al cargarlos).
  bool relationsLoading = false;
  Object? relationsError;

  bool get canEdit;

  bool get isNew;

  /// «Itinerario», «Parada»… para los textos («Crear Parada», «Creando Parada»).
  String get noun;

  bool get feminine => false;

  /// Valores editables, para saber si hay cambios sin guardar.
  List<Object?> snapshot();

  /// Guarda los campos; al crear, devuelve el registro creado.
  Future<Resource?> save();

  Future<void> remove() async {}

  bool get canDelete => false;

  /// Puede crear otro del mismo tipo («Crear [Objeto]»).
  bool get canCreate => false;

  /// Formulario vacío del mismo tipo.
  Widget? emptyForm() => null;

  /// Formulario del registro recién creado (el formulario sigue mostrándolo).
  Widget? savedForm(Resource created) => null;

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

  bool get dirty => !_leaving && canEdit && _initial != null && (pending.isNotEmpty || !listEquals(_initial, snapshot()));

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

  /// Guarda los campos y las relaciones pendientes con un solo spinner.
  Future<bool> _save() async {
    if (!form.currentState!.validate()) return false;
    Resource? created;
    final ok = await runAction(context, () async {
      created = await save();
      createdId = created?.id;
      for (final op in [...pending]) {
        await op.run();
        if (mounted) setState(() => pending.remove(op));
      }
    }, label: '${isNew ? 'Creando' : 'Actualizando'} $noun');
    if (!ok || !mounted) return false;
    if (isNew && created != null) {
      // El formulario sigue mostrando el registro guardado.
      final next = savedForm(created!);
      if (next != null) {
        _leaving = true;
        await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => next), result: true);
        return true;
      }
    }
    markClean();
    await reloadRelations();
    if (mounted) await context.read<Session>().reloadMe().catchError((_) {});
    return true;
  }

  /// «Crear [Objeto]»: un formulario vacío del mismo tipo, sin volver a la lista.
  Future<void> _createAnother() async {
    final next = emptyForm();
    if (next == null) return;
    if (dirty) {
      switch (await confirmLeave(context)) {
        case LeaveChoice.cancel:
          return;
        case LeaveChoice.save:
          if (!await _save() || !mounted) return;
        case LeaveChoice.leave:
          break;
      }
    }
    if (!mounted) return;
    _leaving = true;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => next), result: true);
  }

  /// Elimina con [path] tras confirmar (con sus consecuencias).
  Future<void> deleteWith(String path, String what, String consequences) async {
    if (!await confirmDelete(context, what, consequences: consequences) || !mounted) return;
    final ok = await runAction(context, () => api.delete(path), label: 'Eliminando $noun');
    if (ok && mounted) {
      _leaving = true;
      Navigator.pop(context, true);
    }
  }

  /// Elige o quita una relación: queda pendiente hasta Guardar (docs/11 §11.65).
  Future<void> relation(Future<bool> Function(Ops ops) action) async {
    await action(Ops(context, defer: defer));
    if (mounted) setState(() {});
  }

  /// Apunta un cambio de relación pendiente.
  void defer(PendingOp op) {
    if (mounted) setState(() => pending.add(op));
  }

  /// Una acción sobre otro objeto (p. ej. «Actualizar Solicitud: Aprobar»),
  /// que se hace al momento; al terminar recarga las relaciones.
  Future<void> now(Future<bool> Function() action, {String? label}) async {
    var changed = false;
    await runAction(context, () async => changed = await action(), label: label);
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
        if (canCreate) ActionItem(Icons.add, 'Crear $noun', _createAnother),
        if (canDelete && !isNew) ActionItem(Icons.delete_outline, 'Eliminar $noun', remove, destructive: true),
      ];

  String? text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  /// Cambios de relaciones pendientes de Guardar, marcados (se pueden deshacer).
  Widget pendingSection() => pending.isEmpty
      ? const SizedBox.shrink()
      : Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          shape: RoundedRectangleBorder(side: const BorderSide(color: orange, width: 1.5), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Text('Pendiente de guardar', style: TextStyle(fontWeight: FontWeight.w700, color: amber)),
            ),
            for (final op in pending)
              ListTile(
                dense: true,
                leading: Icon(op.icon, color: amber),
                title: Text(op.label),
                trailing: IconButton(tooltip: 'Deshacer', icon: const Icon(Icons.undo), onPressed: () => setState(() => pending.remove(op))),
              ),
          ]),
        );

  /// Pantalla del formulario con sus campos y sus relaciones.
  Widget formScaffold({required String title, required List<Widget> fields, List<Widget> relations = const [], List<ActionItem> Function()? extra}) {
    return LeaveGuard(
      dirty: () => dirty,
      onSave: canEdit ? _save : null,
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
            pendingSection(),
            if (relationsError != null && !relationsLoading)
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
  bool get canCreate => me.isAdmin;

  @override
  Widget emptyForm() => const EntityForm();

  @override
  Widget savedForm(Resource created) => EntityForm(entity: Entity.from(created));

  String get _id => _e?.id ?? createdId!;

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
  Future<Resource?> save() async {
    final attributes = {
      'abbreviation': _abbreviation.text.trim().toUpperCase(),
      'number': text(_number),
      'name': _name.text.trim(),
      'description': text(_description),
      'observation': text(_observation),
      'active': active,
    };
    if (isNew) return (await api.post('/entities', resourceData('entities', attributes: attributes))).resource;
    await api.patch('/entities/${_e!.id}', resourceData('entities', id: _e!.id, attributes: attributes));
    return null;
  }

  @override
  Future<void> remove() => deleteWith('/entities/${_e!.id}', 'la Entidad ${_e!.abbreviation}',
      'Sus itinerarios se conservan, sin Entidad. Las personas no se eliminan: quedan sin esa Entidad (y sin sus itinerarios en ella).');

  /// «Adicionar persona»: una que ya tiene cuenta o registrar una nueva.
  Future<void> _addPerson() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AppDialog(
        icon: const Icon(Icons.person_add_alt_1, size: 32),
        title: 'Adicionar persona',
        content: const Text('¿La persona ya tiene cuenta en MiRuta?', textAlign: TextAlign.center),
        buttons: [
          primaryButton(context, 'Elegir', Icons.search, () => Navigator.pop(context, 'existing')),
          otherButton(context, 'Crear Trabajador', Icons.badge_outlined, () => Navigator.pop(context, 'new')),
          cancelButton(context),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'new') {
      if (isNew) {
        showMessage(context, 'Guarde primero la Entidad para registrar en ella una persona nueva.');
        return;
      }
      await open(() => push<bool>(context, RegisterWorkerForm(entity: _e)));
      return;
    }
    await relation((ops) async {
      final person = await ops.pickPerson('Adicionar persona a ${_abbreviation.text.trim().toUpperCase()}', exclude: _workers.map((w) => w.person.id).toSet());
      if (person == null) return false;
      await ops.write('Adicionar persona: ${person.fullName}', Icons.person_add_alt_1,
          () async => api.post('/workers', resourceData('workers', relationships: {'entity': ResourceId('entities', _id), 'user': ResourceId('users', person.id)})));
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
          ActionItem(Icons.logout, 'Actualizar Entidad: Salir', () => relation((ops) => ops.leaveEntity(me.membershipIn(_e!.id)!))),
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
      relations: [
              if (!isNew)
              FoldSection<Itinerary>(
                storageKey: 'form.entidad.itinerarios',
                title: 'Itinerarios',
                items: _itineraries,
                emptyText: 'No tiene itinerarios.',
                builder: (i) => itineraryTile(i, showEntity: false, chief: me.isChiefOf(i.id), onTap: () => open(() => push<bool>(context, ItineraryForm(itinerary: i)))),
              ),
              if (admin && !isNew) RelationButton(Icons.add_road, 'Crear Itinerario', () => open(() => push<bool>(context, ItineraryForm(entityId: _e!.id, entityAbbreviation: _e!.abbreviation)))),
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
                      onTap: () => now(() => Ops(context).showApplication(a, mine: a.userId == me.userId, canResolve: admin), label: 'Actualizando Solicitud')),
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

  @override
  bool get canCreate => me.isAdmin;

  @override
  Widget emptyForm() => const ItineraryForm();

  @override
  Widget savedForm(Resource created) => ItineraryForm(itinerary: Itinerary.from(created));

  String get _id => _i?.id ?? createdId!;

  /// Gestiona sus paradas y personas (también al crearlo, el Administrador).
  bool get _manages => isNew ? me.isAdmin : (me.isAdmin || me.isChiefOf(_i!.id));

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
  Future<Resource?> save() async {
    final attributes = {'name': _name.text.trim(), 'description': text(_description), 'observation': text(_observation), 'active': active};
    final entity = _entityId == null ? null : ResourceId('entities', _entityId!);
    if (isNew) {
      return (await api.post('/itineraries', resourceData('itineraries', attributes: attributes, relationships: {'entity': entity}))).resource;
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
    return null;
  }

  @override
  Future<void> remove() => deleteWith('/itineraries/${_i!.id}', 'el itinerario ${_i!.name}',
      'Sus personas salen de él (pierden su parada y la jefatura en él); se eliminan sus viajes y solicitudes. Las paradas se conservan.');

  Future<void> _reorder(int from, int to) async {
    final ordered = [..._stops];
    ordered.insert(to, ordered.removeAt(from));
    setState(() {
      _stops = ordered;
      // Un solo cambio pendiente con el último orden.
      pending.removeWhere((op) => op.label == 'Ordenar paradas');
    });
    defer(PendingOp('Ordenar paradas', Icons.drag_indicator, () async {
      await api.patch('/itineraries/$_id/relationships/stops', {
        'data': [for (final s in ordered) ResourceId('stops', s.id).toJson()],
      });
    }));
  }

  /// «Adicionar parada»: una existente o una nueva.
  Future<void> _addStop() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AppDialog(
        icon: const Icon(Icons.add_location_alt_outlined, size: 32),
        title: 'Adicionar parada',
        content: const Text('¿Añadir una parada que ya existe o crear una nueva?', textAlign: TextAlign.center),
        buttons: [
          primaryButton(context, 'Existente', Icons.search, () => Navigator.pop(context, 'existing')),
          otherButton(context, 'Crear Parada', Icons.add_location_alt_outlined, () => Navigator.pop(context, 'new')),
          cancelButton(context),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'new') {
      if (isNew) {
        showMessage(context, 'Guarde primero el itinerario para crear en él una parada nueva.');
        return;
      }
      await open(() => push<bool>(context, StopForm(itineraryId: _i!.id)));
      return;
    }
    await relation((ops) async {
      final all = (await api.getAll('/stops')).map(Stop.from).where((s) => isNew || s.positionIn(_i!.id) == null).toList();
      if (!mounted) return false;
      final stop = await pickOne<Stop>(context, 'Adicionar parada', all, (s) => s.landmark, subtitle: (s) => s.address, search: true);
      if (stop == null) return false;
      await ops.write('Adicionar parada: ${stop.landmark}', Icons.add_location_alt_outlined,
          () async => api.post('/itinerary-stops', resourceData('itinerary-stops', relationships: {
                'itinerary': ResourceId('itineraries', _id),
                'stop': ResourceId('stops', stop.id),
              })));
      return true;
    });
  }

  Future<bool> _removeStop(Ops ops) async {
    final stop = await pickOne<Stop>(context, 'Quitar parada del itinerario', _stops, (s) => '${s.positionIn(_i!.id) ?? ''}. ${s.landmark}', subtitle: (s) => s.address);
    if (stop == null || !mounted) return false;
    if (!await confirm(context, 'Quitar parada', '¿Quitar ${stop.landmark} de ${_i!.name}? La parada se conserva; quien la tenía como parada habitual en este itinerario queda sin ella.',
        accept: 'Quitar', icon: Icons.playlist_remove, destructive: true, headerIcon: Icons.place)) {
      return false;
    }
    final link = stop.linkIn(_i!.id);
    if (link != null) await ops.write('Quitar parada: ${stop.landmark}', Icons.playlist_remove, () => api.delete('/itinerary-stops/${link.itineraryStopId}'));
    return true;
  }

  /// «Adicionar persona» al itinerario: el Administrador, cualquiera (entra
  /// en su Entidad); el Jefe, las de su Entidad. Parada opcional.
  Future<bool> _addPerson(Ops ops) async {
    if (_entityId == null) {
      showMessage(context, 'Asocie primero una Entidad al itinerario.');
      return false;
    }
    final person = await ops.pickPerson('Adicionar persona a ${_name.text.trim()}',
        query: me.isAdmin ? const {} : {'filter[entity]': _entityId}, exclude: _workers.map((p) => p.userId ?? '').toSet());
    if (person == null || !mounted) return false;
    // Parada habitual (opcional): solo para planificar (docs/11 §11.65).
    final stop = isNew ? (cancelled: false, stop: null) : await ops.pickStopOf(_i!.id, title: 'Parada habitual (opcional)');
    if (stop.cancelled) return false;
    await ops.write('Adicionar persona: ${person.fullName}${stop.stop == null ? '' : ' (parada habitual ${stop.stop!.landmark})'}', Icons.person_add_alt_1,
        () async => api.post('/worker-itineraries', resourceData('worker-itineraries', relationships: {
              'user': ResourceId('users', person.id),
              'itinerary': ResourceId('itineraries', _id),
              if (stop.stop != null) 'stop': ResourceId('stops', stop.stop!.id),
            })));
    return true;
  }

  Future<bool> _assignChief(Ops ops) async {
    final p = await pickOne<Placement>(context, 'Jefe de ${_i!.name}', _workers, (p) => p.userName ?? '', subtitle: (p) => p.isChief ? 'Ya es Jefe' : (p.stopLandmark ?? 'Sin parada habitual'));
    if (p == null || !mounted) return false;
    return ops.setChief(p, !p.isChief);
  }

  @override
  Widget build(BuildContext context) {
    final edit = canEdit;
    final manages = _manages;
    final draggable = manages && _stops.length > 1;
    return formScaffold(
      title: 'Itinerario',
      extra: () => [
        if (manages && _stops.isNotEmpty) ActionItem(Icons.playlist_remove, 'Actualizar Itinerario: Quitar parada', () => relation(_removeStop)),
        if (!isNew && me.isAdmin && _workers.isNotEmpty) ActionItem(Icons.badge_outlined, 'Actualizar Itinerario: Asignar o quitar Jefe', () => relation(_assignChief)),
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
      relations: [
              FoldSection<Stop>(
                storageKey: 'form.itinerario.paradas',
                title: draggable ? 'Paradas (arrastre para ordenar)' : 'Paradas',
                items: _stops,
                paginate: false,
                emptyText: 'No tiene paradas.',
                builder: (s) => stopTile(s, position: isNew ? null : s.positionIn(_i!.id), extra: s.address, onTap: () => open(() => push<bool>(context, StopForm(stop: s)))),
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
                      onTap: () => now(() => Ops(context).showApplication(a, mine: a.userId == me.userId, canResolve: manages), label: 'Actualizando Solicitud')),
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
  bool get canDelete => canEdit && !isNew;

  @override
  bool get canCreate => me.isAdmin || me.chiefItineraryId != null;

  @override
  Widget emptyForm() => StopForm(itineraryId: widget.itineraryId ?? (me.isAdmin ? null : me.chiefItineraryId));

  @override
  Widget savedForm(Resource created) => StopForm(stop: Stop.from(created));

  String get _id => widget.stop?.id ?? createdId!;

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

  /// «Pegar ubicación» (docs/11 §11.65): «lat, lng», enlaces de Google Maps,
  /// OsmAnd y OpenStreetMap y geo:lat,lng.
  Future<void> _pasteLocation() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    GeoPoint? point;
    try {
      // Los enlaces cortos de Google Maps se resuelven por Internet.
      point = await SharedLocation.resolve(clip?.text ?? '');
    } catch (_) {}
    if (!mounted) return;
    if (point == null) {
      showMessage(context, 'No se reconoce una ubicación en lo copiado');
      return;
    }
    setState(() {
      _latitude = double.parse(point!.latitude.toStringAsFixed(6));
      _longitude = double.parse(point.longitude.toStringAsFixed(6));
    });
  }

  @override
  Future<Resource?> save() async {
    if (_latitude == null || _longitude == null) {
      throw StateError('Falta la ubicación: pulse «Usar mi ubicación actual», «Pegar ubicación» o compártala desde otra app.');
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
      return (await api.post('/stops', resourceData('stops', attributes: attributes, relationships: {
        if (widget.itineraryId != null) 'itinerary': ResourceId('itineraries', widget.itineraryId!),
      })))
          .resource;
    }
    await api.patch('/stops/${widget.stop!.id}', resourceData('stops', id: widget.stop!.id, attributes: attributes));
    return null;
  }

  @override
  Future<void> remove() => deleteWith('/stops/${widget.stop!.id}', 'la parada ${widget.stop!.landmark}',
      'Quien la tenía queda sin parada (conserva su itinerario). Si la usa otro itinerario, el Jefe no puede eliminarla: solo quitarla del suyo.');

  /// «Asociar itinerario»: el Administrador, cualquiera; el Jefe, el suyo.
  /// También al crear la parada (queda pendiente hasta Guardar).
  Future<bool> _associate(Ops ops) async {
    final stop = _stop;
    var list = (await ops.itineraries())
        .where((i) => (stop == null || stop.positionIn(i.id) == null) && i.id != widget.itineraryId)
        .toList();
    if (!me.isAdmin) list = list.where((i) => i.id == me.chiefItineraryId).toList();
    if (!mounted) return false;
    if (list.isEmpty) {
      showMessage(context, 'No hay itinerarios que asociar.');
      return false;
    }
    final itinerary = await pickOne<Itinerary>(context, 'Asociar itinerario', list, (i) => i.name, subtitle: (i) => i.entityAbbreviation ?? 'Sin Entidad', search: list.length > 8);
    if (itinerary == null) return false;
    await ops.write('Asociar itinerario: ${itinerary.name}', Icons.playlist_add,
        () async => api.post('/itinerary-stops', resourceData('itinerary-stops', relationships: {
              'itinerary': ResourceId('itineraries', itinerary.id),
              'stop': ResourceId('stops', _id),
            })));
    return true;
  }

  Future<bool> _dissociate(Ops ops) async {
    final links = _stop!.itineraries.where((l) => me.isAdmin || me.isChiefOf(l.itineraryId)).toList();
    final link = await pickOne<StopLink>(context, 'Quitar de un itinerario', links, (l) => l.name, subtitle: (l) => l.entityAbbreviation ?? 'Sin Entidad');
    if (link == null || !mounted) return false;
    if (!await confirm(context, 'Quitar del itinerario', '¿Quitar ${_stop!.landmark} de ${link.name}? La parada se conserva (aunque quede sin itinerario).',
        accept: 'Quitar', icon: Icons.playlist_remove, destructive: true, headerIcon: Icons.route)) {
      return false;
    }
    await ops.write('Quitar del itinerario ${link.name}', Icons.playlist_remove, () => api.delete('/itinerary-stops/${link.itineraryStopId}'));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final edit = canEdit;
    final manages = me.isAdmin || me.chiefItineraryId != null;
    final links = _stop?.itineraries ?? const <StopLink>[];
    return formScaffold(
      title: 'Parada',
      extra: () => [
        if (!isNew && manages && links.any((l) => me.isAdmin || me.isChiefOf(l.itineraryId)))
          ActionItem(Icons.playlist_remove, 'Actualizar Parada: Quitar de un itinerario', () => relation(_dissociate)),
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
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _locating ? null : _useCurrentLocation,
                  icon: _locating ? const BusyIndicator(size: 18) : const Icon(Icons.my_location),
                  label: const Text('Usar mi ubicación actual', textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(onPressed: _pasteLocation, icon: const Icon(Icons.content_paste), label: const Text('Pegar ubicación')),
              ),
            ]),
          ),
        ActiveSwitch(value: active, onChanged: edit ? (v) => setState(() => active = v) : null),
      ],
      relations: [
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
                title: 'Trabajadores con esta parada habitual',
                items: _workers,
                emptyText: 'Nadie la tiene como parada habitual.',
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
  bool get canCreate => _admin;

  @override
  Widget emptyForm() => const RegisterWorkerForm();

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
  Future<Resource?> save() async {
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
    return null;
  }

  @override
  Future<void> remove() => deleteWith('/users/${_p.id}', 'a ${_p.fullName}', 'Se elimina la persona con su cuenta, sus pertenencias y sus solicitudes.');

  // Relaciones

  bool _canAddIn(Membership m) => _admin || me.placements.any((p) => p.isChief && p.entityId == m.entityId);

  bool _canChange(Placement p) => _admin || _self || me.isChiefOf(p.itineraryId);

  Future<bool> _placementOptions(Ops ops, Placement p) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(title: Text(p.itineraryName, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text('${p.entityAbbreviation} • ${p.stopLandmark ?? 'Sin parada'}')),
          ListTile(leading: const Icon(Icons.route), title: const Text('Ver el itinerario'), onTap: () => Navigator.pop(context, 'open')),
          if (_canChange(p)) ListTile(leading: const Icon(Icons.where_to_vote_outlined), title: const Text('Parada habitual'), onTap: () => Navigator.pop(context, 'stop')),
          if (_admin) ListTile(leading: const Icon(Icons.badge_outlined), title: Text(p.isChief ? 'Quitar rol de Jefe' : 'Asignar rol de Jefe'), onTap: () => Navigator.pop(context, 'chief')),
          if (_canChange(p))
            ListTile(leading: const Icon(Icons.logout, color: red), title: Text(_self ? 'Salir del itinerario' : 'Quitar del itinerario', style: const TextStyle(color: red)), onTap: () => Navigator.pop(context, 'remove')),
        ]),
      ),
    );
    if (!mounted) return false;
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

  Future<bool> _membershipOptions(Ops ops, Membership m) async {
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
    switch (choice) {
      case 'open':
        await open(() => openEntity(context, m.entityId));
        return false;
      case 'absence':
        // La ausencia es otro objeto: se crea en su pantalla.
        return Ops(context).declareAbsence(widget.userId, _chiefOfHer && !_admin && !_self ? m.itineraries.where((p) => p.itineraryId == context.me.chiefItineraryId).toList() : m.itineraries, who: _self ? null : _p.fullName);
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
    final canChildren = _admin || _self;
    return formScaffold(
      title: 'Trabajador',
      extra: () => [
        if (_admin) ActionItem(Icons.add_business_outlined, 'Actualizar Trabajador: Asociar Entidad', () => relation((ops) => ops.associateEntity([widget.userId], exclude: _p.memberships.map((m) => m.entityId).toSet()))),
        if (_admin || me.chiefItineraryId != null)
          ActionItem(Icons.add_road, 'Actualizar Trabajador: Añadir itinerario', () => relation((ops) => ops.addItinerary(me, widget.userId, exclude: {for (final m in _p.memberships) ...m.itineraries.map((p) => p.itineraryId)}))),
        if (canChildren) ActionItem(Icons.person_add_alt_1, 'Crear Hijo', _openChild),
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
            membershipTile(m, onTap: () => relation((ops) => _membershipOptions(ops, m))),
            for (final p in m.itineraries) placementTile(p, indent: true, onTap: () => relation((ops) => _placementOptions(ops, p))),
            if (_canAddIn(m))
              RelationButton(Icons.add_road, 'Añadir itinerario en ${m.entityAbbreviation}', indent: true,
                  () => relation((ops) => ops.addItinerary(me, widget.userId, entityId: m.entityId, exclude: m.itineraries.map((p) => p.itineraryId).toSet()))),
          ]),
        ),
        if (_admin)
          RelationButton(Icons.add_business_outlined, 'Asociar Entidad',
              () => relation((ops) => ops.associateEntity([widget.userId], exclude: _p.memberships.map((m) => m.entityId).toSet()))),
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
    final ok = await runAction(context, label: 'Creando Trabajador', () async {
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
    if (meta['created'] != false) {
      await showDialog<void>(
        context: context,
        builder: (context) => AppDialog(
          icon: const Icon(Icons.how_to_reg, size: 32, color: green),
          title: 'Trabajador creado',
          content: SelectableText('Comuníquele sus datos de acceso (deberá cambiar la contraseña al entrar):\n\nUsuario: ${meta['username']}\nContraseña: ${_password.text}'),
          buttons: [
            primaryButton(context, 'Copiar', Icons.copy, () => Clipboard.setData(ClipboardData(text: 'Usuario: ${meta['username']}\nContraseña: ${_password.text}'))),
            cancelButton(context, label: 'Cerrar'),
          ],
        ),
      );
    }
    if (!mounted) return;
    // El formulario sigue mostrando lo guardado: la ficha del trabajador.
    final userId = document!.resource.relId('user')?.id;
    if (userId != null) {
      await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => WorkerForm(userId: userId)), result: true);
    } else {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _card.text.trim();
    return LeaveGuard(
      dirty: () => _dirty,
      child: AppScaffold(
        title: 'Crear Trabajador',
        tab: MainTab.management,
        actions: () => [ActionItem(Icons.person_add_alt_1, 'Crear Trabajador', _register)],
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
