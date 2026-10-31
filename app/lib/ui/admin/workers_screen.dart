import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../../services/templates.dart';
import '../applications/application_forms.dart';
import '../auth/entity_field.dart';
import '../auth/names_fields.dart';
import '../widgets/common.dart';

/// Trabajadores de la Entidad. Los Jefes de itinerario ven los de su
/// itinerario. Los superiores registran a quien no tiene teléfono (con un
/// código de activación) y asignan o quitan roles directamente
/// (docs/08-version-2.md §8.3 y §8.5). El Administrador activa y desactiva.
class WorkersScreen extends StatefulWidget {
  final List<String>? itineraryIds;

  const WorkersScreen({super.key, this.itineraryIds});

  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  final _view = GlobalKey<AsyncViewState<List<Worker>>>();
  String _search = '';
  String _active = 'true';

  Future<List<Worker>> _load() async {
    final api = context.api;
    final List<String?> itineraries = widget.itineraryIds ?? [null];
    final workers = <Worker>[];
    for (final itinerary in itineraries) {
      final resources = await api.getAll('/workers', query: {
        'include': 'rank,entity',
        ...context.entityFilter,
        'filter[itinerary]': ?itinerary,
        if (_search.isNotEmpty) 'filter[search]': _search,
        if (_active != 'true') 'filter[active]': _active,
      });
      workers.addAll(resources.map(Worker.from));
    }
    return workers;
  }

  Future<void> _register() async {
    if (context.entityRelationship() == null) return;
    final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RegisterWorkerScreen(itineraryIds: widget.itineraryIds)));
    if (created == true) _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.me.isAdmin;
    return Scaffold(
      appBar: AppBar(title: Text(widget.itineraryIds == null ? 'Trabajadores' : 'Miembros de mi itinerario')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _register,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Registrar sin teléfono'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre, usuario o Pase', isDense: true),
                onSubmitted: (value) {
                  _search = value.trim();
                  _view.currentState?.reload();
                },
              ),
            ),
            if (admin) ...[
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _active,
                items: const [
                  DropdownMenuItem(value: 'true', child: Text('Activos')),
                  DropdownMenuItem(value: 'false', child: Text('Inactivos')),
                  DropdownMenuItem(value: 'all', child: Text('Todos')),
                ],
                onChanged: (value) {
                  setState(() => _active = value!);
                  _view.currentState?.reload();
                },
              ),
            ],
          ]),
        ),
        Expanded(
          child: AsyncView<List<Worker>>(
            key: _view,
            load: _load,
            builder: (context, workers, reload) => ListView(padding: const EdgeInsets.only(bottom: 88), children: [
              ListTile(title: Text('${workers.length} trabajador(es)')),
              for (final w in workers)
                ListTile(
                  leading: WorkerAvatar(w),
                  title: Text(w.fullName, style: TextStyle(decoration: w.active ? null : TextDecoration.lineThrough)),
                  subtitle: Wrap(spacing: 8, children: [
                    if (w.pass != null) Text('Pase ${w.pass}'),
                    if (admin && w.entity != null) Text(w.entity!.abbreviation),
                    RankBadge(w.rank),
                    if (w.childrenCount > 0) Text('${w.childrenCount} niño(s)'),
                    if (!w.activated) const StatusChip('Sin activar', color: Colors.orange, icon: Icons.phonelink_off),
                  ]),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerDetailScreen(workerId: w.id)));
                    reload();
                  },
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Un trabajador: datos, roles (asignar y quitar) y, si no activó su cuenta,
/// su código de activación.
class WorkerDetailScreen extends StatefulWidget {
  final String workerId;

  const WorkerDetailScreen({super.key, required this.workerId});

  @override
  State<WorkerDetailScreen> createState() => _WorkerDetailScreenState();
}

class _WorkerDetailScreenState extends State<WorkerDetailScreen> {
  final _view = GlobalKey<AsyncViewState<Worker>>();

  Future<Worker> _load() async =>
      Worker.from((await context.api.get('/workers/${widget.workerId}', query: {'include': 'rank,entity,itinerary,stop'})).resource);

  Future<void> _assign(Worker worker, String type) async {
    if (await showApplicationForm(context, type, worker: worker)) _view.currentState?.reload();
  }

  Future<void> _assignDirect(Worker worker, String type) async {
    if (!await confirm(context, ApplicationType.label(type), '¿Asignar a ${worker.name.short}? Recibirá un aviso.', accept: 'Asignar')) return;
    if (!mounted) return;
    await context.api.post('/applications', resourceData('applications', attributes: {'type': type}, relationships: {'worker': ResourceId('workers', worker.id)}));
    if (mounted) showMessage(context, 'Asignado');
    _view.currentState?.reload();
  }

  Future<void> _remove(Worker worker, String type, {String? itineraryId}) async {
    if (!await confirm(context, ApplicationType.label(type), '¿Quitárselo a ${worker.name.short}? Recibirá un aviso.', accept: 'Quitar', destructive: true)) return;
    if (!mounted) return;
    await context.api.post('/applications', resourceData('applications', attributes: {'type': type}, relationships: {
      'worker': ResourceId('workers', worker.id),
      if (itineraryId != null) 'itinerary': ResourceId('itineraries', itineraryId),
    }));
    if (mounted) showMessage(context, 'Hecho');
    _view.currentState?.reload();
  }

  Future<void> _newCode(Worker worker) async {
    final document = await context.api.post('/workers/${worker.id}/activation-codes', const {});
    if (!mounted) return;
    await showActivationCode(context, worker, document.resource.meta['activationCode'] as String, document.resource.meta['activationExpiresAt'] as String?);
  }

  Future<void> _toggle(Worker worker) async {
    final activate = !worker.active;
    if (!await confirm(context, activate ? 'Activar' : 'Desactivar', '¿${activate ? 'Activar' : 'Desactivar'} a ${worker.fullName}?', destructive: !activate)) return;
    if (!mounted) return;
    await context.api.patch('/workers/${worker.id}', resourceData('workers', id: worker.id, attributes: {'active': activate}));
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.me;
    return Scaffold(
      appBar: AppBar(title: const Text('Trabajador')),
      body: AsyncView<Worker>(
        key: _view,
        load: _load,
        builder: (context, w, reload) {
          final transportChief = me.isAdmin || me.roles.isTransportChief;
          final chiefOfHis = me.isChiefOf(w.itineraryId);
          final roles = w.roles;
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            ListTile(
              leading: WorkerAvatar(w, radius: 28),
              title: Text(w.fullName, style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text([if (w.entity != null) w.entity!.abbreviation, if (w.pass != null) 'Pase ${w.pass}', w.sex == 'F' ? 'Mujer' : 'Hombre'].join(' · ')),
            ),
            ListTile(leading: const Icon(Icons.military_tech_outlined), title: Text(w.rank?.name ?? ''), subtitle: const Text('Jerarquía')),
            if (!w.activated) ...[
              const SectionTitle('Cuenta sin activar'),
              const ListTile(
                leading: Icon(Icons.phonelink_off),
                title: Text('Todavía no tiene usuario ni contraseña.'),
                subtitle: Text('Cuando tenga teléfono, entrará con "Ya me registró un superior" y su código.'),
              ),
              BusyListTile(leading: const Icon(Icons.key_outlined), title: const Text('Generar un código nuevo'), onTap: () => _newCode(w)),
            ],
            const SectionTitle('Itinerario'),
            BusyListTile(
              leading: const Icon(Icons.route),
              title: Text(w.itineraryId == null ? 'Sin itinerario' : 'Tiene itinerario y parada'),
              trailing: const Icon(Icons.edit_location_alt_outlined),
              onTap: () => _assign(w, ApplicationType.itineraryMembership),
            ),
            if (w.itineraryId != null && (transportChief || chiefOfHis))
              BusyListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Quitarlo del itinerario'),
                onTap: () => _remove(w, ApplicationType.itineraryLeave),
              ),
            if (transportChief) ...[
              const SectionTitle('Roles'),
              if (roles.isDriver)
                BusyListTile(leading: const Icon(Icons.airline_seat_recline_normal), title: const Text('Chofer'), trailing: const Text('Quitar'), onTap: () => _remove(w, ApplicationType.driverLeave))
              else
                BusyListTile(leading: const Icon(Icons.airline_seat_recline_normal), title: const Text('Hacerlo chofer'), trailing: const Icon(Icons.add), onTap: () => _assignDirect(w, ApplicationType.driver)),
              for (final itineraryId in roles.chiefOfItineraries)
                BusyListTile(
                  leading: const Icon(Icons.groups),
                  title: const Text('Jefe de itinerario'),
                  trailing: const Text('Quitar'),
                  onTap: () => _remove(w, ApplicationType.itineraryChiefLeave, itineraryId: itineraryId),
                ),
              if (!roles.isItineraryChief)
                BusyListTile(leading: const Icon(Icons.groups), title: const Text('Hacerlo Jefe de itinerario'), trailing: const Icon(Icons.add), onTap: () => _assign(w, ApplicationType.itineraryChief)),
              if (me.isAdmin)
                roles.isTransportChief
                    ? BusyListTile(leading: const Icon(Icons.directions_bus), title: const Text('Jefe de Transporte'), trailing: const Text('Quitar'), onTap: () => _remove(w, ApplicationType.transportChiefLeave))
                    : BusyListTile(
                        leading: const Icon(Icons.directions_bus),
                        title: const Text('Hacerlo Jefe de Transporte'),
                        trailing: const Icon(Icons.add),
                        onTap: () => _assignDirect(w, ApplicationType.transportChief),
                      ),
            ],
            if (me.isAdmin) ...[
              const SectionTitle('Administración'),
              BusyListTile(
                leading: Icon(w.active ? Icons.person_off_outlined : Icons.person_add_alt),
                title: Text(w.active ? 'Desactivar' : 'Activar'),
                onTap: () => _toggle(w),
              ),
            ],
          ]);
        },
      ),
    );
  }
}

/// Registrar a un trabajador sin teléfono (docs/08-version-2.md §8.3).
class RegisterWorkerScreen extends StatefulWidget {
  final List<String>? itineraryIds;

  const RegisterWorkerScreen({super.key, this.itineraryIds});

  @override
  State<RegisterWorkerScreen> createState() => _RegisterWorkerScreenState();
}

class _RegisterWorkerScreenState extends State<RegisterWorkerScreen> {
  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _firstSurname = TextEditingController();
  final _secondSurname = TextEditingController();
  late final _names = NamesFields(firstName: _firstName, middleName: _middleName, firstSurname: _firstSurname, secondSurname: _secondSurname);
  final _pass = TextEditingController();
  String? _sex;
  String? _rankId;
  String? _itineraryId;
  String? _stopId;
  List<Rank> _ranks = [];
  List<Itinerary> _itineraries = [];
  List<Stop> _stops = [];
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.api;
      final me = context.me;
      final entityFilter = context.entityFilter;
      final ranks = (await api.getAll('/ranks', query: {'sort': 'sortOrder,name'})).map(Rank.from).toList();
      final itineraries = (await api.getAll('/itineraries', query: {'sort': 'name', ...entityFilter}))
          .map(Itinerary.from)
          .where((i) => me.isChiefOf(i.id))
          .toList();
      if (!mounted) return;
      setState(() {
        _ranks = ranks;
        _itineraries = itineraries;
        if (itineraries.length == 1 && !me.managesTransport) _itineraryId = itineraries.first.id;
      });
      if (_itineraryId != null) await _loadStops(_itineraryId!);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _loadStops(String itineraryId) async {
    setState(() {
      _itineraryId = itineraryId;
      _stopId = null;
      _stops = [];
    });
    final links = await context.api.getAll('/itinerary-stops', query: {'filter[itinerary]': itineraryId, 'include': 'stop', 'sort': 'position'});
    if (mounted) setState(() => _stops = links.map((l) => ItineraryStop.from(l).stop!).toList());
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final entity = context.entityRelationship();
    if (entity == null) return;
    setState(() => _error = null);
    try {
      final document = await context.api.post('/workers', resourceData('workers', attributes: {
        ...Session.nameAttributes(_names.value),
        'pass': int.parse(_pass.text),
        'sex': _sex,
      }, relationships: {
        ...entity,
        'rank': ResourceId('ranks', _rankId!),
        if (_itineraryId != null) 'itinerary': ResourceId('itineraries', _itineraryId!),
        if (_itineraryId != null) 'stop': ResourceId('stops', _stopId!),
      }));
      if (!mounted) return;
      final worker = Worker.from(document.resource);
      await showActivationCode(context, worker, document.resource.meta['activationCode'] as String, document.resource.meta['activationExpiresAt'] as String?);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itineraryChiefOnly = !context.me.managesTransport;
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar trabajador')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Para quien no tiene teléfono. Se genera un código para que, cuando lo tenga, active su cuenta y elija su usuario y su contraseña.'),
          const SizedBox(height: 16),
          _names,
          PassField(controller: _pass),
          const SizedBox(height: 12),
          FormField<String>(
            validator: (_) => _sex == null ? 'Indica el sexo' : null,
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
            validator: (v) => v == null ? 'Elige la jerarquía' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _itineraryId,
            decoration: InputDecoration(labelText: itineraryChiefOnly ? 'Itinerario' : 'Itinerario (opcional)'),
            items: [for (final i in _itineraries) DropdownMenuItem(value: i.id, child: Text(i.name))],
            onChanged: (value) => value == null ? null : _loadStops(value),
            validator: (v) => itineraryChiefOnly && v == null ? 'Elige el itinerario' : null,
          ),
          if (_itineraryId != null) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _stopId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Parada'),
              items: [for (final s in _stops) DropdownMenuItem(value: s.id, child: Text('${s.landmark} · ${s.street}', overflow: TextOverflow.ellipsis))],
              onChanged: (value) => setState(() => _stopId = value),
              validator: (v) => v == null ? 'Elige la parada' : null,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(onPressed: _save, showErrors: false, child: const Text('Registrar')),
        ]),
      ),
    );
  }
}

/// Muestra el código de activación (también como QR) para entregarlo en mano.
Future<void> showActivationCode(BuildContext context, Worker worker, String code, String? expiresAt) {
  final expires = expiresAt == null ? null : DateTime.tryParse(expiresAt)?.toLocal();
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Código de activación'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Entrégaselo en mano a ${worker.name.short}. Solo se muestra ahora; si se pierde, genera otro.'),
          const SizedBox(height: 16),
          SelectableText(code, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 3)),
          const SizedBox(height: 8),
          SizedBox(width: 180, height: 180, child: QrImageView(data: code, backgroundColor: Colors.white)),
          const SizedBox(height: 8),
          Text([
            if (worker.entity != null) 'Entidad: ${worker.entity!.abbreviation}',
            if (worker.pass != null) 'Pase: ${worker.pass}',
            if (expires != null) 'Válido hasta el ${formatDateTime(expires)}',
          ].join('\n'), textAlign: TextAlign.center),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
    ),
  );
}
