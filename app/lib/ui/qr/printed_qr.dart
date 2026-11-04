import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

/// Abre el QR impreso de esa pertenencia (docs/11 §11.9; workers.printed_qr).
Future<void> openPrintedQr(BuildContext context, Worker worker) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => PrintedQrScreen(worker: worker)));

/// QR impreso (GET /workers/{id}/printed-qr) con nombres, apellidos y sexo
/// al lado. Acciones: Compartir (imagen PNG con la lista de Android),
/// Imprimir o guardar (PDF) y Anular (POST …/revoke).
class PrintedQrScreen extends StatefulWidget {
  final Worker worker;

  const PrintedQrScreen({super.key, required this.worker});

  @override
  State<PrintedQrScreen> createState() => _PrintedQrScreenState();
}

class PrintedQr {
  final String qr;
  final int version;
  final PersonName name;
  final String fullName;
  final String? sex;

  const PrintedQr({required this.qr, required this.version, required this.name, required this.fullName, this.sex});

  factory PrintedQr.from(Resource r) => PrintedQr(
        qr: r.string('qr') ?? '',
        version: r.integer('version') ?? 0,
        name: PersonName.from(r),
        fullName: r.string('fullName') ?? '',
        sex: r.string('sex'),
      );

  String get sexText => sexLabel(sex);

  /// Nombres / apellidos / sexo, para imprimir al lado del QR.
  List<String> get printedLines => [
        [name.firstName, if (name.middleName.isNotEmpty) name.middleName].join(' '),
        [name.firstSurname, name.secondSurname].where((s) => s.isNotEmpty).join(' '),
        sexText,
      ].where((l) => l.trim().isNotEmpty).toList();

  String get fileName => 'QR-${fullName.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9]+'), '-')}';
}

class _PrintedQrScreenState extends State<PrintedQrScreen> {
  PrintedQr? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final document = await context.api.get('/workers/${widget.worker.id}/printed-qr');
      if (mounted) setState(() => (_data = PrintedQr.from(document.resource), _error = null));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.hasCode('PRINTED_QR_NOT_AVAILABLE')
          ? '${widget.worker.fullName} usa la app en su teléfono, así que no tiene QR impreso. '
              'Si perdió el teléfono, indique en su ficha que no tiene teléfono para generarle uno.'
          : error.message);
    }
  }

  Future<File> _file(String extension, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_data!.fileName}.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _sharePng() async {
    final png = await printedQrPng(_data!);
    final file = await _file('png', png);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')], subject: 'QR de ${_data!.fullName}', text: 'QR de MiRuta de ${_data!.fullName}'));
  }

  Future<void> _sharePdf() async {
    final pdf = await printedQrPdf(_data!);
    final file = await _file('pdf', pdf);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], subject: 'QR de ${_data!.fullName}'));
  }

  Future<void> _savePdf() async {
    final pdf = await printedQrPdf(_data!);
    final uri = await FilePicker.saveFile(fileName: '${_data!.fileName}.pdf', bytes: pdf, mimeType: 'application/pdf', dialogTitle: 'Guardar el QR');
    if (uri != null && mounted) showMessage(context, 'QR guardado');
  }

  Future<void> _savePng() async {
    final png = await printedQrPng(_data!);
    final uri = await FilePicker.saveFile(fileName: '${_data!.fileName}.png', bytes: png, mimeType: 'image/png', dialogTitle: 'Guardar el QR');
    if (uri != null && mounted) showMessage(context, 'Imagen guardada');
  }

  Future<void> _revoke() async {
    await context.api.post('/workers/${widget.worker.id}/printed-qr/revoke', {});
    await _load();
    if (mounted) showMessage(context, 'QR anulado. Imprima y entregue el nuevo: el anterior ya no vale.');
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final ready = data != null;
    return AppScaffold(
      title: 'QR impreso',
      tab: MainTab.more,
      actions: [
        ActionItem(icon: Icons.share_outlined, label: 'Compartir imagen', enabled: ready, onPressed: _sharePng),
        ActionItem(icon: Icons.print_outlined, label: 'Imprimir (compartir PDF)', enabled: ready, onPressed: _sharePdf),
        ActionItem(icon: Icons.picture_as_pdf_outlined, label: 'Guardar PDF', enabled: ready, onPressed: _savePdf),
        ActionItem(icon: Icons.image_outlined, label: 'Guardar imagen', enabled: ready, onPressed: _savePng),
        const ActionItem.divider(),
        ActionItem(
          icon: Icons.block,
          label: 'Anular y generar otro',
          enabled: ready,
          destructive: true,
          confirmation: 'El QR impreso actual (y sus copias) dejará de valer y se generará uno nuevo. '
              'Los teléfonos que escanean sin conexión se enteran al sincronizar. ¿Anularlo?',
          onPressed: _revoke,
        ),
      ],
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : data == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
                  Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        QrImageView(data: data.qr, size: 170, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            for (final (i, line) in data.printedLines.indexed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(line,
                                    style: TextStyle(color: Colors.black, fontSize: i < 2 ? 18 : 15, fontWeight: i < 2 ? FontWeight.w600 : FontWeight.normal)),
                              ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sirve en todas sus Entidades, sin conexión: para subir al transporte y para el alta en un itinerario. '
                    'No caduca; si se pierde o se copia, anúlelo y entregue uno nuevo. '
                    'Cuando la persona entre en la app con su teléfono, este QR se anula solo.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text('Versión ${data.version}', style: Theme.of(context).textTheme.bodySmall),
                ]),
    );
  }
}

/// Imagen PNG del QR impreso: el código y, al lado, nombres, apellidos y sexo.
Future<Uint8List> printedQrPng(PrintedQr data) async {
  const width = 1200.0, height = 600.0, qrSize = 520.0, margin = 40.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));
  canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.white);
  final painter = QrPainter(data: data.qr, version: QrVersions.auto, errorCorrectionLevel: QrErrorCorrectLevel.M, gapless: true);
  canvas.save();
  canvas.translate(margin, (height - qrSize) / 2);
  painter.paint(canvas, const Size(qrSize, qrSize));
  canvas.restore();
  var y = 150.0;
  for (final (i, line) in data.printedLines.indexed) {
    final text = TextPainter(
      text: TextSpan(text: line, style: TextStyle(color: Colors.black, fontSize: i < 2 ? 52 : 42, fontWeight: i < 2 ? FontWeight.bold : FontWeight.normal)),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: width - qrSize - margin * 3);
    text.paint(canvas, Offset(qrSize + margin * 2, y));
    y += text.height + 24;
  }
  final image = await recorder.endRecording().toImage(width.toInt(), height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// PDF sencillo (A4) con la tarjeta para recortar: QR y, al lado, nombres,
/// apellidos y sexo.
Future<Uint8List> printedQrPdf(PrintedQr data) async {
  final document = pw.Document(title: 'QR de ${data.fullName}', author: 'MiRuta');
  document.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (context) => pw.Align(
      alignment: pw.Alignment.topLeft,
      child: pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: 0.8)),
        child: pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
          pw.BarcodeWidget(barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium), data: data.qr, width: 190, height: 190),
          pw.SizedBox(width: 16),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            for (final (i, line) in data.printedLines.indexed)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(line, style: pw.TextStyle(fontSize: i < 2 ? 16 : 13, fontWeight: i < 2 ? pw.FontWeight.bold : pw.FontWeight.normal)),
              ),
          ]),
        ]),
      ),
    ),
  ));
  return document.save();
}
