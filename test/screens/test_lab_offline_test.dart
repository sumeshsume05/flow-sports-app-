import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flow_sports_app/screens/admin/admin_test_lab_screen.dart';
import 'package:flow_sports_app/services/test_lab_service.dart';
import 'package:flow_sports_app/state/connectivity_state.dart';
import 'package:flow_sports_app/state/season_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Reported on the phone: with airplane mode on, the Test Lab looked empty
// ("Create test teams") although the test data was there — the server-side
// count never answers offline. Now it counts the saved copy and says so.

late FakeFirebaseFirestore db;

Future<void> _seed() async {
  db = FakeFirebaseFirestore();
  await db.collection('config').doc('activeSeason').set({'seasonId': '2026'});
  for (var i = 0; i < 3; i++) {
    await db.collection('teams').add(
        {'sport': 'cricket', 'category': 'test', 'season': '2026', 'name': 'Team $i'});
  }
  for (var i = 0; i < 2; i++) {
    await db.collection('matches').add({
      'sport': 'cricket', 'category': 'test', 'season': '2026', 'stage': 'league', 'matchNumber': i,
      'label': 'M$i', 'matchCode': 'L$i', 'status': 'upcoming', 'notifyTopic': '',
      'teamA': {'teamId': 'a', 'name': 'A'}, 'teamB': {'teamId': 'b', 'name': 'B'},
    });
  }
  // A real (non-test) team that must never be counted.
  await db.collection('teams').add({'sport': 'cricket', 'category': 'boys', 'season': '2026', 'name': 'Real'});
}

/// A server count that never answers, like a phone with no signal.
Future<int> _hangs(Query<Map<String, dynamic>> q) => Completer<int>().future;
Future<int> _fails(Query<Map<String, dynamic>> q) async => throw StateError('unavailable');

void main() {
  group('TestLabService.counts', () {
    test('online: the server count, not marked as a saved copy', () async {
      await _seed();
      final c = await TestLabService(firestore: db, serverCount: (q) async => (await q.get()).size)
          .counts('cricket', '2026');
      expect((c.teams, c.matches, c.fromCache), (3, 2, false));
    });

    test('the server count fails: the saved copy is counted instead', () async {
      await _seed();
      final c = await TestLabService(firestore: db, serverCount: _fails).counts('cricket', '2026');
      expect((c.teams, c.matches, c.fromCache), (3, 2, true));
    });

    test('the server never answers: falls back after the wait', () async {
      await _seed();
      final c = await TestLabService(
        firestore: db,
        serverCount: _hangs,
        serverCountTimeout: const Duration(milliseconds: 50),
      ).counts('cricket', '2026');
      expect((c.teams, c.matches, c.fromCache), (3, 2, true));
    });

    test('the phone knows it is offline: no wait at all', () async {
      await _seed();
      final c = await TestLabService(firestore: db, serverCount: _hangs).counts('cricket', '2026', offline: true);
      expect(c.fromCache, isTrue);
      expect(c.teams, 3);
    });

    test('real teams are never counted', () async {
      await _seed();
      final c = await TestLabService(firestore: db, serverCount: _fails).counts('cricket', '2026');
      expect(c.teams, 3);
    });
  });

  group('Test Lab screen', () {
    Future<ConnectivityState> open(WidgetTester tester, {required bool offline, required TestLabService service}) async {
      tester.view.physicalSize = const Size(822, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final connectivity = ConnectivityState.fixed(offline: offline);
      final season = SeasonState(firestore: db);
      addTearDown(season.dispose);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ConnectivityState>.value(value: connectivity),
          ChangeNotifierProvider<SeasonState>.value(value: season),
        ],
        child: MaterialApp(home: AdminTestLabScreen(service: service)),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      return connectivity;
    }

    testWidgets('offline: still shows the saved test data and pauses changes', (tester) async {
      await _seed();
      await open(tester,
          offline: true, service: TestLabService(firestore: db, serverCount: _hangs));

      // Cricket's numbers are there — not the empty "Create test teams" start.
      // (Badminton genuinely has no test data in this fixture.)
      expect(find.text('3 teams · 2 matches'), findsOneWidget);
      expect(find.text('Replace with this scenario'), findsOneWidget);
      expect(find.text('Create test teams'), findsOneWidget);
      expect(find.textContaining('copy saved on your phone'), findsWidgets);
      // Changing data is paused.
      final replace = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Replace with this scenario').first);
      expect(replace.onPressed, isNull);
      final reset = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Reset test data').first);
      expect(reset.onPressed, isNull);
    });

    testWidgets('online: changes are available; going offline pauses them, coming back resumes', (tester) async {
      await _seed();
      final connectivity = await open(tester,
          offline: false, service: TestLabService(firestore: db, serverCount: (q) async => (await q.get()).size));
      final replace = find.widgetWithText(FilledButton, 'Replace with this scenario').first;
      expect(tester.widget<FilledButton>(replace).onPressed, isNotNull);
      expect(find.textContaining('copy saved on your phone'), findsNothing);

      connectivity.setOffline(true);
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.widget<FilledButton>(replace).onPressed, isNull);
      expect(find.textContaining('copy saved on your phone'), findsWidgets);

      connectivity.setOffline(false);
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.widget<FilledButton>(replace).onPressed, isNotNull);
      expect(find.textContaining('copy saved on your phone'), findsNothing);
    });

    testWidgets('opened offline, then the network returns: the numbers are re-read and changes unlock', (tester) async {
      await _seed();
      var serverUp = false;
      final service = TestLabService(
        firestore: db,
        serverCount: (q) => serverUp ? q.get().then((s) => s.size) : Completer<int>().future,
        serverCountTimeout: const Duration(milliseconds: 50),
      );
      final connectivity = await open(tester, offline: true, service: service);
      final replace = find.widgetWithText(FilledButton, 'Replace with this scenario').first;
      expect(tester.widget<FilledButton>(replace).onPressed, isNull);
      expect(find.textContaining('copy saved on your phone'), findsWidgets);

      serverUp = true;
      connectivity.setOffline(false);
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.widget<FilledButton>(replace).onPressed, isNotNull);
      expect(find.textContaining('copy saved on your phone'), findsNothing);
    });

    testWidgets('nothing readable at all: says so and does not pretend there is no data', (tester) async {
      db = FakeFirebaseFirestore();
      await db.collection('config').doc('activeSeason').set({'seasonId': '2026'});
      // Both the server count and the saved copy fail.
      final failing = TestLabService(firestore: _ThrowingOnCache(db), serverCount: _fails);
      await open(tester, offline: true, service: failing);
      expect(find.textContaining('Could not read the test data'), findsWidgets);
      expect(find.text('Create test teams'), findsWidgets);
      final create = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create test teams').first);
      expect(create.onPressed, isNull, reason: 'with unknown data the create button must stay locked');
    });
  });
}

/// A Firestore whose saved-copy reads fail, for the "nothing readable" case.
class _ThrowingOnCache extends FakeFirebaseFirestore {
  _ThrowingOnCache(FakeFirebaseFirestore base);

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) => throw StateError('no saved copy');
}
