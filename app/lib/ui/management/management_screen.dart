import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/session.dart';
import '../admin/nomenclators_screen.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/data_view.dart';
import 'forms.dart';
import 'include_by_qr_screen.dart';
import 'table_screens.dart';

/// Cantidades de las tarjetas (GET management-summary).
class _Summary {
  final int entities;
  final int itineraries;
  final int stops;
  final int workers;
  final int pendingEntity;
  final int pendingItinerary;
  final Map<String, int> nomenclators;

  const _Summary(this.entities, this.itineraries, this.stops, this.workers, this.pendingEntity, this.pendingItinerary, this.nomenclators);
}

/// Gestión (docs/11 §11.56 y §11.59, maquetas G19 n.º 1 y G20 n.º 1):
/// tarjetas de las tablas (Entidades, Itinerarios, Paradas, Trabajadores y,
/// para el Administrador, los nomencladores) con su cantidad y las
/// solicitudes pendientes. Tocar una tarjeta abre la pantalla de esa tabla.
class ManagementScreen extends StatefulWidget {
  const ManagementScreen({super.key});

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  final _view = GlobalKey<DataViewState<_Summary>>();

  Future<_Summary> _load() async {
    final a = (await context.read<Session>().api.get('/management-summary')).resource.attributes;
    int n(Object? v) => v is num ? v.toInt() : 0;
    return _Summary(n(a['entities']), n(a['itineraries']), n(a['stops']), n(a['workers']), n(a['pendingEntityApplications']), n(a['pendingItineraryApplications']),
        {for (final e in (a['nomenclators'] as Map? ?? const {}).entries) '${e.key}': n(e.value)});
  }

  Future<void> _open(Widget screen) async {
    await push(context, screen);
    if (mounted) _view.currentState?.reload();
  }

  List<ActionItem> _actions() {
    final me = context.read<Session>().me!;
    return [
      if (me.manages) ActionItem(Icons.qr_code_scanner, 'Incluir por QR', () => _open(const IncludeByQrScreen())),
      if (me.isAdmin) ActionItem(Icons.person_add_alt_1, 'Registrar trabajador', () => _open(const RegisterWorkerForm())),
      if (me.isAdmin) ActionItem(Icons.add_business_outlined, 'Crear Entidad', () => _open(const EntityForm())),
      if (me.isAdmin) ActionItem(Icons.add_road, 'Crear itinerario', () => _open(const ItineraryForm())),
      if (me.isAdmin || me.chiefItineraryId != null) ActionItem(Icons.add_location_alt_outlined, 'Crear parada', () => _open(StopForm(itineraryId: me.isAdmin ? null : me.chiefItineraryId))),
    ];
  }

  String _requests(int n) => n == 1 ? '1 solicitud' : '$n solicitudes';

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    return AppScaffold(
      title: 'Gestión',
      tab: MainTab.management,
      actions: _actions,
      body: DataView<_Summary>(
        key: _view,
        kinds: const {'applications'},
        cacheKey: 'gestion.resumen',
        load: _load,
        builder: (context, s, reload) => ListView(padding: const EdgeInsets.only(top: 4, bottom: 120), physics: const AlwaysScrollableScrollPhysics(), children: [
          const SectionTitle('Organización'),
          _Grid(children: [
            TableCard(icon: Icons.apartment, title: 'Entidades', line: [ '${s.entities}', if (s.pendingEntity > 0) _requests(s.pendingEntity)].join(' • '),
                badge: s.pendingEntity, onTap: () => _open(const EntitiesScreen())),
            TableCard(icon: Icons.route, title: 'Itinerarios', line: ['${s.itineraries}', if (s.pendingItinerary > 0) _requests(s.pendingItinerary)].join(' • '),
                badge: s.pendingItinerary, onTap: () => _open(const ItinerariesScreen())),
            TableCard(icon: Icons.place, title: 'Paradas', line: '${s.stops}', onTap: () => _open(const StopsScreen())),
            TableCard(icon: Icons.groups_outlined, title: 'Trabajadores', line: '${s.workers}', onTap: () => _open(const WorkersScreen())),
          ]),
          if (me.isAdmin) ...[
            const SectionTitle('Nomencladores'),
            _Grid(children: [
              for (final n in Nomenclator.all)
                TableCard(icon: nomenclatorIcon(n.type), title: n.title, line: '${s.nomenclators[n.type] ?? 0}', onTap: () => _open(NomenclatorsScreen(only: n))),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  final List<Widget> children;

  const _Grid({required this.children});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.15,
          children: children,
        ),
      );
}

/// Tarjeta de una tabla en Gestión: ícono, nombre, cantidad y el número de
/// solicitudes pendientes.
class TableCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String line;
  final int badge;
  final VoidCallback onTap;

  const TableCard({super.key, required this.icon, required this.title, required this.line, this.badge = 0, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(4),
      shape: RoundedRectangleBorder(side: BorderSide(color: t.colorScheme.outline), borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CardImage(icon: icon, size: 44),
              const Spacer(),
              if (badge > 0) Badge(label: Text('$badge'), largeSize: 24, textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
            const Spacer(),
            Text(title, style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(line, style: t.textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}
