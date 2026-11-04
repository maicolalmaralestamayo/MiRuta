import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mitransporte/core/api_client.dart';
import 'package:mitransporte/core/json_api.dart';
import 'package:mitransporte/models/models.dart';
import 'package:mitransporte/services/session.dart';
import 'package:mitransporte/ui/home/home_screen.dart';
import 'package:mitransporte/ui/home/more_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _json(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// Un documento de colección a partir de un fixture de un solo recurso.
Map<String, dynamic> _asList(String name) {
  final document = _json(name);
  return {...document, 'data': [document['data']]};
}

/// Responde con los fixtures de la API 3.0 según la ruta.
class _FixtureAdapter implements HttpClientAdapter {
  final requested = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = options.uri.path.replaceFirst('/api/v1', '');
    requested.add(path);
    final body = switch (path) {
      '/children' => _asList('children'),
      '/trips' => _asList('trip'),
      '/trip-legs' => _asList('trip_leg'),
      _ => {'data': []},
    };
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
  });

  Future<(Session, _FixtureAdapter)> pumpWith(WidgetTester tester, String meFixture, Widget screen) async {
    final adapter = _FixtureAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'))..httpClientAdapter = adapter;
    final session = Session(ApiClient.withDio(dio))
      ..me = Me.from(JsonApiDocument.fromJson(_json(meFixture)).resource)
      ..state = SessionState.ready;
    tester.view.physicalSize = const Size(412 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: session.connection),
    ], child: MaterialApp(home: screen)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    return (session, adapter);
  }

  testWidgets('Inicio de una trabajadora con dos Entidades', (tester) async {
    await pumpWith(tester, 'me', const HomeScreen());
    expect(find.text('Lucía María Pérez García'), findsOneWidget);
    expect(find.text('DOS • PRUEBA'), findsOneWidget);
    for (final label in ['Perfil', 'Hijos', 'Entidades', 'Itinerario', 'Roles', 'Viajes']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Pepito Juan Pérez García'), findsOneWidget);
    expect(find.text('Nacimiento 05/03/18'), findsOneWidget);
    expect(find.text('PRUEBA'), findsNWidgets(2), reason: 'tarjeta de la Entidad y línea 2 de «Trabajador»');
    expect(find.byIcon(Icons.unfold_more), findsOneWidget);
    expect(find.text('Ruta Este'), findsWidgets);
    expect(find.text('Calle 2 • Parque'), findsOneWidget);
    expect(find.text('Trabajador'), findsOneWidget);
    expect(find.text('Viajes'), findsWidgets);
    // Barra principal sin «Solicitudes».
    expect(find.text('Mensajes'), findsOneWidget);
    expect(find.text('Más'), findsOneWidget);
    expect(find.text('Solicitudes'), findsNothing);
  });

  testWidgets('Inicio del Administrador sin Entidad', (tester) async {
    await pumpWith(tester, 'me_admin', const HomeScreen());
    expect(find.text('Sin Entidad'), findsWidgets);
    expect(find.text('Unirme a una Entidad'), findsOneWidget);
    expect(find.text('Itinerario y parada'), findsNothing);
  });

  testWidgets('Más: Gestión solo con permisos de gestión', (tester) async {
    await pumpWith(tester, 'me', const MoreScreen());
    expect(find.text('Gestión'), findsNothing);
  });

  testWidgets('Más: la Jefa de Transporte ve Gestión', (tester) async {
    await pumpWith(tester, 'me_chief', const MoreScreen());
    expect(find.text('Gestión'), findsOneWidget);
  });
}
