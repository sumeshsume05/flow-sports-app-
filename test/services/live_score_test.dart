import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flow_sports_app/services/firestore_service.dart';
import 'package:flutter_test/flutter_test.dart';

late FakeFirebaseFirestore db;
late FirestoreService fs;

Future<void> seed({int? a, int? b}) async {
  db = FakeFirebaseFirestore();
  fs = FirestoreService(firestore: db);
  await db.collection('matches').doc('m1').set({'scoreA': a, 'scoreB': b, 'status': 'live'});
}

Future<Map<String, dynamic>> match() async => (await db.collection('matches').doc('m1').get()).data()!;
Future<List<Map<String, dynamic>>> log() async =>
    (await db.collection('matches').doc('m1').collection('pointLog').get()).docs.map((d) => d.data()).toList();

void main() {
  test('the new score comes back at once, before the write is acknowledged', () async {
    await seed(a: 4, b: 2);
    final r = fs.adjustLiveScore('m1', team: 'A', delta: 1, currentA: 4, currentB: 2);
    expect((r.scoreA, r.scoreB), (5, 2));
    await r.saved;
    expect((await match())['scoreA'], 5);
  });

  test('writes the point log in the same batch, with the resulting score', () async {
    await seed(a: 0, b: 0);
    await fs.adjustLiveScore('m1', team: 'B', delta: 1, currentA: 0, currentB: 0).saved;
    final entries = await log();
    expect(entries.single['team'], 'B');
    expect([entries.single['scoreA'], entries.single['scoreB']], [0, 1]);
    expect(entries.single['createdAt'], isNotNull);
  });

  test('works from an empty (null) score', () async {
    await seed();
    await fs.adjustLiveScore('m1', team: 'A', delta: 1, currentA: 0, currentB: 0).saved;
    expect((await match())['scoreA'], 1);
  });

  test('a − at 0 writes nothing', () async {
    await seed(a: 0, b: 3);
    final r = fs.adjustLiveScore('m1', team: 'A', delta: -1, currentA: 0, currentB: 3);
    expect((r.scoreA, r.scoreB), (0, 3));
    await r.saved;
    expect(await log(), isEmpty);
  });

  test('two admins tapping from the same starting score both count', () async {
    await seed(a: 10, b: 10);
    final one = fs.adjustLiveScore('m1', team: 'A', delta: 1, currentA: 10, currentB: 10);
    final two = fs.adjustLiveScore('m1', team: 'A', delta: 1, currentA: 10, currentB: 10);
    await Future.wait([one.saved, two.saved]);
    expect((await match())['scoreA'], 12, reason: 'increments add up; a plain "set to 11" would lose one');
    expect((await log()).length, 2);
  });

  test('taking a tap back is a new log entry, not an edit', () async {
    await seed(a: 0, b: 0);
    await fs.adjustLiveScore('m1', team: 'A', delta: 1, currentA: 0, currentB: 0).saved;
    await fs.adjustLiveScore('m1', team: 'A', delta: -1, currentA: 1, currentB: 0).saved;
    expect((await match())['scoreA'], 0);
    expect((await log()).length, 2);
  });
}
