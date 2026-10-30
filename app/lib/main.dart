import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

import 'core/api_client.dart';
import 'services/notifications.dart';
import 'services/session.dart';
import 'services/sync.dart';
import 'services/tracking_service.dart';
import 'ui/auth/lock_screen.dart';
import 'ui/auth/login_screen.dart';
import 'ui/home/home_shell.dart';
import 'ui/theme.dart';

/// Tarea en segundo plano: sincroniza viajes, avisos y mensajes.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Notifications.init();
      await initializeDateFormatting('es');
      final part = SyncPart.fromTask(task);
      await SyncService.run(await ApiClient.create(), parts: part == null ? {...SyncPart.values} : {part});
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
  TrackingService.init();

  final session = Session(await ApiClient.create());
  runApp(ChangeNotifierProvider.value(value: session, child: const MiTransporteApp()));
  session.init();
}

class MiTransporteApp extends StatelessWidget {
  const MiTransporteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MiTransporte',
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
      home: const WithForegroundTask(child: _Root()),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    switch (context.watch<Session>().state) {
      case SessionState.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case SessionState.loggedOut:
        return const LoginScreen();
      case SessionState.locked:
        return const LockScreen();
      case SessionState.ready:
        return const HomeShell();
    }
  }
}
