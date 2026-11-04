import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api_exception.dart';
import '../../services/qr/qr_codes.dart';
import '../../services/qr/qr_device.dart';
import '../../services/templates.dart';
import '../navigation.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

/// Mi QR (docs/11 §11.8): QR dinámico `MR1.…` firmado en el teléfono con la
/// clave del Android Keystore, generado sin conexión y renovado cada 15 s.
/// Mientras se muestra, la pantalla no admite capturas ni grabación (FLAG_SECURE).
class MyQrScreen extends StatefulWidget {
  const MyQrScreen({super.key});

  @override
  State<MyQrScreen> createState() => _MyQrScreenState();
}

class _MyQrScreenState extends State<MyQrScreen> with WidgetsBindingObserver {
  StoredCertificate? _certificate;
  String? _qr;
  String? _error;
  int _left = qrRefreshSeconds;
  Timer? _timer;
  bool _renewing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    QrDevice.setSecure(true);
    _start();
  }

  Future<void> _start() async {
    final api = context.api;
    final userId = context.me.userId;
    try {
      // Con conexión lo registra o renueva; sin conexión vale el guardado.
      _certificate = await QrDevice.ensureCertificate(api, userId);
      _error = null;
    } on ApiException catch (error) {
      _certificate = await QrDevice.certificate();
      if (_certificate == null || _certificate!.userId != userId) {
        _certificate = null;
        _error = error.isNetwork
            ? 'Para activar su QR, abra esta pantalla una vez con conexión al servidor. Después funciona sin conexión.'
            : error.message;
      }
    } catch (_) {
      _certificate = null;
      _error = 'Este teléfono no puede guardar la clave segura del QR.';
    }
    if (!mounted) return;
    await _refresh();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        _refresh();
      } else {
        setState(() => _left--);
      }
    });
  }

  Future<void> _refresh() async {
    final certificate = _certificate;
    if (certificate == null) {
      setState(() {});
      return;
    }
    try {
      final qr = await QrDevice.currentQr(certificate);
      if (mounted) {
        setState(() {
          _qr = qr;
          _left = qrRefreshSeconds;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo firmar el código con la clave del teléfono.');
    }
  }

  Future<void> _renew() async {
    setState(() => _renewing = true);
    try {
      _certificate = await QrDevice.ensureCertificate(context.api, context.me.userId, force: true);
      _error = null;
      await _refresh();
      if (mounted) showMessage(context, 'Certificado renovado');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _renewing = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver a la app se genera uno nuevo enseguida.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    QrDevice.setSecure(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.me;
    final certificate = _certificate;
    final theme = Theme.of(context);
    return AppScaffold(
      title: 'Mi QR',
      tab: MainTab.more,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        Text(me.fullName, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Sirve en todas sus Entidades: para subir al transporte y para que le den de alta en un itinerario.',
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        if (_error != null && certificate == null)
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center)))
        else if (_qr == null)
          const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
        else
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: _qr!,
                size: 300,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                backgroundColor: Colors.white,
                semanticsLabel: 'Mi código QR',
              ),
            ),
          ),
        if (_qr != null) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _left / qrRefreshSeconds),
          const SizedBox(height: 6),
          Text('Se renueva en $_left s. Cada código vale una sola vez.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
        if (certificate != null) ...[
          const SizedBox(height: 16),
          if (certificate.expired)
            Text('El certificado de este teléfono caducó: conéctese para renovarlo.', textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error))
          else
            Text('Certificado del teléfono válido hasta el ${formatDate(certificate.expiresAt)}.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _renewing ? null : _renew,
              icon: _renewing ? const BusyIndicator(size: 16) : const Icon(Icons.refresh),
              label: const Text('Renovar certificado'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text('Esta pantalla no admite capturas ni grabación. Una foto del código deja de valer en segundos.',
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
      ]),
    );
  }
}
