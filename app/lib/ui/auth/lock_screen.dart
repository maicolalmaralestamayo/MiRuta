import 'package:flutter/material.dart';

import '../widgets/common.dart';

/// Pantalla de desbloqueo con huella o PIN del teléfono.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    try {
      await context.session.unlock();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text('MiTransporte está bloqueada'),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _unlock, icon: const Icon(Icons.fingerprint), label: const Text('Desbloquear')),
          TextButton(onPressed: () => context.session.logout(), child: const Text('Cerrar sesión')),
        ]),
      ),
    );
  }
}
