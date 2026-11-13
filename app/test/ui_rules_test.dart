import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/core/api_exception.dart';
import 'package:mitransporte/core/busy_scope.dart';
import 'package:mitransporte/ui/widgets/common.dart';

/// Reglas de la interfaz de la 4.1.0 (docs/11 §11.56).
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

  testWidgets('«Salir sin guardar» solo si hay cambios: Cancelar sigue en el formulario, Salir sale', (tester) async {
    var dirty = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeaveGuard(dirty: () => dirty, child: const Scaffold(body: Text('formulario'))))),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    dirty = true;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Salir sin guardar'), findsOneWidget);
    expect(find.text('¿Salir? Los cambios no se guardarán.'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('formulario'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salir'));
    await tester.pumpAndSettle();
    expect(find.text('formulario'), findsNothing);
  });

  testWidgets('spinner que bloquea con «Cancelar»: «Operación cancelada»', (tester) async {
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
          }, success: 'Itinerario actualizado'),
          child: const Text('guardar'),
        )));
    await tester.tap(find.text('guardar'));
    await tester.pump();
    expect(find.text('Conectando con el servidor…'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Conectando con el servidor…'), findsNothing);
    expect(find.text('Operación cancelada'), findsOneWidget);
  });

  testWidgets('al terminar, el mensaje escueto del resultado', (tester) async {
    await tester.pumpWidget(host((context) => TextButton(
          onPressed: () => runAction(context, () async {}, success: 'Itinerario creado'),
          child: const Text('crear'),
        )));
    await tester.tap(find.text('crear'));
    await tester.pumpAndSettle();
    expect(find.text('Itinerario creado'), findsOneWidget);
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
