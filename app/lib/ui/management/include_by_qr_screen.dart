import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api_exception.dart';
import '../../core/storage.dart';
import '../../services/qr/qr_codes.dart';
import '../../services/qr/qr_queue.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

/// Lee un código QR con la cámara y lo devuelve (null si se vuelve atrás).
Future<String?> scanQrCode(BuildContext context, {String hint = 'Apunte al QR que muestra la persona en «Mi QR».'}) =>
    push<String>(context, QrScannerScreen(hint: hint));

class QrScannerScreen extends StatefulWidget {
  final String hint;

  const QrScannerScreen({super.key, required this.hint});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Escanear QR',
      tab: MainTab.management,
      actions: () => [ActionItem(Icons.flashlight_on_outlined, 'Linterna', () => _controller.toggleTorch())],
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
            if (value != null && !_done) {
              _done = true;
              Navigator.pop(context, value);
            }
          },
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 16,
          child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(widget.hint, textAlign: TextAlign.center))),
        ),
      ]),
    );
  }
}

enum _Where { entity, itinerary, stop }

/// Opción de un selector (id y nombre), también guardada para usarla sin conexión.
class _Option {
  final String id;
  final String name;
  final String? parentId;

  const _Option(this.id, this.name, [this.parentId]);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'parentId': parentId};

  factory _Option.fromJson(Map<String, dynamic> j) => _Option('${j['id']}', '${j['name']}', j['parentId'] as String?);
}

/// «Incluir por QR» (docs/11 §11.27, maqueta G18 n.º 7): tras escanear el QR
/// de la persona se elige dónde incluirla (Entidad, itinerario o parada); el
/// formulario indica dónde está ya. Funciona con y sin conexión.
class IncludeByQrScreen extends StatefulWidget {
  const IncludeByQrScreen({super.key});

  @override
  State<IncludeByQrScreen> createState() => _IncludeByQrScreenState();
}

class _IncludeByQrScreenState extends State<IncludeByQrScreen> {
  static const _optionsKey = 'user.qr.options';

  String? _qr;
  QrCheck? _check;
  bool _offline = false;
  String _name = '';
  String? _photo;
  List<Map<String, dynamic>> _places = const [];
  _Where _where = _Where.itinerary;
  List<_Option> _entities = const [];
  List<_Option> _itineraries = const [];
  Map<String, List<_Option>> _stops = const {};
  _Option? _entity;
  _Option? _itinerary;
  _Option? _stop;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    _loadOptions();
  }

  Future<void> _scan() async {
    final qr = await scanQrCode(context);
    if (!mounted) return;
    if (qr == null) {
      if (_qr == null) Navigator.pop(context);
      return;
    }
    setState(() {
      _qr = qr;
      _error = null;
      _name = '';
      _places = const [];
    });
    try {
      final r = (await context.api.post('/qr-scans', {
        'data': {'type': 'qr-scans', 'attributes': {'qr': qr, 'scannedAt': DateTime.now().toIso8601String()}},
      })).resource;
      setState(() {
        _offline = false;
        _name = r.string('fullName') ?? '';
        _photo = r.string('photoUrl');
        _places = [for (final m in (r.attributes['memberships'] as List? ?? const [])) Map<String, dynamic>.from(m as Map)];
      });
    } on ApiException catch (error) {
      if (!error.isNetwork) {
        setState(() => _error = error.message);
        return;
      }
      // Sin conexión: se comprueba en el teléfono y se envía después.
      try {
        final check = await QrQueue.verify(qr);
        setState(() {
          _offline = true;
          _check = check;
          _name = 'Persona n.º ${check.userId}';
        });
      } on QrException catch (e) {
        setState(() => _error = e.message);
      }
    }
  }

  /// Entidades, itinerarios y paradas posibles (el Jefe, solo su itinerario).
  Future<void> _loadOptions() async {
    final me = context.me;
    try {
      final api = context.api;
      final entities = me.isAdmin
          ? (await api.getAll('/entities')).map((r) => _Option(r.id, r.string('abbreviation') ?? '')).toList()
          : [for (final m in me.memberships.where((m) => m.itineraryId == me.chiefItineraryId)) _Option(m.entityId, m.entityAbbreviation)];
      final itineraries = me.isAdmin
          ? (await api.getAll('/itineraries')).map((r) => _Option(r.id, r.string('name') ?? '', r.relId('entity')?.id)).toList()
          : [for (final m in me.memberships.where((m) => m.itineraryId == me.chiefItineraryId)) _Option(m.itineraryId!, m.itineraryName ?? '', m.entityId)];
      final stops = <String, List<_Option>>{};
      for (final i in me.isAdmin ? const <_Option>[] : itineraries) {
        stops[i.id] = (await api.getAll('/stops', query: {'filter[itinerary]': i.id, 'sort': 'position'})).map((r) => _Option(r.id, r.string('landmark') ?? '')).toList();
      }
      await Storage.setJson(_optionsKey, {
        'entities': [for (final o in entities) o.toJson()],
        'itineraries': [for (final o in itineraries) o.toJson()],
        'stops': {for (final e in stops.entries) e.key: [for (final o in e.value) o.toJson()]},
      });
      _apply(entities, itineraries, stops);
    } catch (_) {
      final saved = await Storage.getJson(_optionsKey);
      List<_Option> list(Object? raw) => [for (final o in (raw as List? ?? const [])) _Option.fromJson(Map<String, dynamic>.from(o as Map))];
      _apply(list(saved['entities']), list(saved['itineraries']), {for (final e in (saved['stops'] as Map? ?? const {}).entries) '${e.key}': list(e.value)});
    }
  }

  void _apply(List<_Option> entities, List<_Option> itineraries, Map<String, List<_Option>> stops) {
    if (!mounted) return;
    final me = context.me;
    setState(() {
      _entities = entities;
      _itineraries = itineraries;
      _stops = stops;
      if (!me.isAdmin) {
        _itinerary = itineraries.firstOrNull;
        _entity = entities.firstOrNull;
      }
    });
  }

  Future<List<_Option>> _stopsOf(String itineraryId) async {
    if (_stops.containsKey(itineraryId)) return _stops[itineraryId]!;
    final list = (await context.api.getAll('/stops', query: {'filter[itinerary]': itineraryId, 'sort': 'position'})).map((r) => _Option(r.id, r.string('landmark') ?? '')).toList();
    _stops = {..._stops, itineraryId: list};
    return list;
  }

  Future<void> _pickEntity() async {
    final e = await pickOne<_Option>(context, 'Entidad', _entities, (o) => o.name);
    if (e != null) {
      setState(() {
        _entity = e;
        _itinerary = null;
        _stop = null;
      });
    }
  }

  Future<void> _pickItinerary({bool optional = false}) async {
    const none = _Option('', 'Sin itinerario');
    final options = _itineraries.where((i) => _where != _Where.entity || i.parentId == _entity?.id).toList();
    final i = await pickOne<_Option>(context, 'Itinerario', [if (optional) none, ...options], (o) => o.name);
    if (i != null) {
      setState(() {
        _itinerary = i.id.isEmpty ? null : i;
        _stop = null;
      });
    }
  }

  Future<void> _pickStop({bool optional = true}) async {
    final itinerary = _itinerary;
    if (itinerary == null) {
      showMessage(context, 'Elija primero el itinerario.');
      return;
    }
    try {
      final stops = await _stopsOf(itinerary.id);
      if (!mounted) return;
      const none = _Option('', 'Sin parada');
      final s = await pickOne<_Option>(context, 'Parada', [if (optional) none, ...stops], (o) => o.name);
      if (s != null) setState(() => _stop = s.id.isEmpty ? null : s);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _include() async {
    final qr = _qr;
    if (qr == null) return;
    String? entityId;
    String? itineraryId;
    String? stopId;
    switch (_where) {
      case _Where.entity:
        if (_entity == null) throw StateError('Elija la Entidad.');
        entityId = _entity!.id;
        itineraryId = _itinerary?.id;
        stopId = _stop?.id;
      case _Where.itinerary:
        if (_itinerary == null) throw StateError('Elija el itinerario.');
        itineraryId = _itinerary!.id;
        stopId = _stop?.id;
      case _Where.stop:
        if (_stop == null) throw StateError('Elija la parada.');
        stopId = _stop!.id;
        itineraryId = _itinerary?.id;
    }
    final label = [_name, _itinerary?.name ?? _entity?.name, _stop?.name].whereType<String>().join(' • ');
    if (_offline) {
      await QrQueue.enqueue(qr: qr, check: _check!, label: label, entityId: entityId, itineraryId: itineraryId, stopId: stopId);
      if (mounted) showMessage(context, 'Sin conexión: la inclusión se enviará al volver la conexión. Hasta entonces la persona no la verá.');
    } else {
      final r = (await context.api.post('/qr-inclusions', QrQueue.body(qr: qr, scannedAt: DateTime.now(), entityId: entityId, itineraryId: itineraryId, stopId: stopId))).resource;
      if (mounted) showMessage(context, '${r.string('fullName') ?? _name} quedó incluido.');
    }
    if (mounted) Navigator.pop(context, true);
  }

  String _placeText(Map<String, dynamic> m) {
    final entity = (m['entity'] as Map?)?['abbreviation'] ?? '';
    final itinerary = (m['itinerary'] as Map?)?['name'];
    final stop = (m['stop'] as Map?)?['landmark'];
    return [entity, itinerary ?? 'Sin itinerario', if (itinerary != null) stop ?? 'Sin parada', if (m['isChief'] == true) 'Jefe'].join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final me = context.me;
    return AppScaffold.list(
      title: 'Incluir por QR',
      tab: MainTab.management,
      actions: () => [
        if (_qr != null && _error == null) ActionItem(Icons.how_to_reg, 'Incluir', _include),
        ActionItem(Icons.qr_code_scanner, 'Escanear otro QR', _scan),
      ],
      children: [
        const SizedBox(height: 8),
        if (_error != null) NoticeCard(icon: Icons.error_outline, title: 'QR no válido', detail: _error!, color: red, buttonIcon: Icons.qr_code_scanner, buttonText: 'Escanear otra vez', onPressed: _scan),
        if (_qr == null && _error == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        if (_name.isNotEmpty) ...[
          InfoCard(images: [CardImage(url: _photo, icon: Icons.person, round: true)], title: _name, lines: [if (_offline) 'Sin conexión: comprobado en el teléfono']),
          if (!_offline) ...[
            const SectionTitle('Ya está en'),
            if (_places.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Sin Entidad')),
            for (final m in _places) InfoCard(images: const [CardImage(icon: Icons.apartment)], title: '${(m['entity'] as Map?)?['abbreviation'] ?? ''}', lines: [_placeText(m)]),
          ],
          const SectionTitle('Incluir en'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<_Where>(
              showSelectedIcon: false,
              segments: [
                if (me.isAdmin) const ButtonSegment(value: _Where.entity, label: Text('Entidad'), icon: Icon(Icons.apartment)),
                const ButtonSegment(value: _Where.itinerary, label: Text('Itinerario'), icon: Icon(Icons.route)),
                const ButtonSegment(value: _Where.stop, label: Text('Parada'), icon: Icon(Icons.place)),
              ],
              selected: {_where},
              onSelectionChanged: (s) => setState(() {
                _where = s.first;
                _stop = null;
                if (me.isAdmin) {
                  _itinerary = null;
                  _entity = null;
                }
              }),
            ),
          ),
          if (_where == _Where.entity)
            SelectorCard(icon: Icons.apartment, title: _entity?.name ?? 'Elija la Entidad', lines: const ['Entidad'], onTap: _pickEntity),
          if (_where != _Where.entity || _entity != null)
            SelectorCard(
              icon: Icons.route,
              title: _itinerary?.name ?? (_where == _Where.entity ? 'Sin itinerario' : 'Elija el itinerario'),
              lines: [_where == _Where.entity ? 'Itinerario (opcional)' : (_where == _Where.stop ? 'Itinerario de la parada' : 'Itinerario')],
              enabled: me.isAdmin,
              onTap: () => _pickItinerary(optional: _where == _Where.entity),
            ),
          if (_itinerary != null)
            SelectorCard(
              icon: Icons.place,
              title: _stop?.name ?? (_where == _Where.stop ? 'Elija la parada' : 'Sin parada'),
              lines: [_where == _Where.stop ? 'Parada' : 'Parada (opcional)'],
              onTap: () => _pickStop(optional: _where != _Where.stop),
            ),
        ],
      ],
    );
  }
}
