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
import 'package:mitransporte/ui/admin/applications_screen.dart';
import 'package:mitransporte/ui/admin/roles_admin_screen.dart';
import 'package:mitransporte/ui/admin/workers_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _json(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// Una petición recibida por el cliente falso.
class _Request {
  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Map<String, dynamic>? body;

  _Request(this.method, this.path, this.query, this.body);
}

typedef _Handler = Map<String, dynamic>? Function(_Request request);

/// Responde con lo que diga [handler] (o una colección vacía) y guarda las peticiones.
class _FakeApi implements HttpClientAdapter {
  final _Handler handler;
  final requests = <_Request>[];

  _FakeApi(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    Map<String, dynamic>? body;
    if (requestStream != null) {
      final bytes = await requestStream.expand((chunk) => chunk).toList();
      if (bytes.isNotEmpty) body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    }
    final request = _Request(options.method, options.uri.path.replaceFirst('/api/v1', ''), options.uri.queryParameters, body);
    requests.add(request);
    final response = handler(request) ?? {'data': []};
    return ResponseBody.fromString(jsonEncode(response), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _entities = {
  'data': [
    {
      'type': 'entities',
      'id': '1',
      'attributes': {'abbreviation': 'PRUEBA', 'name': 'Empresa de prueba', 'workerCount': 3, 'active': true},
    },
  ],
};

Map<String, dynamic> _operations() => {
      'data': [
        for (final (key, group, name, scopes) in [
          ('workers.view', 'Trabajadores', 'Consultar trabajadores', ['itinerary', 'entity', 'all']),
          ('tracking.drive', 'Recorrido', 'Conducir', ['entity', 'all']),
          ('vehicles.view', 'Vehículos', 'Consultar vehículos', ['entity', 'all']),
        ])
          {
            'type': 'operations',
            'id': key,
            'attributes': {'key': key, 'group': group, 'name': name, 'scopes': scopes},
          },
      ],
    };

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
    }
  }

  Future<_FakeApi> pumpWith(WidgetTester tester, String meFixture, Widget screen, _Handler handler) async {
    final api = _FakeApi(handler);
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'))..httpClientAdapter = api;
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
    await settle(tester);
    return api;
  }

  bool menuEnabled(WidgetTester tester, String label) => tester.widget<ListTile>(find.widgetWithText(ListTile, label)).enabled;

  testWidgets('Trabajadores: la Jefa de Transporte ve los de su Entidad y selecciona varios', (tester) async {
    await pumpWith(tester, 'me_chief', const WorkersScreen(), (r) => r.path == '/workers' ? _json('workers') : null);
    expect(find.text('PRUEBA'), findsWidgets, reason: 'selector de Entidad');
    expect(find.byIcon(Icons.unfold_more), findsOneWidget);
    expect(find.text('Activos'), findsOneWidget);
    expect(find.text('Carlos Luis Chofer Díaz'), findsOneWidget);
    expect(find.text('Teresa Ana Jefa López'), findsOneWidget);

    await tester.longPress(find.text('Carlos Luis Chofer Díaz'));
    await tester.pumpAndSettle();
    expect(find.text('1 seleccionado'), findsOneWidget);
    await tester.tap(find.text('Teresa Ana Jefa López'));
    await tester.pumpAndSettle();
    expect(find.text('2 seleccionados'), findsOneWidget);

    await tester.tap(find.text('Acciones'));
    await tester.pumpAndSettle();
    // Sin workers.register ni workers.deactivate; con roles.assign en su Entidad.
    expect(menuEnabled(tester, 'Registrar persona'), isFalse);
    expect(menuEnabled(tester, 'Desactivar'), isFalse);
    expect(menuEnabled(tester, 'Asignar rol'), isTrue);
    expect(menuEnabled(tester, 'Editar'), isFalse, reason: 'Editar necesita exactamente una');
  });

  testWidgets('Registro por el Administrador: muestra la tarjeta, el usuario y la contraseña', (tester) async {
    final api = await pumpWith(tester, 'me_admin', const WorkersScreen(), (r) => switch ((r.method, r.path)) {
          ('GET', '/entities') => _entities,
          ('GET', '/workers') => _json('workers'),
          ('GET', '/password-suggestion') => _json('password_suggestion'),
          ('GET', '/username-suggestion') => _json('username_suggestion'),
          ('POST', '/workers') => _json('worker_registered'),
          _ => null,
        });
    expect(find.text('Carlos Luis Chofer Díaz'), findsOneWidget);

    await tester.tap(find.text('Acciones'));
    await tester.pumpAndSettle();
    expect(menuEnabled(tester, 'Registrar persona'), isTrue);
    await tester.tap(find.text('Registrar persona'));
    await settle(tester);

    expect(find.text('U6_ztmENoD'), findsOneWidget, reason: 'contraseña propuesta');
    await tester.enterText(find.widgetWithText(TextFormField, 'Primer nombre'), 'Ana');
    await tester.enterText(find.widgetWithText(TextFormField, 'Primer apellido'), 'Gómez');
    await tester.enterText(find.widgetWithText(TextFormField, 'Segundo apellido'), 'Ruiz');
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.widgetWithText(TextFormField, 'ana'), findsOneWidget, reason: 'usuario propuesto');
    await tester.enterText(find.widgetWithText(TextFormField, 'Carné de identidad'), '85031512345');
    await tester.pumpAndSettle();
    expect(find.text('Masculino • 15/03/85'), findsOneWidget);
    await tester.tap(find.text('Tiene teléfono'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Registrar'));
    await settle(tester);

    final post = api.requests.singleWhere((r) => r.method == 'POST' && r.path == '/workers');
    final data = post.body!['data'] as Map;
    expect((data['attributes'] as Map)['identityCard'], '85031512345');
    expect((data['attributes'] as Map)['username'], 'ana');
    expect((data['attributes'] as Map)['hasPhone'], isFalse);
    expect(((data['relationships'] as Map)['entity'] as Map)['data'], {'type': 'entities', 'id': '1'});

    expect(find.text('Persona registrada'), findsOneWidget);
    expect(find.text('Carlos Luis Chofer Díaz'), findsOneWidget);
    expect(find.text('carlos'), findsOneWidget);
    expect(find.text('HBf5Zwj.LG'), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsNWidgets(2));
    expect(find.byIcon(Icons.share), findsNWidgets(2));
  });

  testWidgets('Solicitudes por resolver: por tipo, y rechazar pide el motivo', (tester) async {
    final document = _json('applications');
    for (final a in document['data'] as List) {
      (a['attributes'] as Map)
        ..['status'] = 'pending'
        ..['canResolve'] = true;
    }
    final api = await pumpWith(tester, 'me_admin', const ApplicationsToResolveScreen(), (r) => r.method == 'GET' && r.path == '/applications' ? document : null);
    expect(find.text('Entrar en una Entidad'), findsOneWidget);
    expect(find.text('Itinerario y parada'), findsOneWidget);
    expect(find.text('Roles'), findsOneWidget);
    expect(find.text('Chofer en PRUEBA'), findsOneWidget);

    await tester.longPress(find.text('Chofer en PRUEBA'));
    await tester.pumpAndSettle();
    expect(find.text('1 seleccionada'), findsOneWidget);
    await tester.tap(find.text('Acciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rechazar'));
    await tester.pumpAndSettle();
    expect(find.text('Motivo del rechazo'), findsOneWidget);
    // Sin motivo no se acepta.
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    expect(find.text('Motivo del rechazo'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'No tiene licencia');
    await tester.tap(find.text('Aceptar'));
    await settle(tester);

    final patch = api.requests.singleWhere((r) => r.method == 'PATCH');
    expect(patch.path, '/applications/4');
    expect((patch.body!['data'] as Map)['attributes'], {'status': 'rejected', 'resolutionNote': 'No tiene licencia'});
  });

  testWidgets('Roles: el Administrador es de solo lectura y el editor guarda operaciones y aprobadores', (tester) async {
    final api = await pumpWith(tester, 'me_admin', const RolesAdminScreen(), (r) => switch ((r.method, r.path)) {
          ('GET', '/roles') => _json('roles'),
          ('GET', '/operations') => _operations(),
          ('PATCH', '/roles/3') => {'data': (_json('roles')['data'] as List)[1]},
          _ => null,
        });
    expect(find.text('Administrador'), findsOneWidget);
    expect(find.text('No se puede editar ni eliminar'), findsOneWidget);
    expect(find.text('Trabajador'), findsOneWidget);

    // El Administrador: solo lectura.
    await tester.tap(find.text('Administrador'));
    await settle(tester);
    await tester.tap(find.text('Acciones'));
    await tester.pumpAndSettle();
    expect(menuEnabled(tester, 'Guardar'), isFalse);
    expect(menuEnabled(tester, 'Eliminar'), isFalse);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await settle(tester);

    // Chofer: sus operaciones con su ámbito y el Jefe de Transporte como aprobador.
    await tester.tap(find.text('Chofer'));
    await settle(tester);
    expect(find.text('Consultar trabajadores'), findsOneWidget);
    expect(find.text('Conducir'), findsOneWidget);
    expect(find.text('Su Entidad'), findsWidgets);
    final approver = tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Jefe de Transporte'));
    expect(approver.selected, isTrue);

    await tester.tap(find.text('Acciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    final patch = api.requests.singleWhere((r) => r.method == 'PATCH');
    final attributes = (patch.body!['data'] as Map)['attributes'] as Map;
    expect(attributes['name'], 'Chofer');
    expect(attributes['approverRoleIds'], ['2']);
    expect((attributes['permissions'] as List).any((p) => p['operation'] == 'tracking.drive' && p['scope'] == 'entity'), isTrue);
    expect((attributes['permissions'] as List).length, 6);
  });
}
