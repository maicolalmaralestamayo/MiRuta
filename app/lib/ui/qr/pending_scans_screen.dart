import 'package:flutter/material.dart';

import '../../services/qr/qr_store.dart';
import '../../services/templates.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/selection.dart';

Future<void> openPendingScans(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PendingScansScreen()));

/// Escaneos hechos sin conexión: los pendientes de enviar y el resultado de
/// cada uno al enviarlos con POST /offline-scans.
class PendingScansScreen extends StatefulWidget {
  const PendingScansScreen({super.key});

  @override
  State<PendingScansScreen> createState() => _PendingScansScreenState();
}

class _PendingScansScreenState extends State<PendingScansScreen> {
  final _selection = SelectionController();
  List<QueuedScan> _items = const [];

  @override
  void initState() {
    super.initState();
    _selection.addListener(_changed);
    _load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _selection.removeListener(_changed);
    _selection.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await QrStore.queue();
    if (!mounted) return;
    _selection.retain(items.map((i) => i.lid));
    setState(() => _items = items.reversed.toList());
  }

  Future<void> _send() async {
    final results = await QrStore.flush(context.api);
    await _load();
    if (!mounted) return;
    final accepted = results.where((r) => r.status == 'accepted' || r.status == 'repeated').length;
    showMessage(context, results.isEmpty ? 'No había nada pendiente.' : '$accepted de ${results.length} registrados. Revise el resultado de cada uno.');
  }

  Future<void> _retryOutsider() async {
    final item = _selection.selectedOf(_items, (i) => i.lid).first;
    await QrStore.retry(item.lid, allowOutsider: true);
    _selection.clear();
    if (mounted) await runAction(context, _send);
  }

  Future<void> _remove() async {
    for (final item in _selection.selectedOf(_items, (i) => i.lid)) {
      await QrStore.remove(item.lid);
    }
    _selection.clear();
    await _load();
  }

  static String statusText(QueuedScan item) => switch (item.status) {
        'pending' => 'Pendiente de enviar',
        'accepted' => 'Registrado',
        'repeated' => 'Ya estaba registrado',
        'discarded' => 'Descartado${item.detail != null ? ': ${item.detail}' : ''}',
        _ => 'Rechazado${item.detail != null ? ': ${item.detail}' : ''}',
      };

  static Color statusColor(QueuedScan item) => switch (item.status) {
        'pending' => Colors.blueGrey,
        'accepted' || 'repeated' => const Color(0xFF2E7D32),
        'discarded' => Colors.orange,
        _ => Colors.red,
      };

  @override
  Widget build(BuildContext context) {
    final selected = _selection.selectedOf(_items, (i) => i.lid);
    final outsider = selected.length == 1 && selected.first.code == 'OUTSIDER_CONFIRMATION_REQUIRED';
    return AppScaffold(
      title: 'Escaneos sin conexión',
      tab: MainTab.trips,
      selection: _selection,
      actions: [
        ActionItem(icon: Icons.cloud_upload_outlined, label: 'Enviar ahora', onPressed: _send),
        ActionItem(
            icon: Icons.cleaning_services_outlined,
            label: 'Quitar los enviados',
            onPressed: () async {
              await QrStore.clearSent();
              await _load();
            }),
        const ActionItem.divider(),
        ActionItem(icon: Icons.alt_route, label: 'Dejar subir y reenviar', needs: ActionNeeds.one, enabled: outsider, onPressed: _retryOutsider),
        ActionItem(
            icon: Icons.delete_outline,
            label: 'Eliminar',
            needs: ActionNeeds.some,
            destructive: true,
            confirmation: '¿Eliminar del teléfono los escaneos seleccionados? Los pendientes no se enviarán.',
            onPressed: _remove),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: SelectableCardList<QueuedScan>(
            controller: _selection,
            emptyText: 'No hay escaneos guardados sin conexión.',
            sections: [
              CardSection(title: 'Pendientes de enviar', items: _items.where((i) => i.pending).toList()),
              CardSection(title: 'Enviados', items: _items.where((i) => !i.pending).toList()),
            ],
            keyOf: (i) => i.lid,
            cardBuilder: (context, item, selected, onTap, onLongPress) => InfoCard(
              images: [CardImage(icon: item.purpose == 'boarding' ? Icons.directions_bus : Icons.alt_route, round: true, size: 44)],
              title: item.label,
              chip: CardChip(item.pending ? 'Pendiente' : (item.status == 'accepted' || item.status == 'repeated' ? 'Hecho' : 'Revisar'), color: statusColor(item)),
              lines: [
                '${item.purpose == 'boarding' ? 'Subida' : 'Alta en itinerario'} · ${formatDateTime(item.scannedAt)}'
                    '${item.childIds.isNotEmpty ? ' · ${plural(item.childIds.length, 'niño', 'niños')}' : ''}',
                statusText(item),
              ],
              selected: selected,
              onTap: onTap,
              onLongPress: onLongPress,
            ),
        ),
      ),
    );
  }
}
