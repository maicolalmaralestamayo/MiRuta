import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mitransporte/core/api_client.dart';
import 'package:mitransporte/core/json_api.dart';
import 'package:mitransporte/models/models.dart';
import 'package:mitransporte/services/session.dart';
import 'package:mitransporte/ui/home/home_screen.dart';
import 'package:mitransporte/ui/widgets/actions.dart';
import 'package:mitransporte/ui/widgets/app_scaffold.dart';
import 'package:mitransporte/ui/widgets/cards.dart';
import 'package:mitransporte/ui/widgets/entity_selector.dart';
import 'package:mitransporte/ui/widgets/selection.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Resource fixture(String name) =>
    JsonApiDocument.fromJson(jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>).resource;

Widget app(Widget child, {Session? session}) {
  final home = MaterialApp(home: child);
  if (session == null) return home;
  return MultiProvider(providers: [
    ChangeNotifierProvider.value(value: session),
    ChangeNotifierProvider.value(value: session.connection),
  ], child: home);
}

Session sessionFor(String meFixture) {
  final session = Session(ApiClient.withDio(Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'))));
  session.me = Me.from(fixture(meFixture));
  session.state = SessionState.ready;
  return session;
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('carné de identidad (docs/11 §11.2)', () {
    test('fecha de nacimiento, siglo y sexo', () {
      expect(IdentityCard.birthDate('85031512345'), DateTime(1985, 3, 15));
      expect(IdentityCard.birthDate('18030564140'), DateTime(2018, 3, 5), reason: '7.º dígito 6 → 2000');
      expect(IdentityCard.birthDate('99123194567'), DateTime(1899, 12, 31), reason: '7.º dígito 9 → 1800');
      expect(IdentityCard.sex('85031512345'), 'M', reason: 'penúltimo par');
      expect(IdentityCard.sex('90052002130'), 'F', reason: 'penúltimo impar');
    });

    test('no válidos', () {
      expect(IdentityCard.validate(''), isNotNull);
      expect(IdentityCard.validate('1234'), isNotNull);
      expect(IdentityCard.validate('85133112345'), isNotNull, reason: 'mes 13');
      expect(IdentityCard.validate('85023012345'), isNotNull, reason: '30 de febrero');
      expect(IdentityCard.birthDate('30010164140', today: DateTime(2026, 11, 4)), isNull, reason: 'futura');
      expect(IdentityCard.validate('85031512345'), isNull);
    });
  });

  testWidgets('InfoCard: líneas, ✓ al seleccionarla y toque', (tester) async {
    var taps = 0;
    await tester.pumpWidget(app(Scaffold(
      body: InfoCard(images: const [CardImage(icon: Icons.apartment)], title: 'UMIM', lines: const ['Unidad', '50 trabajadores'], selected: true, onTap: () => taps++),
    )));
    expect(find.text('UMIM'), findsOneWidget);
    expect(find.text('50 trabajadores'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('UMIM'));
    expect(taps, 1);
  });

  testWidgets('tarjetas modelo: hijo, Entidad con ↕, sin itinerario, rol', (tester) async {
    final me = Me.from(fixture('me'));
    final membership = me.memberships.first;
    await tester.pumpWidget(app(Scaffold(
      body: ListView(children: [
        UserCard.person(me.person),
        ChildCard(Child.from(fixture('children'))),
        EntityCard(membership.entity, selector: true),
        ItineraryStopCard.membership(me.memberships.last),
        RoleCard.worker(membership.entity),
      ]),
    )));
    expect(find.text('DOS • PRUEBA'), findsOneWidget);
    expect(find.text('Nacimiento 05/03/18'), findsOneWidget);
    expect(find.text('Derecho 31/08/34'), findsOneWidget);
    expect(find.byIcon(Icons.unfold_more), findsOneWidget);
    expect(find.text('Sin itinerario'), findsOneWidget);
    expect(find.text('Trabajador'), findsOneWidget);
  });

  testWidgets('Acciones: menú flotante, en gris sin selección, ✕ al abrirlo', (tester) async {
    final selection = SelectionController();
    var created = 0;
    var edited = 0;
    await tester.pumpWidget(app(AppScaffold(
      title: 'Hijos',
      selection: selection,
      actions: [
        ActionItem(icon: Icons.add, label: 'Crear', onPressed: () => created++),
        const ActionItem.divider(),
        ActionItem(icon: Icons.edit, label: 'Editar', needs: ActionNeeds.one, onPressed: () => edited++),
        ActionItem(icon: Icons.delete, label: 'Eliminar', needs: ActionNeeds.some, destructive: true, onPressed: () {}),
      ],
      body: const SizedBox.expand(),
    )));
    expect(find.text('Acciones'), findsOneWidget);
    expect(find.text('Crear'), findsNothing);
    await tester.tap(find.text('Acciones'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Editar')).enabled, isFalse);
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Crear')).enabled, isTrue);
    await tester.tap(find.text('Editar'));
    expect(edited, 0);
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(find.text('Crear'), findsNothing, reason: 'se cierra al elegir');

    selection.select('1');
    await tester.pump();
    await tester.tap(find.text('Acciones'));
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Editar')).enabled, isTrue);
  });

  testWidgets('selección múltiple: mantener pulsado, «N seleccionados» y ✕', (tester) async {
    final selection = SelectionController();
    final opened = <String>[];
    await tester.pumpWidget(app(AppScaffold(
      title: 'Hijos',
      selection: selection,
      body: SelectableCardList<String>(
        controller: selection,
        sections: const [CardSection(title: 'Con derecho a viajar', items: ['Laura', 'Carlos'])],
        keyOf: (name) => name,
        onOpen: opened.add,
        cardBuilder: (context, name, selected, onTap, onLongPress) => InfoCard(title: name, selected: selected, onTap: onTap, onLongPress: onLongPress),
      ),
    )));
    await tester.tap(find.text('Laura'));
    expect(opened, ['Laura'], reason: 'tocar abre la edición');

    await tester.longPress(find.text('Laura'));
    await tester.pump();
    expect(find.text('1 seleccionado'), findsOneWidget);
    await tester.tap(find.text('Carlos'));
    await tester.pump();
    expect(find.text('2 seleccionados'), findsOneWidget);
    expect(opened, ['Laura'], reason: 'en modo selección tocar marca');
    expect(find.byIcon(Icons.check), findsNWidgets(2));

    await tester.tap(find.byTooltip('Salir de la selección'));
    await tester.pump();
    expect(selection.active, isFalse);
    expect(find.text('Hijos'), findsOneWidget);
  });

  testWidgets('selector de Entidad: hoja «Mis Entidades» con ✓ y elegir otra', (tester) async {
    final session = sessionFor('me');
    await tester.pumpWidget(app(const Scaffold(body: EntitySelector()), session: session));
    expect(find.text('PRUEBA'), findsOneWidget, reason: 'sin elegir: la primera');
    await tester.tap(find.text('PRUEBA'));
    await tester.pumpAndSettle();
    expect(find.text('Mis Entidades'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('Solicitar entrar en otra Entidad'), findsOneWidget);
    expect(find.text('Darme de baja de esta Entidad'), findsOneWidget);
    await tester.tap(find.text('DOS').last);
    await tester.pumpAndSettle();
    expect(session.selectedEntityId, '2');
    expect(find.text('Segunda Entidad'), findsOneWidget);
    expect(await SharedPreferences.getInstance().then((p) => p.getString(Session.selectedEntityKey)), '2', reason: 'se recuerda');
  });

  testWidgets('sin Entidad: tarjeta «Sin Entidad»', (tester) async {
    await tester.pumpWidget(app(const Scaffold(body: EntitySelector()), session: sessionFor('me_admin')));
    expect(find.text('Sin Entidad'), findsOneWidget);
  });

  testWidgets('Inicio: seis botones del mismo tamaño, 3 por fila', (tester) async {
    await tester.pumpWidget(app(const Scaffold(body: HomeButtons())));
    final labels = ['Perfil', 'Hijos', 'Entidades', 'Itinerario', 'Roles', 'Viajes'];
    final sizes = {for (final l in labels) tester.getSize(find.ancestor(of: find.text(l), matching: find.byType(QuickButton)))};
    expect(sizes, hasLength(1));
    final rows = {for (final l in labels) tester.getTopLeft(find.text(l)).dy.round()};
    expect(rows, hasLength(2));
  });
}
