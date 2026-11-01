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
import '../theme.dart';
import '../widgets/common.dart';
import 'stops_screen.dart';

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
        label: const Text('Registrar trabajador'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar', hintText: 'Nombre, usuario o Pase', isDense: true),
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
                  DropdownMenuItem(value: 'true', child: Text('Activados')),
                  DropdownMenuItem(value: 'false', child: Text('Desactivados')),
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
              ListTile(title: Text(plural(workers.length, 'trabajador', 'trabajadores'))),
              for (final w in workers)
                ListTile(
                  leading: WorkerAvatar(w),
                  title: Text(w.fullName, style: TextStyle(decoration: w.active ? null : TextDecoration.lineThrough)),
                  subtitle: Wrap(spacing: 8, children: [
                    if (w.pass != null) Text('Pase ${w.pass}'),
                    if (admin && w.entity != null) Text(w.entity!.abbreviation),
                    RankBadge(w.rank),
                    if (w.childrenCount > 0) Text(plural(w.childrenCount, 'niño', 'niños')),
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
  final _view = GlobalKey<AsyncViewState<Resource>>();

  Future<Resource> _load() async =>
      (await context.api.get('/workers/${widget.workerId}', query: {'include': 'rank,entity,itinerary,stop,user'})).resource;

  Future<void> _assign(Worker worker, String type) async {
    if (await showApplicationForm(context, type, worker: worker)) _view.currentState?.reload();
  }

  Future<void> _assignDirect(Worker worker, String type, String role) async {
    if (!await confirm(context, 'Asignar $role', '¿Asignar el $role a ${worker.name.short}? Recibirá un aviso.', accept: 'Asignar rol')) return;
    if (!mounted) return;
    await context.api.post('/applications', resourceData('applications', attributes: {'type': type}, relationships: {'worker': ResourceId('workers', worker.id)}));
    if (mounted) showMessage(context, 'Rol asignado');
    _view.currentState?.reload();
  }

  Future<void> _remove(Worker worker, String type, String what, {String? itineraryId}) async {
    if (!await confirm(context, 'Quitar $what', '¿Quitar $what a ${worker.name.short}? Recibirá un aviso.', accept: 'Quitar', destructive: true)) return;
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

  Future<void> _setActive(Worker worker, bool activate) async {
    if (activate == worker.active) return;
    if (!await confirm(context, activate ? 'Activar trabajador' : 'Desactivar trabajador', '¿${activate ? 'Activar' : 'Desactivar'} a ${worker.fullName}?',
        accept: activate ? 'Activar' : 'Desactivar', destructive: !activate)) {
      _view.currentState?.reload();
      return;
    }
    if (!mounted) return;
    await runAction(context, () => context.api.patch('/workers/${worker.id}', resourceData('workers', id: worker.id, attributes: {'active': activate})));
    _view.currentState?.reload();
  }

  /// Un dato en su propio control de solo lectura.
  Widget _data(String label, String? value, {Widget? prefix}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: InputDecorator(
          isEmpty: (value ?? '').isEmpty,
          decoration: InputDecoration(labelText: label, enabled: false, prefixIcon: prefix),
          child: (value ?? '').isEmpty ? null : Text(value!, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final me = context.me;
    return Scaffold(
      appBar: AppBar(title: const Text('Trabajador')),
      body: AsyncView<Resource>(
        key: _view,
        load: _load,
        builder: (context, resource, reload) {
          final w = Worker.from(resource);
          final username = resource.related('user')?.string('username');
          final itinerary = resource.related('itinerary')?.string('name');
          final stopResource = resource.related('stop');
          final stop = stopResource == null ? null : Stop.from(stopResource);
          final transportChief = me.isAdmin || me.roles.isTransportChief;
          final chiefOfHis = me.isChiefOf(w.itineraryId);
          final roles = w.roles;
          Widget roleTile(IconData icon, String role, {required bool has, Future<void> Function()? add, Future<void> Function()? remove}) => has
              ? ListTile(
                  leading: Icon(icon),
                  title: Text(role),
                  trailing: remove == null
                      ? null
                      : BusyIconButton(tooltip: 'Quitar $role', icon: const Icon(Icons.remove_circle_outline, color: overloadColor), onPressed: remove),
                )
              : BusyListTile(leading: Icon(icon), title: Text('Asignar $role'), trailing: const Icon(Icons.add), onTap: add);
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(padding: const EdgeInsets.all(16), child: Center(child: WorkerAvatar(w, radius: 40))),
            _data('Nombre', w.fullName),
            _data('Nombre de usuario', username ?? (w.activated ? null : 'Cuenta sin activar')),
            _data('Entidad', w.entity == null ? null : '${w.entity!.abbreviation} · ${w.entity!.name}'),
            _data('Pase', w.pass?.toString()),
            _data('Sexo', w.sex == 'F' ? 'Femenino' : 'Masculino'),
            _data('Jerarquía', w.rank?.name, prefix: const Icon(rankIcon)),
            if (w.childrenCount > 0) _data('Hijos con derecho a viajar', plural(w.childrenCount, 'niño', 'niños')),
            if (me.isAdmin)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: DropdownButtonFormField<bool>(
                  key: ValueKey('active-${w.active}'),
                  initialValue: w.active,
                  decoration: const InputDecoration(labelText: 'Estado'),
                  items: const [
                    DropdownMenuItem(value: true, child: Text('Activado')),
                    DropdownMenuItem(value: false, child: Text('Desactivado')),
                  ],
                  onChanged: (value) => _setActive(w, value!),
                ),
              ),
            if (!w.activated) ...[
              const SectionTitle('Cuenta sin activar'),
              BusyListTile(leading: const Icon(Icons.key_outlined), title: const Text('Generar código de activación'), onTap: () => _newCode(w)),
            ],
            const SectionTitle('Itinerario'),
            BusyListTile(
              leading: const Icon(Icons.route),
              title: Text(w.itineraryId == null ? 'Sin itinerario' : (itinerary ?? 'Itinerario')),
              subtitle: stop == null ? null : Text('${stop.landmark} · ${stopAddress(stop)}'),
              onTap: () => _assign(w, ApplicationType.itineraryMembership),
            ),
            if (w.itineraryId != null && (transportChief || chiefOfHis))
              BusyListTile(
                leading: const Icon(Icons.logout, color: overloadColor),
                title: const Text('Quitar del itinerario'),
                onTap: () => _remove(w, ApplicationType.itineraryLeave, 'el itinerario'),
              ),
            if (transportChief) ...[
              const SectionTitle('Roles'),
              roleTile(Icons.airline_seat_recline_normal, 'Rol de Chofer',
                  has: roles.isDriver,
                  add: () => _assignDirect(w, ApplicationType.driver, 'Rol de Chofer'),
                  remove: () => _remove(w, ApplicationType.driverLeave, 'el Rol de Chofer')),
              for (final itineraryId in roles.chiefOfItineraries)
                roleTile(Icons.groups, 'Rol de Jefe de itinerario',
                    has: true, remove: () => _remove(w, ApplicationType.itineraryChiefLeave, 'el Rol de Jefe de itinerario', itineraryId: itineraryId)),
              if (!roles.isItineraryChief)
                roleTile(Icons.groups, 'Rol de Jefe de itinerario', has: false, add: () => _assign(w, ApplicationType.itineraryChief)),
              if (me.isAdmin)
                roleTile(Icons.directions_bus, 'Rol de Jefe de Transporte',
                    has: roles.isTransportChief,
                    add: () => _assignDirect(w, ApplicationType.transportChief, 'Rol de Jefe de Transporte'),
                    remove: () => _remove(w, ApplicationType.transportChiefLeave, 'el Rol de Jefe de Transporte')),
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
  String _sex = 'M';
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
          _names,
          PassField(controller: _pass),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _sex,
            decoration: const InputDecoration(labelText: 'Sexo'),
            items: const [
              DropdownMenuItem(value: 'M', child: Text('Masculino')),
              DropdownMenuItem(value: 'F', child: Text('Femenino')),
            ],
            onChanged: (value) => setState(() => _sex = value!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _rankId,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(labelText: 'Jerarquía', prefixIcon: Icon(rankIcon)),
            items: [for (final rank in _ranks) DropdownMenuItem(value: rank.id, child: Text(rank.name))],
            onChanged: (value) => setState(() => _rankId = value),
            validator: (v) => v == null ? 'Elija la jerarquía.' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _itineraryId,
            decoration: InputDecoration(labelText: itineraryChiefOnly ? 'Itinerario' : 'Itinerario (opcional)'),
            items: [for (final i in _itineraries) DropdownMenuItem(value: i.id, child: Text(i.name))],
            onChanged: (value) => value == null ? null : _loadStops(value),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (v) => itineraryChiefOnly && v == null ? 'Elija el itinerario.' : null,
          ),
          if (_itineraryId != null) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _stopId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Parada'),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              items: [for (final s in _stops) DropdownMenuItem(value: s.id, child: Text('${s.landmark} · ${stopAddress(s)}', overflow: TextOverflow.ellipsis))],
              onChanged: (value) => setState(() => _stopId = value),
              validator: (v) => v == null ? 'Elija la parada.' : null,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(onPressed: _save, showErrors: false, icon: const Icon(Icons.person_add_alt), child: const Text('Registrar trabajador')),
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
          Text('Entrégueselo en mano a ${worker.name.short}. Solo se muestra ahora; si se pierde, genere otro.'),
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
      actions: [FilledButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.check), label: const Text('Listo'))],
    ),
  );
}
