import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/core/api_exception.dart';
import 'package:mitransporte/core/busy_scope.dart';
import 'package:mitransporte/ui/widgets/busy.dart';
import 'package:mitransporte/ui/widgets/common.dart';

/// Reglas de la interfaz (docs/11 §11.56 y §11.65).
void main() {
  Widget host(Widget Function(BuildContext context) builder) => MaterialApp(home: Scaffold(body: Builder(builder: builder)));

  testWidgets('modal simple: ícono, título, pregunta y «Volver» / «Cancelar solicitud»', (tester) async {
    bool? result;
    await tester.pumpWidget(host((context) => TextButton(
          onPressed: () async => result = await confirm(context, 'Cancelar solicitud', '¿Cancelar su solicitud de entrar en ESM?',
              accept: 'Cancelar solicitud', destructive: true, headerIcon: Icons.cancel_outlined, cancel: 'Volver', cancelIcon: Icons.arrow_back),
          child: const Text('abrir'),
        )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    expect(find.text('Volver'), findsOneWidget);
    expect(find.text('Cancelar solicitud'), findsNWidgets(2)); // título y botón
    expect(find.text('Cancelar'), findsNothing);
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('«Salir sin guardar» (4.4.0): Guardar, Salir sin guardar y Cancelar, uno debajo del otro', (tester) async {
    var dirty = false;
    var saved = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => LeaveGuard(
                      dirty: () => dirty,
                      onSave: () async {
                        saved++;
                        return true;
                      },
                      child: const Scaffold(body: Text('formulario'))))),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    dirty = true;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Salir sin guardar'), findsNWidgets(2)); // título y botón
    // Uno debajo del otro: Guardar arriba, Cancelar abajo, a todo el ancho.
    final save = tester.getRect(find.widgetWithText(FilledButton, 'Guardar'));
    final leave = tester.getRect(find.widgetWithText(FilledButton, 'Salir sin guardar'));
    final cancel = tester.getRect(find.widgetWithText(FilledButton, 'Cancelar'));
    expect(save.top < leave.top && leave.top < cancel.top, isTrue);
    expect(save.width, cancel.width);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('formulario'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(saved, 1);
    expect(find.text('formulario'), findsNothing);
  });

  testWidgets('spinner «[Acción] [Objeto]» con «✕ Cancelar»; al cancelar o terminar, sin cintas', (tester) async {
    final request = Completer<void>();
    await tester.pumpWidget(host((context) => TextButton(
          onPressed: () => runAction(context, () async {
            // Lo que hace ApiClient con cada petición dentro de la operación.
            final scope = BusyScope.active!;
            scope.begin();
            try {
              await Future.any([request.future, scope.token.whenCancel.then<void>((_) => throw ApiException.cancelled())]);
            } finally {
              scope.end();
            }
          }, label: progressiveLabel('Actualizar Itinerario')),
          child: const Text('guardar'),
        )));
    await tester.tap(find.text('guardar'));
    await tester.pump();
    expect(find.text('Actualizando Itinerario'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Actualizando Itinerario'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  test('textos de los spinners de las acciones CRUD', () {
    expect(progressiveLabel('Crear Parada'), 'Creando Parada');
    expect(progressiveLabel('Actualizar Viaje: Cancelar'), 'Actualizando Viaje');
    expect(progressiveLabel('Eliminar Itinerario'), 'Eliminando Itinerario');
    expect(progressiveLabel('Consultar Paradas'), 'Consultando Paradas');
    expect(progressiveLabel('Activar ubicación'), isNull);
  });

  test('fuera de la operación (ámbito cerrado) ya no se usa el spinner', () async {
    final scope = BusyScope(onBusyChanged: (_) {});
    late Zone zone;
    await scope.run(() async => zone = Zone.current);
    scope.close();
    zone.run(() => expect(BusyScope.active, isNull));
    expect(CancelToken.isCancel(DioException(requestOptions: RequestOptions())), isFalse);
  });
}
