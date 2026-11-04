import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api/absences_api.dart';
import '../../services/api/memberships_api.dart';
import '../../services/session.dart';
import '../../services/templates.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/entity_selector.dart';
import '../widgets/selection.dart';
import 'worker_common.dart';

/// Itinerario y parada (docs/11 §11.5, §11.12 y §11.18; maqueta
/// pantallas-final.png, 5). Con selector de Entidad: «Mi itinerario y
/// parada» (o «Sin itinerario», y las solicitudes pendientes) y «Ausencias».
///
/// Acciones: Solicitar itinerario y parada (siempre juntos), Declarar
/// ausencia (tipo y fechas, o indefinida; sin aprobación), Editar (una
/// ausencia), Darme de baja (del itinerario), Cancelar solicitud y Eliminar
/// (ausencias).
class ItineraryStopScreen extends StatefulWidget {
  const ItineraryStopScreen({super.key});

  @override
  State<ItineraryStopScreen> createState() => _ItineraryStopScreenState();
}

const _noItinerary = 'none';

typedef _Data = ({List<Application> applications, List<Absence> absences});

class _ItineraryStopScreenState extends State<ItineraryStopScreen> {
  static const _itinerary = 'itinerary:';
  static const _application = 'application:';
  static const _absence = 'absence:';

  final _selection = SelectionController();
  /// Una vista por pertenencia e itinerario: al cambiar de Entidad se carga de nuevo.
  final _views = <String, GlobalKey<AsyncViewState<_Data>>>{};
  String _viewKey = '';
  List<Absence> _absences = const [];

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<_Data> _load(Membership? membership) async {
    if (membership == null) return (applications: const <Application>[], absences: const <Absence>[]);
    final applications = MembershipsApi(context.api).myApplications(type: ApplicationType.itineraryMembership, entityId: membership.entityId);
    final absences = AbsencesApi(context.api).mine(workerId: membership.workerId);
    final data = (applications: await applications, absences: await absences);
    _absences = data.absences;
    return data;
  }

  /// Acciones abiertas al tocar una tarjeta: el error se muestra.
  Future<void> _guard(Future<void> action) async {
    try {
      await action;
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _reload() async {
    _selection.clear();
    await _views[_viewKey]?.currentState?.reload();
  }

  Future<void> _requestItinerary(Membership membership) async {
    final api = MembershipsApi(context.api);
    final itineraries = await api.itineraries(membership.entityId);
    if (!mounted) return;
    if (itineraries.isEmpty) {
      showMessage(context, '${membership.entity.abbreviation} todavía no tiene itinerarios.');
      return;
    }
    final itinerary = await pickFrom<Itinerary>(context, 'Elija el itinerario', itineraries, (i) => i.name);
    if (itinerary == null || !mounted) return;
    final stops = await api.stopsOf(itinerary.id);
    if (!mounted) return;
    final stop = await pickFrom<Stop>(context, 'Elija su parada en ${itinerary.name}', stops, (s) => s.landmark, subtitle: (s) => s.address);
    if (stop == null || !mounted) return;
    final ok = await confirm(
      context,
      'Solicitar itinerario y parada',
      '¿Solicitar ${itinerary.name}, parada ${stop.landmark}?${membership.hasItinerary ? ' Al aprobarse, dejará ${membership.itinerary!.name}.' : ''}',
      accept: 'Solicitar',
    );
    if (!ok || !mounted) return;
    await api.requestItinerary(itineraryId: itinerary.id, stopId: stop.id);
    if (!mounted) return;
    showMessage(context, 'Solicitud enviada. Le avisaremos cuando la resuelvan.');
    await _reload();
  }

  Future<void> _editAbsence(Membership membership, [Absence? absence]) async {
    final types = await AbsencesApi(context.api).types();
    if (!mounted) return;
    final saved = await showDialog<bool>(context: context, builder: (_) => AbsenceDialog(workerId: membership.workerId, types: types, absence: absence, api: AbsencesApi(context.api)));
    if (saved == true && mounted) {
      showMessage(context, absence == null ? 'Ausencia declarada' : 'Ausencia guardada');
      await _reload();
    }
  }

  Future<void> _leaveItinerary(Membership membership) async {
    final session = context.session;
    await MembershipsApi(session.api).leaveItinerary(membership.workerId);
    await session.reloadMe();
    if (!mounted) return;
    showMessage(context, 'Se dio de baja de ${membership.itinerary?.name ?? 'su itinerario'}.');
    await _reload();
  }

  Future<void> _cancel() async {
    final api = MembershipsApi(context.api);
    for (final id in SelectionKeys.ids(_selection, _application)) {
      await api.cancelApplication(id);
    }
    if (!mounted) return;
    showMessage(context, 'Solicitud cancelada');
    await _reload();
  }

  Future<void> _deleteAbsences() async {
    final api = AbsencesApi(context.api);
    for (final id in SelectionKeys.ids(_selection, _absence)) {
      await api.delete(id);
    }
    if (!mounted) return;
    showMessage(context, 'Ausencias eliminadas');
    await _reload();
  }

  Absence? get _selectedAbsence {
    final ids = SelectionKeys.ids(_selection, _absence);
    if (ids.length != 1 || _selection.count != 1) return null;
    for (final a in _absences) {
      if (a.id == ids.first) return a;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final membership = context.watch<Session>().selectedMembership;
    final hasEntity = membership != null;
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) => AppScaffold(
        title: 'Itinerario y parada',
        selection: _selection,
        actions: [
          ActionItem(icon: Icons.swap_horiz, label: 'Solicitar itinerario y parada', enabled: hasEntity, onPressed: () => _requestItinerary(membership!)),
          ActionItem(icon: Icons.event_busy, label: 'Declarar ausencia', enabled: hasEntity, onPressed: () => _editAbsence(membership!)),
          const ActionItem.divider(),
          ActionItem(
            icon: Icons.edit_outlined,
            label: 'Editar',
            needs: ActionNeeds.one,
            enabled: _selectedAbsence != null,
            onPressed: () => _editAbsence(membership!, _selectedAbsence),
          ),
          ActionItem(
            icon: Icons.logout,
            label: 'Darme de baja',
            needs: ActionNeeds.one,
            enabled: SelectionKeys.allAre(_selection, _itinerary),
            confirmation: 'Dejará su itinerario y su parada en ${membership?.entity.abbreviation ?? ''}. Para volver tendrá que solicitarlo de nuevo. ¿Darse de baja?',
            onPressed: () => _leaveItinerary(membership!),
          ),
          ActionItem(
            icon: Icons.cancel_outlined,
            label: 'Cancelar solicitud',
            needs: ActionNeeds.some,
            enabled: SelectionKeys.allAre(_selection, _application),
            confirmation: '¿Cancelar las solicitudes seleccionadas?',
            onPressed: _cancel,
          ),
          ActionItem(
            icon: Icons.delete_outline,
            label: 'Eliminar',
            needs: ActionNeeds.some,
            destructive: true,
            enabled: SelectionKeys.allAre(_selection, _absence),
            confirmation: '¿Eliminar las ausencias seleccionadas?',
            onPressed: _deleteAbsences,
          ),
        ],
        body: AsyncView<_Data>(
          key: _views.putIfAbsent(_viewKey = '${membership?.workerId}-${membership?.itineraryId}', GlobalKey.new),
          load: () => _load(membership),
          builder: (context, data, reload) {
            final header = [EntitySelector(onChanged: (_) => _selection.clear())];
            if (membership == null) {
              return ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), children: [
                ...header,
                const Padding(padding: EdgeInsets.all(24), child: Text('Cuando le aprueben la entrada en una Entidad podrá solicitar su itinerario y su parada.', textAlign: TextAlign.center)),
                const DeveloperChatFooter(),
              ]);
            }
            // «Sin itinerario» (no se selecciona; al tocarla, se solicita).
            final mine = <Object>[membership.hasItinerary ? membership : _noItinerary, ...data.applications];
            String keyOf(Object item) => switch (item) {
                  Membership m => '$_itinerary${m.workerId}',
                  Application a => '$_application${a.id}',
                  Absence a => '$_absence${a.id}',
                  _ => 'none',
                };
            return ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
              SelectableCardList<Object>(
                controller: _selection,
                scrollable: false,
                header: header,
                sections: [
                  CardSection(title: 'Mi itinerario y parada', items: mine, hideIfEmpty: false),
                  CardSection(title: 'Ausencias', items: data.absences, hideIfEmpty: false, emptyText: 'No tiene ausencias declaradas.'),
                ],
                keyOf: keyOf,
                onOpen: (item) {
                  if (item is Membership || item == _noItinerary) _guard(_requestItinerary(membership));
                  if (item is Absence) _guard(_editAbsence(membership, item));
                },
                canSelect: (item) => item != _noItinerary,
                cardBuilder: (context, item, selected, onTap, onLongPress) => switch (item) {
                  Membership m => ItineraryStopCard.membership(m, selected: selected, onTap: onTap, onLongPress: onLongPress),
                  Application a => ItineraryStopCard(
                      itineraryName: a.itineraryName ?? '',
                      landmark: a.stopLandmark,
                      chip: pendingChip(),
                      extraLine: requestedOn(a),
                      selected: selected,
                      onTap: onTap,
                      onLongPress: onLongPress,
                    ),
                  Absence a => AbsenceCard(a, selected: selected, onTap: onTap, onLongPress: onLongPress),
                  _ => ItineraryStopCard.membership(null, onTap: onTap),
                },
              ),
              const DeveloperChatFooter(),
            ]);
          },
        ),
      ),
    );
  }
}

/// Tarjeta de una ausencia: el tipo y «lun. 16/11/26 al vie. 27/11/26» o
/// «Desde jue. 05/11/26 • Indefinida».
class AbsenceCard extends StatelessWidget {
  final Absence absence;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AbsenceCard(this.absence, {super.key, this.selected = false, this.onTap, this.onLongPress});

  static String period(Absence a) =>
      a.end == null ? 'Desde ${formatDate(a.start)} • Indefinida' : (a.endsOn == a.startsOn ? formatDate(a.start) : '${formatDate(a.start)} al ${formatDate(a.end!)}');

  @override
  Widget build(BuildContext context) => InfoCard(
        images: const [CardImage(icon: Icons.event_busy)],
        title: absence.absenceTypeName ?? 'Ausencia',
        lines: [period(absence), if ((absence.note ?? '').isNotEmpty) absence.note!],
        selected: selected,
        onTap: onTap,
        onLongPress: onLongPress,
      );
}

/// Declarar o editar una ausencia: tipo, desde, hasta o indefinida, y nota.
/// Devuelve true si se guardó.
class AbsenceDialog extends StatefulWidget {
  final String workerId;
  final List<Named> types;
  final Absence? absence;
  final AbsencesApi api;

  const AbsenceDialog({super.key, required this.workerId, required this.types, required this.api, this.absence});

  @override
  State<AbsenceDialog> createState() => _AbsenceDialogState();
}

class _AbsenceDialogState extends State<AbsenceDialog> {
  late String? _typeId = widget.absence?.absenceTypeId ?? (widget.types.length == 1 ? widget.types.first.id : null);
  late DateTime _start = widget.absence?.start ?? DateTime.now();
  late DateTime? _end = widget.absence?.end;
  late bool _indefinite = widget.absence != null && widget.absence!.end == null;
  late final _note = TextEditingController(text: widget.absence?.note ?? '');
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_typeId == null) return setState(() => _error = 'Elija el tipo de ausencia.');
    if (!_indefinite && _end == null) return setState(() => _error = 'Elija hasta cuándo, o márquela como indefinida.');
    if (!_indefinite && _end!.isBefore(_start)) return setState(() => _error = 'La fecha de fin no puede ser anterior a la de inicio.');
    setState(() {
      _error = null;
      _saving = true;
    });
    final end = _indefinite ? null : _end;
    try {
      if (widget.absence == null) {
        await widget.api.create(workerId: widget.workerId, absenceTypeId: _typeId!, startsOn: _start, endsOn: end, note: _note.text);
      } else {
        await widget.api.update(widget.absence!.id, absenceTypeId: _typeId!, startsOn: _start, endsOn: end, note: _note.text);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.absence == null ? 'Declarar ausencia' : 'Ausencia'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Se declara para no perder el derecho a viajar: durante la ausencia no cuenta como pasajero esperado.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _typeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: [for (final t in widget.types) DropdownMenuItem(value: t.id, child: Text(t.name))],
            onChanged: (value) => setState(() => _typeId = value),
          ),
          const SizedBox(height: 12),
          DateField(label: 'Desde', value: _start, firstDate: DateTime(2020), onChanged: (d) => setState(() => _start = d)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Indefinida'),
            value: _indefinite,
            onChanged: (v) => setState(() => _indefinite = v),
          ),
          if (!_indefinite) DateField(label: 'Hasta', value: _end, firstDate: _start, onChanged: (d) => setState(() => _end = d)),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Nota (opcional)'), maxLines: 2),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(widget.absence == null ? 'Declarar' : 'Guardar')),
      ],
    );
  }
}
