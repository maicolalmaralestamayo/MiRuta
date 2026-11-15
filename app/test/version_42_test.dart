import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/core/json_api.dart';
import 'package:mitransporte/core/local_cache.dart';
import 'package:mitransporte/models/models.dart';
import 'package:mitransporte/services/app_settings.dart';
import 'package:mitransporte/services/theme_controller.dart';
import 'package:mitransporte/services/tracking/trip_permissions.dart';
import 'package:mitransporte/services/tracking/trip_window.dart';
import 'package:mitransporte/ui/widgets/app_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Versión 4.2.0 (docs/11 §11.61 y §11.62): ventana de viaje, contador,
/// caché local, tema, ausencias y avisos por fabricante.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Ventana de viaje', () {
    const settings = AppSettings({'anticipacion_viaje': '10min', 'fin_ventana': '5min', 'frecuencia_calculo': '10seg', 'frecuencia_reposo': '15min'});
    final departs = DateTime(2026, 11, 16, 7, 0);
    WindowTrip trip({String status = 'planificado', DateTime? changed, String? state, DateTime? stateAt, String? stop = '7'}) => WindowTrip(
        id: '15', itineraryName: 'XX Aniversario', departsAt: departs, status: status, statusChangedAt: changed, myStopId: stop, myState: state, myStateAt: stateAt);

    test('empieza X antes de la salida', () {
      final slots = TripWindow.slots([trip()], const {}, settings, DateTime(2026, 11, 16, 6, 0));
      expect(slots.single.start, DateTime(2026, 11, 16, 6, 50));
      expect(slots.single.contains(DateTime(2026, 11, 16, 6, 49)), isFalse);
      expect(slots.single.contains(DateTime(2026, 11, 16, 6, 50)), isTrue);
    });

    test('termina Y después del fin del viaje o de su estado definitivo', () {
      final finished = TripWindow.slots([trip(status: 'terminado', changed: DateTime(2026, 11, 16, 7, 40))], const {}, settings, DateTime(2026, 11, 16, 7, 41));
      expect(finished.single.end, DateTime(2026, 11, 16, 7, 45));
      expect(TripWindow.slots([trip(status: 'terminado', changed: DateTime(2026, 11, 16, 7, 40))], const {}, settings, DateTime(2026, 11, 16, 7, 46)), isEmpty);
      final dropped = TripWindow.slots([trip(state: 'dejado', stateAt: DateTime(2026, 11, 16, 7, 20))], const {}, settings, DateTime(2026, 11, 16, 7, 21));
      expect(dropped.single.end, DateTime(2026, 11, 16, 7, 25));
      final done = TripWindow.slots([trip()], {'15': DateTime(2026, 11, 16, 7, 30)}, settings, DateTime(2026, 11, 16, 7, 31));
      expect(done.single.end, DateTime(2026, 11, 16, 7, 35));
    });

    test('sin parada no hay ventana (no viaja)', () {
      expect(TripWindow.slots([trip(stop: null)], const {}, settings, DateTime(2026, 11, 16, 6, 55)), isEmpty);
    });

    test('Z y F con sus mínimos', () {
      expect(settings.windowEvery, const Duration(seconds: 10));
      expect(const AppSettings({'frecuencia_calculo': '1seg'}).windowEvery, const Duration(seconds: 5));
      expect(const AppSettings({'frecuencia_reposo': '5min'}).outsideEvery, const Duration(minutes: 15));
      expect(const AppSettings({}).windowAfter, const Duration(minutes: 5));
    });
  });

  test('contador de la barra: «7 s» y «12:34»', () {
    final now = DateTime(2026, 11, 16, 7);
    expect(countdownText(now.add(const Duration(seconds: 7)), now: now), '7 s');
    expect(countdownText(now.add(const Duration(minutes: 12, seconds: 34)), now: now), '12:34');
    expect(countdownText(now.subtract(const Duration(seconds: 3)), now: now), '0 s');
    expect(countdownText(null), isNull);
  });

  group('Caché local', () {
    test('clave con los parámetros ordenados y archivo estable', () {
      expect(LocalCache.keyFor('/stops', {'sort': 'position', 'filter[itinerary]': '3'}), '/stops?filter[itinerary]=3&sort=position');
      expect(LocalCache.fileName('/me'), LocalCache.fileName('/me'));
      expect(LocalCache.fileName('/me'), isNot(LocalCache.fileName('/me?x=1')));
      expect(LocalCache.fileName('/me'), matches(RegExp(r'^[0-9a-f]{16}\.json$')));
    });

    test('no guarda el tiempo real ni la sincronización', () {
      expect(LocalCache.cacheable('/itineraries'), isTrue);
      expect(LocalCache.cacheable('/trips/15'), isTrue);
      expect(LocalCache.cacheable('/trips/15/live'), isFalse);
      expect(LocalCache.cacheable('/trips/15/passengers'), isFalse);
      expect(LocalCache.cacheable('/sync'), isFalse);
    });

    test('huellas de sync: lo que cambió se vuelve a pedir', () async {
      expect(await LocalCache.compareVersions({'entities': 'a', 'trips': 'b'}), isEmpty);
      expect(await LocalCache.compareVersions({'entities': 'a', 'trips': 'b'}), isEmpty);
      expect(await LocalCache.compareVersions({'entities': 'a', 'trips': 'c'}), {'trips', 'data'});
    });

    test('«Actualizado hace …»', () {
      final now = DateTime(2026, 11, 16, 12);
      expect(agoText(now.subtract(const Duration(seconds: 20)), now: now), 'ahora');
      expect(agoText(now.subtract(const Duration(minutes: 5)), now: now), 'hace 5 min');
      expect(agoText(now.subtract(const Duration(hours: 3)), now: now), 'hace 3 h');
      expect(agoText(now.subtract(const Duration(days: 1)), now: now), 'hace 1 día');
    });
  });

  test('ausencia por itinerarios, indefinida', () {
    final a = Absence.from(Resource(type: 'absences', id: '4', attributes: const {'startsOn': '2026-11-16', 'endsOn': null, 'current': true}, meta: const {
      'absenceTypeName': 'Vacaciones',
      'itineraries': [
        {'id': '1', 'name': 'XX Aniversario', 'entityAbbreviation': 'ESM'},
        {'id': '2', 'name': 'Ruta Playa', 'entityAbbreviation': 'UMIM'},
      ],
    }));
    expect(a.indefinite, isTrue);
    expect(a.itineraryNames, 'XX Aniversario, Ruta Playa');
    expect(a.typeName, 'Vacaciones');
  });

  test('avisos por fabricante', () {
    expect(TripPermissions.manufacturerHintFor('Xiaomi'), contains('Inicio automático'));
    expect(TripPermissions.manufacturerHintFor('HUAWEI'), contains('Huawei'));
    expect(TripPermissions.manufacturerHintFor('OPPO'), contains('Oppo'));
    expect(TripPermissions.manufacturerHintFor('samsung'), contains('nunca se suspenden'));
    expect(TripPermissions.manufacturerHintFor('Nokia'), contains('segundo plano'));
  });

  testWidgets('tema claro, oscuro o automático (se guarda en el teléfono)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: ThemeModeSelector()))));
    expect(ThemeController.mode.value, ThemeMode.system);
    // Un solo botón (docs/11 §11.63) que abre el menú.
    await tester.tap(find.byIcon(Icons.settings_suggest_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oscuro'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(ThemeController.mode.value, ThemeMode.dark);
    expect((await SharedPreferences.getInstance()).getString('app.theme_mode'), 'dark');
    await ThemeController.set(ThemeMode.system);
  });
}
