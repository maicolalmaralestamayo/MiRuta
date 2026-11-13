import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

import 'core/api_client.dart';
import 'core/storage.dart';
import 'services/notifications.dart';
import 'services/session.dart';
import 'services/sync.dart';
import 'ui/auth/login_screen.dart';
import 'ui/auth/new_password_screen.dart';
import 'ui/home/home_shell.dart';
import 'ui/theme.dart';

/// Tarea en segundo plano: GET sync con «Frecuencia reposo» o «Frecuencia
/// día viaje» (docs/11 §11.44), y notificaciones del teléfono.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Con la app abierta consulta ella (y muestra los avisos dentro).
      if (await Storage.isForeground()) return true;
      await Notifications.init();
      await initializeDateFormatting('es');
      await SyncService.run(await ApiClient.create());
    } catch (_) {
      // Sin conexión o sesión cerrada: se intenta en la siguiente ejecución.
    }
    return true;
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  await initializeDateFormatting('es');
  await Notifications.init();
  await Workmanager().initialize(callbackDispatcher);

  final session = Session(await ApiClient.create());
  runApp(MultiProvider(providers: [
    ChangeNotifierProvider.value(value: session),
    ChangeNotifierProvider.value(value: session.connection),
  ], child: const MiRutaApp()));
  session.init();
}

class MiRutaApp extends StatelessWidget {
  const MiRutaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MiRuta',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const WithForegroundTask(child: Root()),
    );
  }
}

/// Raíz: inicio de sesión (con la actualización obligatoria, si la hay),
/// contraseña nueva obligatoria o la pantalla principal.
class Root extends StatelessWidget {
  const Root({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    switch (session.state) {
      case SessionState.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case SessionState.loggedOut:
        return const LoginScreen();
      case SessionState.ready:
        if (session.me?.mustChangePassword == true) return const NewPasswordScreen();
        return const HomeShell();
    }
  }
}
