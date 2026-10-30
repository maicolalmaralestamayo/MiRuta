import 'package:flutter/material.dart';

import '../../services/app_pin.dart';
import '../widgets/common.dart';

/// Desbloqueo con el PIN de la app. Tras varios intentos fallidos, o si se
/// olvidó, se cierra la sesión y se entra con el carné y la contraseña.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  int _attempts = 0;
  String? _error;
  bool _busy = false;

  Future<void> _press(String digit) async {
    if (_busy || _pin.length >= AppPin.maxLength) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_pin.length < AppPin.minLength) return;
    setState(() => _busy = true);
    try {
      final ok = await context.session.unlock(_pin);
      if (ok || !mounted) return;
      _attempts++;
      if (_attempts >= AppPin.maxAttempts) {
        await context.session.logout();
        return;
      }
      setState(() {
        _pin = '';
        _error = 'PIN incorrecto. Te quedan ${AppPin.maxAttempts - _attempts} intento(s).';
      });
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => SizedBox(
          width: 76,
          height: 76,
          child: TextButton(
            style: TextButton.styleFrom(shape: const CircleBorder()),
            onPressed: onTap ?? () => _press(label),
            child: icon == null ? Text(label, style: Theme.of(context).textTheme.headlineMedium) : Icon(icon, size: 28),
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 56, color: colors.primary),
              const SizedBox(height: 12),
              Text('Escribe tu PIN', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < AppPin.maxLength; i++)
                  Container(
                    margin: const EdgeInsets.all(6),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length ? colors.primary : null,
                      border: Border.all(color: i < AppPin.minLength || i < _pin.length ? colors.primary : colors.outlineVariant),
                    ),
                  ),
              ]),
              SizedBox(height: 28, child: _error == null ? null : Text(_error!, style: TextStyle(color: colors.error))),
              for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
                Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d)]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                key('', icon: Icons.backspace_outlined, onTap: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1))),
                key('0'),
                key('', icon: Icons.check_circle, onTap: _pin.length >= AppPin.minLength ? _submit : null),
              ]),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  if (await confirm(context, '¿Olvidaste el PIN?', 'Se cerrará la sesión y tendrás que entrar con tu carné y tu contraseña.')) {
                    if (context.mounted) await context.session.logout();
                  }
                },
                child: const Text('¿Olvidaste el PIN?'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
