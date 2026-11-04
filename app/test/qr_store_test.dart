import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/services/qr/qr_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cola sin conexión: formato de POST /offline-scans', () async {
    final at = DateTime.utc(2026, 11, 3, 22, 10, 4);
    await QrStore.enqueue(purpose: 'boarding', qr: 'MR1.x', scannedAt: at, label: 'Ana', tripLegId: '81', childIds: ['4']);
    await QrStore.enqueue(purpose: 'itinerary_assignment', qr: 'MRP1.y', scannedAt: at, label: 'Luis', itineraryId: '3', stopId: '17');
    final items = await QrStore.queue();
    expect(items, hasLength(2));
    expect(await QrStore.pendingCount(), 2);
    final boarding = items.first.toRequest();
    expect(boarding['type'], 'offline-scans');
    expect(boarding['lid'], startsWith('b-'));
    expect(boarding['attributes'], {'purpose': 'boarding', 'qr': 'MR1.x', 'scannedAt': '2026-11-03T22:10:04.000Z', 'childIds': ['4'], 'allowOutsider': false});
    expect(boarding['relationships'], {'tripLeg': {'data': {'type': 'trip-legs', 'id': '81'}}});
    final assignment = items.last.toRequest();
    expect((assignment['attributes'] as Map).containsKey('childIds'), isFalse);
    expect(assignment['relationships'], {
      'itinerary': {'data': {'type': 'itineraries', 'id': '3'}},
      'stop': {'data': {'type': 'stops', 'id': '17'}},
    });

    await QrStore.retry(items.first.lid, allowOutsider: true);
    expect((await QrStore.queue()).first.allowOutsider, isTrue);
    await QrStore.remove(items.last.lid);
    expect(await QrStore.queue(), hasLength(1));
  });

  test('códigos usados y subidas del trayecto', () async {
    await QrStore.markNonceUsed('12:a1b2c3d4e5f60718');
    expect(await QrStore.usedNonces(), contains('12:a1b2c3d4e5f60718'));
    await QrStore.addLegBoarding('81', userId: '30', printed: true, childIds: ['4']);
    await QrStore.addLegBoarding('81', userId: '12', printed: false);
    final leg = await QrStore.legBoardings('81');
    expect(leg.userIds, {'30', '12'});
    expect(leg.printedUserIds, {'30'});
    expect(leg.childIds, {'4'});
  });

  test('lista sin conexión', () async {
    await QrStore.saveRoster('1', {
      'generatedAt': '2026-11-04T10:00:00+00:00',
      'workers': [
        {'workerId': '30', 'userId': '12', 'fullName': 'Maicol Almarales', 'sex': 'M', 'itineraryId': '3', 'stopId': '17', 'printedQrVersion': null},
      ],
      'children': [
        {'childId': '4', 'fullName': 'Ana Almarales', 'sex': 'F', 'eligibleUntil': '2034-08-31', 'parentUserIds': ['12']},
      ],
    });
    final roster = (await QrStore.roster('1'))!;
    expect(roster.worker('12')!.fullName, 'Maicol Almarales');
    expect(roster.worker('12')!.printedQrVersion, isNull);
    expect(roster.childrenOf('12').single.childId, '4');
    final (worker, found) = await QrStore.findWorker('12', entityId: '2');
    expect(worker?.workerId, '30');
    expect(found?.entityId, '1');
  });
}
