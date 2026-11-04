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
import 'package:mitransporte/ui/trips/trips_screen.dart';
import 'package:mitransporte/ui/worker/child_form_screen.dart';
import 'package:mitransporte/ui/worker/children_screen.dart';
import 'package:mitransporte/ui/worker/entities_screen.dart';
import 'package:mitransporte/ui/worker/itinerary_screen.dart';
import 'package:mitransporte/ui/worker/roles_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _json(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _asList(Map<String, dynamic> document) => {...document, 'data': [document['data']]};

/// Respuestas de la API 3.0 con los fixtures; filtra las solicitudes por
/// tipo, estado y Entidad como el servidor. Anota cada petición («GET /x»).
class _FixtureAdapter implements HttpClientAdapter {
  final requests = <String>[];

  /// Solicitudes (por defecto, las del fixture).
  List<dynamic> applications = (_json('applications')['data'] as List);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = options.uri.path.replaceFirst('/api/v1', '');
    final query = options.uri.queryParameters;
    requests.add('${options.method} $path');
    if (options.method == 'DELETE') return ResponseBody.fromString('', 204);
    final body = switch (path) {
      '/children' => _asList(_json('children')),
      '/applications' => {
          'data': applications.where((a) {
            final attributes = (a as Map)['attributes'] as Map;
            final entity = ((a['relationships'] as Map)['entity'] as Map)['data'] as Map?;
            return (query['filter[type]'] == null || attributes['type'] == query['filter[type]']) &&
                (query['filter[status]'] == null || attributes['status'] == query['filter[status]']) &&
                (query['filter[entity]'] == null || entity?['id'] == query['filter[entity]']);
          }).toList(),
        },
      '/absences' => _json('absences'),
      '/roles' => _json('roles'),
      '/trips' => _runningTrip(),
      '/trip-legs' => _asList(_json('trip_leg')),
      _ => {'data': []},
    };
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  /// El viaje del fixture, hoy: salió hace una hora y regresa dentro de una.
  Map<String, dynamic> _runningTrip() {
    final document = _asList(_json('trip'));
    final trip = (document['data'] as List).first as Map<String, dynamic>;
    final now = DateTime.now().toUtc();
    trip['attributes'] = {
      ...trip['attributes'] as Map,
      'departsAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
      'returnsAt': now.add(const Duration(hours: 1)).toIso8601String(),
    };
    return document;
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

  Future<_FixtureAdapter> pump(WidgetTester tester, Widget screen, {String me = 'me', void Function(_FixtureAdapter)? setUp}) async {
    final adapter = _FixtureAdapter();
    setUp?.call(adapter);
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'))..httpClientAdapter = adapter;
    final session = Session(ApiClient.withDio(dio))
      ..me = Me.from(JsonApiDocument.fromJson(_json(me)).resource)
      ..state = SessionState.ready;
    tester.view.physicalSize = const Size(412 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: session.connection),
    ], child: MaterialApp(home: screen)));
    await settle(tester);
    return adapter;
  }

  Future<void> openActions(WidgetTester tester) async {
    await tester.tap(find.text('Acciones'));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String label) =>
      tester.widget<ListTile>(find.ancestor(of: find.text(label), matching: find.byType(ListTile))).enabled;

  testWidgets('Hijos: secciones, selección y eliminar con confirmación', (tester) async {
    final adapter = await pump(tester, const ChildrenScreen());
    expect(find.text('Con derecho a viajar'), findsOneWidget);
    expect(find.text('Pepito Juan Pérez García'), findsOneWidget);
    expect(find.text('Derecho 31/08/34'), findsOneWidget);
    expect(find.text('Hablar con el desarrollador'), findsOneWidget);

    await openActions(tester);
    expect(enabled(tester, 'Crear hijo nuevo'), isTrue);
    expect(enabled(tester, 'Agregar hijo ya registrado'), isTrue);
    expect(enabled(tester, 'Editar'), isFalse);
    expect(enabled(tester, 'Eliminar'), isFalse);
    await openActions(tester); // cierra

    await tester.longPress(find.text('Pepito Juan Pérez García'));
    await tester.pumpAndSettle();
    expect(find.text('1 seleccionado'), findsOneWidget);
    await openActions(tester);
    expect(enabled(tester, 'Editar'), isTrue);
    expect(enabled(tester, 'Desactivar'), isTrue);
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await settle(tester);
    expect(adapter.requests, contains('DELETE /children/1'));
  });

  testWidgets('Formulario de un hijo: solo lectura y otros padres', (tester) async {
    final resource = JsonApiDocument.fromJson(_json('children')).resource;
    final base = Child.from(resource);
    final child = Child(
      id: base.id,
      name: base.name,
      sex: base.sex,
      birthDate: base.birthDate,
      eligibleUntil: base.eligibleUntil,
      identityCard: base.identityCard,
      parents: [...base.parents, (id: '9', fullName: 'Pedro Pérez Díaz')],
    );
    await pump(tester, ChildFormScreen(child: child));
    expect(find.text('Hijo'), findsOneWidget);
    expect(find.text('Masculino • 05/03/18'), findsOneWidget);
    expect(find.text('31/08/34'), findsOneWidget);
    expect(find.text('También lo tiene declarado'), findsOneWidget);
    expect(find.text('Pedro Pérez Díaz'), findsOneWidget);
    expect(find.text('Lucía María Pérez García'), findsNothing, reason: 'ella misma no sale');
    await openActions(tester);
    for (final label in ['Guardar', 'Desactivar', 'Eliminar']) {
      expect(enabled(tester, label), isTrue, reason: label);
    }
  });

  testWidgets('Hijo nuevo: el derecho se comprueba al guardar', (tester) async {
    await pump(tester, const ChildFormScreen());
    expect(find.text('Hijo nuevo'), findsOneWidget);
    expect(find.text('Se comprueba al guardar'), findsOneWidget);
    await openActions(tester);
    expect(find.text('Desactivar'), findsNothing);
    expect(find.text('Eliminar'), findsNothing);
  });

  testWidgets('Entidades: mis Entidades y solicitudes; acciones según la selección', (tester) async {
    await pump(tester, const MyEntitiesScreen(), setUp: (adapter) {
      final pending = jsonDecode(jsonEncode(adapter.applications[2])) as Map<String, dynamic>;
      pending['id'] = '9';
      (pending['attributes'] as Map)['status'] = 'pending';
      (pending['attributes'] as Map)['entityAbbreviation'] = 'TRES';
      adapter.applications = [...adapter.applications, pending];
    });
    expect(find.text('Mis Entidades'), findsOneWidget);
    expect(find.text('PRUEBA'), findsOneWidget);
    expect(find.text('DOS'), findsOneWidget);
    expect(find.text('Solicitudes pendientes'), findsOneWidget);
    expect(find.text('TRES'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);

    await tester.longPress(find.text('PRUEBA'));
    await tester.pumpAndSettle();
    await openActions(tester);
    expect(enabled(tester, 'Solicitar entrar en una Entidad'), isTrue);
    expect(enabled(tester, 'Darme de baja'), isTrue);
    expect(enabled(tester, 'Cancelar solicitud'), isFalse);
    await openActions(tester);

    await tester.tap(find.text('TRES')); // en modo selección: marca también la solicitud
    await tester.pumpAndSettle();
    expect(find.text('2 seleccionados'), findsOneWidget);
    await openActions(tester);
    expect(enabled(tester, 'Darme de baja'), isFalse, reason: 'selección mezclada');
    expect(enabled(tester, 'Cancelar solicitud'), isFalse);
    await openActions(tester);

    await tester.tap(find.text('PRUEBA')); // desmarca: queda solo la solicitud
    await tester.pumpAndSettle();
    await openActions(tester);
    expect(enabled(tester, 'Darme de baja'), isFalse);
    expect(enabled(tester, 'Cancelar solicitud'), isTrue);
  });

  testWidgets('Itinerario y parada: selector, itinerario y ausencias', (tester) async {
    final adapter = await pump(tester, const ItineraryStopScreen());
    expect(find.byIcon(Icons.unfold_more), findsOneWidget, reason: 'selector de Entidad');
    expect(find.text('Mi itinerario y parada'), findsOneWidget);
    expect(find.text('Ruta Este'), findsOneWidget);
    expect(find.text('Calle 2 • Parque'), findsOneWidget);
    expect(find.text('Ausencias'), findsOneWidget);
    expect(find.text('Enfermedad'), findsOneWidget);
    expect(find.textContaining('al '), findsOneWidget);
    expect(find.text('Hablar con el desarrollador'), findsOneWidget);
    expect(adapter.requests, contains('GET /absences'));

    await tester.longPress(find.text('Enfermedad'));
    await tester.pumpAndSettle();
    await openActions(tester);
    expect(enabled(tester, 'Solicitar itinerario y parada'), isTrue);
    expect(enabled(tester, 'Declarar ausencia'), isTrue);
    expect(enabled(tester, 'Editar'), isTrue);
    expect(enabled(tester, 'Eliminar'), isTrue);
    expect(enabled(tester, 'Darme de baja'), isFalse, reason: 'solo con el itinerario seleccionado');
  });

  testWidgets('Roles: Trabajador primero, sin baja; solicitud pendiente', (tester) async {
    await pump(tester, const MyRolesScreen());
    expect(find.text('Mis roles'), findsOneWidget);
    expect(find.text('Trabajador'), findsOneWidget);
    expect(find.text('Chofer'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Trabajador')).dy, lessThan(tester.getTopLeft(find.text('Chofer')).dy));

    await tester.longPress(find.text('Trabajador'));
    await tester.pumpAndSettle();
    expect(find.text('1 seleccionado'), findsNothing, reason: '«Trabajador» no se selecciona');

    await tester.longPress(find.text('Chofer'));
    await tester.pumpAndSettle();
    await openActions(tester);
    expect(enabled(tester, 'Solicitar un rol'), isTrue);
    expect(enabled(tester, 'Darme de baja'), isFalse);
    expect(enabled(tester, 'Cancelar solicitud'), isTrue);
  });

  testWidgets('Viajes: selector, en curso y sin botón Acciones', (tester) async {
    await pump(tester, const TripsScreen());
    expect(find.byIcon(Icons.unfold_more), findsOneWidget);
    expect(find.text('En curso'), findsWidgets);
    expect(find.text('Ruta Este'), findsOneWidget);
    expect(find.text('Acciones'), findsNothing);
  });
}

/// Deja terminar las peticiones (asíncronas de verdad) y las animaciones.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }
}
