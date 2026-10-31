import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../widgets/common.dart';
import 'statistic.dart';

/// Estadísticas con gráfico y tabla, periodo por rango, fechas sueltas o
/// relativo. Solo se ven en la app (no se exportan). Cada rol ve las suyas.
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
  'workers-distribution': 'Distribución de trabajadores',
  'worker-trips': 'Mis viajes',
  'applications-summary': 'Solicitudes',
  'stop-activity': 'Subidas y bajadas por parada',
  'stop-pass-times': 'Hora de paso por las paradas',
  'distance': 'Distancia recorrida',
};

const _groupings = {
  'punctuality': {'itinerary': 'Itinerario', 'vehicle': 'Vehículo', 'driver': 'Chofer'},
  'occupancy': {'itinerary': 'Itinerario', 'vehicle': 'Vehículo'},
  'workers-distribution': {'itinerary': 'Itinerario', 'stop': 'Parada', 'rank': 'Jerarquía', 'sex': 'Sexo'},
};

enum _PeriodMode { relative, range, dates }

class _StatisticsScreenState extends State<StatisticsScreen> {
  String _name = 'worker-trips';
  _PeriodMode _mode = _PeriodMode.relative;
  int _amount = 30;
  String _unit = 'd';
  DateTimeRange? _range;
  final Set<DateTime> _dates = {};
  String? _by;
  String? _itineraryId;
  List<Itinerary> _itineraries = [];
  Statistic? _result;
  String? _error;
  bool _loading = false;

  List<String> get _available {
    final me = context.me;
    if (me.managesTransport || me.roles.isItineraryChief) return _titles.keys.toList();
    if (me.roles.isDriver) {
      return const ['trips-by-status', 'punctuality', 'duration', 'overloaded-trips', 'occupancy', 'attendance', 'children-transported', 'stop-activity', 'stop-pass-times', 'distance', 'worker-trips'];
    }
    return const ['worker-trips'];
  }

  @override
  void initState() {
    super.initState();
    _name = _available.first;
    if (context.me.managesTransport || context.me.roles.isItineraryChief) {
      context.api.getAll('/itineraries', query: {'sort': 'name', ...context.entityFilter}).then((r) {
        if (mounted) setState(() => _itineraries = r.map(Itinerary.from).toList());
      }).catchError((_) {});
    }
    _load();
  }

  Map<String, dynamic> _query() {
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    return {
      if (_mode == _PeriodMode.relative) 'filter[last]': '$_amount$_unit',
      if (_mode == _PeriodMode.range && _range != null) ...{'filter[from]': day(_range!.start), 'filter[to]': day(_range!.end)},
      if (_mode == _PeriodMode.dates && _dates.isNotEmpty) 'filter[dates]': (_dates.toList()..sort()).map(day).join(','),
      if (_by != null && _groupings[_name]?.containsKey(_by) == true) 'filter[by]': _by,
      if (_itineraryId != null) 'filter[itinerary]': _itineraryId,
      ...context.entityFilter,
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

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, firstDate: DateTime(now.year - 3), lastDate: now, helpText: 'Añadir una fecha');
    if (date != null) {
      setState(() => _dates.add(date));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas'),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
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
            ButtonSegment(value: _PeriodMode.range, label: Text('Rango')),
            ButtonSegment(value: _PeriodMode.dates, label: Text('Fechas')),
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
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text(_range == null ? 'Elegir rango' : '${formatDate(_range!.start)} → ${formatDate(_range!.end)}'),
            onPressed: () async {
              final now = DateTime.now();
              final range = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 3), lastDate: now);
              if (range != null) {
                setState(() => _range = range);
                _load();
              }
            },
          ),
        if (_mode == _PeriodMode.dates)
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final date in _dates.toList()..sort())
              InputChip(label: Text(formatDate(date)), onDeleted: () {
                setState(() => _dates.remove(date));
                _load();
              }),
            ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Añadir fecha'), onPressed: _pickDates),
          ]),
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
            _Chart(result),
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

  const _Chart(this.statistic);

  @override
  Widget build(BuildContext context) {
    final series = statistic.chartSeries();
    if (series == null) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.primary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(series.title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      SizedBox(
        height: 220,
        child: BarChart(BarChartData(
          barGroups: [
            for (var i = 0; i < series.values.length; i++)
              BarChartGroupData(x: i, barRods: [BarChartRodData(toY: series.values[i], color: color, width: 16, borderRadius: BorderRadius.circular(4))]),
          ],
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
