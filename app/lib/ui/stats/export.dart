import 'dart:io';
import 'dart:math';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'statistic.dart';

/// Exportación de una estadística a Excel o a PDF (con su gráfico), para
/// guardar o compartir desde el teléfono.
class StatisticExport {
  static Future<void> excel(Statistic statistic, String title) async {
    final workbook = Excel.createExcel();
    final sheet = workbook['Estadística'];
    workbook.setDefaultSheet('Estadística');
    workbook.delete('Sheet1');
    sheet.appendRow([TextCellValue(title)]);
    sheet.appendRow([TextCellValue(statistic.periodLabel)]);
    sheet.appendRow([]);
    sheet.appendRow([for (final column in statistic.columns) TextCellValue(column.label)]);
    for (final row in statistic.rows) {
      sheet.appendRow([
        for (final column in statistic.columns)
          switch (row[column.key]) {
            int value => IntCellValue(value),
            double value => DoubleCellValue(value),
            null => null,
            final value => TextCellValue(statistic.format(column, value)),
          },
      ]);
    }
    await _share(workbook.encode()!, '${_fileName(title)}.xlsx');
  }

  static Future<void> pdf(Statistic statistic, String title) async {
    final document = pw.Document();
    final chart = statistic.chartSeries();
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Header(level: 0, text: title),
        pw.Text(statistic.periodLabel),
        pw.SizedBox(height: 12),
        if (chart != null && chart.values.isNotEmpty) pw.SizedBox(height: 220, child: _chart(chart)),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: [for (final column in statistic.columns) column.label],
          data: [
            for (final row in statistic.rows) [for (final column in statistic.columns) statistic.format(column, row[column.key])],
          ],
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ));
    await _share(await document.save(), '${_fileName(title)}.pdf');
  }

  static pw.Widget _chart(ChartSeries series) {
    final maximum = series.values.reduce(max);
    final top = maximum <= 0 ? 1.0 : maximum;
    final step = top / 5;
    return pw.Chart(
      grid: pw.CartesianGrid(
        xAxis: pw.FixedAxis.fromStrings([for (final label in series.labels) label.length > 12 ? '${label.substring(0, 12)}…' : label], marginStart: 20, marginEnd: 20),
        yAxis: pw.FixedAxis([for (var i = 0; i <= 5; i++) i * step], format: (value) => value.toStringAsFixed(value < 10 ? 1 : 0), divisions: true),
      ),
      datasets: [
        pw.BarDataSet(
          color: PdfColors.teal,
          width: 14,
          data: [for (var i = 0; i < series.values.length; i++) pw.PointChartValue(i.toDouble(), series.values[i])],
        ),
      ],
    );
  }

  static String _fileName(String title) => title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9áéíóúñ]+'), '_');

  static Future<void> _share(List<int> bytes, String name) async {
    final file = File('${(await getTemporaryDirectory()).path}/$name');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], title: name));
  }
}
