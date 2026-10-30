import '../../core/json_api.dart';
import '../../services/templates.dart';

class StatisticColumn {
  final String key;
  final String label;
  final String type;

  StatisticColumn(this.key, this.label, this.type);

  bool get numeric => type == 'integer' || type == 'number' || type == 'percent';
}

class ChartSeries {
  final String title;
  final List<String> labels;
  final List<double> values;

  ChartSeries(this.title, this.labels, this.values);
}

/// Resultado de GET /statistics/{nombre}: columnas y filas.
class Statistic {
  final List<StatisticColumn> columns;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> period;

  Statistic(this.columns, this.rows, this.period);

  factory Statistic.from(Resource r) => Statistic(
        [for (final c in (r.attributes['columns'] as List)) StatisticColumn('${(c as Map)['key']}', '${c['label']}', '${c['type']}')],
        [for (final row in (r.attributes['rows'] as List)) Map<String, dynamic>.from(row as Map)],
        Map<String, dynamic>.from(r.meta['period'] as Map? ?? const {}),
      );

  String get periodLabel {
    final dates = period['dates'] as List?;
    if (dates != null) return 'Fechas: ${dates.map((d) => formatDate(DateTime.parse('$d'))).join(', ')}';
    if (period['from'] == null) return '';
    return 'Del ${formatDate(DateTime.parse('${period['from']}'))} al ${formatDate(DateTime.parse('${period['to']}'))}';
  }

  String format(StatisticColumn column, Object? value) {
    if (value == null) return '—';
    switch (column.type) {
      case 'percent':
        return '${(value as num).toStringAsFixed(1)} %';
      case 'datetime':
        return formatDateTime(DateTime.parse('$value').toLocal());
      case 'number':
        return (value as num).toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
      default:
        return const {
              'unconfirmed': 'No confirmado', 'confirmed': 'Confirmado', 'completed': 'Realizado', 'cancelled': 'Cancelado',
              'outbound': 'Salida', 'return': 'Regreso', 'automatic': 'Automática', 'self': 'Ya subí', 'qr': 'QR', 'manual': 'Manual',
              'pending': 'Pendiente', 'approved': 'Aprobada', 'rejected': 'Rechazada',
            }['$value'] ??
            '$value';
    }
  }

  /// Serie para el gráfico: primera columna de texto como etiqueta y primera
  /// numérica como valor.
  ChartSeries? chartSeries() {
    final label = columns.where((c) => !c.numeric).firstOrNull;
    final value = columns.where((c) => c.numeric).firstOrNull;
    if (label == null || value == null || rows.isEmpty) return null;
    final labels = <String>[];
    final values = <double>[];
    for (final row in rows) {
      labels.add(format(label, row[label.key]));
      values.add((row[value.key] as num?)?.toDouble() ?? 0);
    }
    return ChartSeries(value.label, labels, values);
  }
}
