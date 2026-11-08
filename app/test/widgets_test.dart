import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mitransporte/core/api_client.dart';
import 'package:mitransporte/models/models.dart';
import 'package:mitransporte/services/session.dart';
import 'package:mitransporte/ui/auth/login_screen.dart';
import 'package:mitransporte/ui/home/home_screen.dart';
import 'package:mitransporte/ui/theme.dart';
import 'package:mitransporte/ui/widgets/cards.dart';
import 'package:mitransporte/ui/widgets/marks.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Session session, Widget home) => MultiProvider(
      providers: [ChangeNotifierProvider.value(value: session), ChangeNotifierProvider.value(value: session.connection)],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
    );

Session newSession() => Session(ApiClient.withDio(Dio(BaseOptions(baseUrl: ''))));

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(appName: 'MiRuta', packageName: 'x', version: '4.0.0', buildNumber: '10', buildSignature: '');
    await initializeDateFormatting('es');
  });

  test('se marca un solo tipo a la vez (docs/11 §11.23)', () {
    final marks = Marks();
    marks.toggle('stop', '1');
    marks.toggle('stop', '2');
    expect(marks.count, 2);
    marks.toggle('person', 'w5');
    expect(marks.type, 'person');
    expect(marks.keys, {'w5'});
    marks.invert(['w5', 'w6', 'w7']);
    expect(marks.keys, {'w6', 'w7'});
    marks.markAll(['w5', 'w6', 'w7']);
    expect(marks.count, 3);
    marks.clear();
    expect(marks.active, isFalse);
  });

  testWidgets('sección plegable paginada de 5 en 5', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          FoldSection<int>(storageKey: 'prueba', title: 'Personas', items: List.generate(12, (i) => i), builder: (i) => Text('Persona $i')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Personas (12)'), findsOneWidget);
    expect(find.text('1–5 de 12'), findsOneWidget);
    expect(find.text('Persona 5'), findsNothing);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.text('Persona 5'), findsOneWidget);
    await tester.tap(find.text('Personas (12)'));
    await tester.pump();
    expect(find.text('Persona 5'), findsNothing);
  });

  testWidgets('tarjeta marcada con el check naranja', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: InfoCard(images: [CardImage(icon: Icons.place)], title: 'Coppelia', lines: ['Calle 23'], selected: true))));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('inicio de sesión sin servidor: botón rojo y diálogo «Falta el servidor»', (tester) async {
    final session = newSession()..state = SessionState.loggedOut;
    await tester.pumpWidget(app(session, const LoginScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Servidor'), findsOneWidget);
    expect(find.text('Olvidé usuario/contraseña'), findsOneWidget);
    expect(find.text('Registrarme'), findsOneWidget);
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Falta el servidor'), findsOneWidget);
    expect(find.text('Indicar servidor'), findsOneWidget);
  });

  testWidgets('Inicio: aviso «Aún no tiene Entidad» y botones Perfil, Hijos y Mi QR', (tester) async {
    final session = newSession()
      ..state = SessionState.ready
      ..me = const Me(userId: '3', username: 'rosa', fullName: 'Rosa Martínez Gil', role: Role.trabajador);
    await tester.pumpWidget(app(session, const HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Rosa Martínez Gil'), findsOneWidget);
    for (final label in ['Perfil', 'Hijos', 'Mi QR', 'Aún no tiene Entidad', 'Solicitar Entidad', 'Inicio', 'Gestión', 'Viajes', 'Más']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });
}
