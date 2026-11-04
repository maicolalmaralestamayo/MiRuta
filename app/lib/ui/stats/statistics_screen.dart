import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../navigation.dart';
import '../admin/management.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import 'statistic.dart';

/// Estadísticas con gráfico y tabla, periodo relativo ("Últimos") o por
/// rango de fechas (un día = rango con inicio y fin iguales). Solo se ven en la app (no se exportan). Cada rol ve las suyas.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

const _titles = {
  'trips-by-status': 'Viajes por estado',
  'punctuality': 'Puntualidad',
  'duration': 'Duración de los trayectos',
  'trips-by-driver': 'Viajes por chofer',
  'trips-by-vehicle': 'Viajes por vehículo',
  'overloaded-trips': 'Viajes saturados y sobresaturados',
  'occupancy': 'Ocupación',
  'attendance': 'Asistencia por parada',
  'children-transported': 'Niños transportados',
  'outsider-travellers': 'Viajan fuera de su itinerario o Entidad',
  'workers-distribution': 'Distribución de trabajadores',
  'worker-trips': 'Mis viajes',
  'applications-summary': 'Solicitudes',
  'stop-activity': 'Subidas y bajadas por parada',
  'stop-pass-times': 'Hora de paso por las paradas',
  'distance': 'Distancia recorrida',
  'trip-incidents': 'Incidencias del recorrido',
};

const _groupings = {
  'punctuality': {'itinerary': 'Itinerario', 'vehicle': 'Vehículo', 'driver': 'Chofer'},
  'occupancy': {'itinerary': 'Itinerario', 'vehicle': 'Vehículo'},
  'workers-distribution': {'itinerary': 'Itinerario', 'stop': 'Parada', 'sex': 'Sexo'},
};

enum _PeriodMode { relative, range }

class _StatisticsScreenState extends State<StatisticsScreen> with ManagementEntityState {
  String _name = 'worker-trips';
  _PeriodMode _mode = _PeriodMode.relative;
  int _amount = 30;
  String _unit = 'd';
  DateTimeRange? _range;
  String? _by;
  String? _itineraryId;
  List<Itinerary> _itineraries = [];
  Statistic? _result;
  String? _error;
  bool _loading = false;

  List<String> get _available {
    final me = context.me;
    if (me.canAnywhere(Op.statisticsView)) return _titles.keys.toList();
    if (me.canAnywhere(Op.trackingDrive)) {
      return const ['trips-by-status', 'punctuality', 'duration', 'overloaded-trips', 'occupancy', 'attendance', 'children-transported', 'outsider-travellers', 'stop-activity', 'stop-pass-times', 'distance', 'trip-incidents', 'worker-trips'];
    }
    return const ['worker-trips'];
  }

  /// Con statistics.view se elige la Entidad (y, dentro, el itinerario).
  bool get _scoped => context.me.canAnywhere(Op.statisticsView);

  @override
  String get entityOperation => Op.statisticsView;

  @override
  void onEntityChanged() {
    _itineraryId = null;
    _loadItineraries();
    _load();
  }

  void _loadItineraries() {
    final e = entity;
    if (e == null) return;
    final me = context.me;
    context.api.getAll('/itineraries', query: {'sort': 'name', 'filter[entity]': e.id}).then((r) {
      if (mounted) setState(() => _itineraries = r.map(Itinerary.from).where((i) => me.can(Op.statisticsView, entityId: e.id, itineraryId: i.id)).toList());
    }).catchError((_) {});
  }

  @override
  void initState() {
    super.initState();
    _name = _available.first;
    if (_scoped) {
      initEntity();
      _loadItineraries();
    } else {
      entityResolved = true;
    }
    _load();
  }

  Map<String, dynamic> _query() {
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    return {
      if (_mode == _PeriodMode.relative) 'filter[last]': '$_amount$_unit',
      if (_mode == _PeriodMode.range && _range != null) ...{'filter[from]': day(_range!.start), 'filter[to]': day(_range!.end)},
      if (_by != null && _groupings[_name]?.containsKey(_by) == true) 'filter[by]': _by,
      if (_itineraryId != null) 'filter[itinerary]': _itineraryId,
      if (_scoped && entity != null) 'filter[entity]': entity!.id,
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final document = await context.api.get('/statistics/$_name', query: _query());
      setState(() => _result = Statistic.from(document.resource));
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AppScaffold(
      title: 'Estadísticas',
      tab: MainTab.more,
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (_scoped && entityResolved && entity != null) ...[entitySelector(), const SizedBox(height: 8)],
        DropdownButtonFormField<String>(
          initialValue: _name,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Estadística'),
          items: [for (final name in _available) DropdownMenuItem(value: name, child: Text(_titles[name]!))],
          onChanged: (value) {
            setState(() {
              _name = value!;
              _by = _groupings[_name]?.keys.first;
            });
            _load();
          },
        ),
        const SizedBox(height: 12),
        SegmentedButton<_PeriodMode>(
          segments: const [
            ButtonSegment(value: _PeriodMode.relative, label: Text('Últimos')),
            ButtonSegment(value: _PeriodMode.range, label: Text('Rango de fechas')),
          ],
          selected: {_mode},
          onSelectionChanged: (value) {
            setState(() => _mode = value.first);
            _load();
          },
        ),
        const SizedBox(height: 8),
        if (_mode == _PeriodMode.relative)
          Row(children: [
            SizedBox(
              width: 90,
              child: TextFormField(
                initialValue: '$_amount',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cantidad'),
                onFieldSubmitted: (value) {
                  _amount = int.tryParse(value) ?? 30;
                  _load();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _unit,
                items: const [
                  DropdownMenuItem(value: 'd', child: Text('días')),
                  DropdownMenuItem(value: 'w', child: Text('semanas')),
                  DropdownMenuItem(value: 'm', child: Text('meses')),
                  DropdownMenuItem(value: 'y', child: Text('años')),
                ],
                onChanged: (value) {
                  _unit = value!;
                  _load();
                },
              ),
            ),
          ]),
        if (_mode == _PeriodMode.range)
          DateRangeField(
            label: 'Rango de fechas',
            value: _range,
            firstDate: DateTime(DateTime.now().year - 3),
            lastDate: DateTime.now(),
            onChanged: (range) {
              setState(() => _range = range);
              _load();
            },
          ),
        if (_groupings[_name] != null) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _by ?? _groupings[_name]!.keys.first,
            decoration: const InputDecoration(labelText: 'Agrupar por'),
            items: [for (final e in _groupings[_name]!.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (value) {
              _by = value;
              _load();
            },
          ),
        ],
        if (_itineraries.isNotEmpty && _name != 'workers-distribution' && _name != 'worker-trips') ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            key: ValueKey('${entity?.id}-${_itineraries.length}'),
            initialValue: _itineraryId,
            decoration: const InputDecoration(labelText: 'Itinerario'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
              for (final i in _itineraries) DropdownMenuItem<String?>(value: i.id, child: Text(i.name)),
            ],
            onChanged: (value) {
              _itineraryId = value;
              _load();
            },
          ),
        ],
        const SizedBox(height: 16),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (!_loading && result != null) ...[
          Text(result.periodLabel, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (result.rows.isEmpty) const Text('Sin datos en este periodo.') else ...[
            _Chart(result, _titles[_name]!),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [for (final c in result.columns) DataColumn(label: Text(c.label), numeric: c.numeric)],
                rows: [
                  for (final row in result.rows) DataRow(cells: [for (final c in result.columns) DataCell(Text(result.format(c, row[c.key])))]),
                ],
              ),
            ),
          ],
        ],
      ]),
    );
  }
}

class _Chart extends StatelessWidget {
  final Statistic statistic;
  final String name;

  const _Chart(this.statistic, this.name);

  @override
  Widget build(BuildContext context) {
    final series = statistic.chartSeries();
    if (series == null) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.primary;
    // Eje en enteros: intervalos de 1 en adelante, sin decimales.
    final top = series.values.fold<double>(0, (a, b) => b > a ? b : a);
    final interval = top <= 5 ? 1.0 : (top / 5).ceilToDouble();
    final maxY = ((top / interval).ceil() * interval).clamp(interval, double.infinity).toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, style: Theme.of(context).textTheme.titleSmall),
      Text(series.title, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      SizedBox(
        height: 220,
        child: BarChart(BarChartData(
          minY: 0,
          maxY: maxY,
          barGroups: [
            for (var i = 0; i < series.values.length; i++)
              BarChartGroupData(x: i, barRods: [BarChartRodData(toY: series.values[i], color: color, width: 16, borderRadius: BorderRadius.circular(4))]),
          ],
          gridData: FlGridData(drawVerticalLine: false, horizontalInterval: interval),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: interval,
                getTitlesWidget: (value, meta) => value != value.roundToDouble()
                    ? const SizedBox.shrink()
                    : Text('${value.toInt()}', style: const TextStyle(fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= series.labels.length) return const SizedBox.shrink();
                  final label = series.labels[index];
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(label.length > 10 ? '${label.substring(0, 10)}…' : label, style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
          ),
        )),
      ),
    ]);
  }
}
