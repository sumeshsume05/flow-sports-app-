import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flow_sports_app/screens/viewer/standings_screen.dart';
import 'package:flow_sports_app/services/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The viewer's league table: no "tied" warning before anyone has played, and
// the cutoff it talks about follows the bracket the admin generated.

late FakeFirebaseFirestore db;

Future<void> _team(String id) => db.collection('teams').doc(id).set(
    {'sport': 'badminton', 'category': 'boys', 'season': '2026', 'name': 'Team $id'});

Future<void> _league(String id, String a, String b, {int? sa, int? sb}) => db.collection('matches').doc(id).set({
      'sport': 'badminton', 'category': 'boys', 'season': '2026', 'stage': 'league', 'matchNumber': 1,
      'label': id, 'matchCode': id, 'notifyTopic': '',
      'status': sa == null ? 'upcoming' : 'completed',
      'teamA': {'teamId': a, 'name': 'Team $a'}, 'teamB': {'teamId': b, 'name': 'Team $b'},
      'scoreA': sa, 'scoreB': sb,
      'result': sa == null ? null : (sa == sb ? 'tie' : (sa > sb! ? 'teamA' : 'teamB')),
    });

Future<void> _knockout(String id, int seedA, int seedB) => db.collection('matches').doc(id).set({
      'sport': 'badminton', 'category': 'boys', 'season': '2026', 'stage': 'knockout', 'matchNumber': 9,
      'label': id, 'matchCode': id, 'notifyTopic': '', 'status': 'upcoming',
      'teamA': {'teamId': null, 'name': null}, 'teamB': {'teamId': null, 'name': null},
      'teamASource': {'type': 'seed', 'seed': seedA, 'matchCode': null},
      'teamBSource': {'type': 'seed', 'seed': seedB, 'matchCode': null},
    });

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(822, 1800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: StandingsScreen(
      sport: 'badminton',
      category: 'boys',
      season: '2026',
      service: FirestoreService(firestore: db),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  setUp(() => db = FakeFirebaseFirestore());

  testWidgets('before any match is played there is no tie warning', (tester) async {
    for (final t in ['a', 'b', 'c', 'd', 'e']) {
      await _team(t);
    }
    await _league('m1', 'a', 'b');
    await _open(tester);
    expect(find.textContaining('tied on points'), findsNothing);
    expect(find.text('Team a'), findsOneWidget);
  });

  testWidgets('a real tie at the cutoff is warned about, naming the default top 4', (tester) async {
    for (final t in ['a', 'b', 'c', 'd', 'e']) {
      await _team(t);
    }
    // d and e both have 2 points and 15 scored; a, b, c are clear above.
    await _league('m1', 'a', 'd', sa: 21, sb: 15);
    await _league('m2', 'b', 'e', sa: 21, sb: 15);
    await _league('m3', 'c', 'd', sa: 21, sb: 10);
    await _league('m4', 'c', 'e', sa: 21, sb: 10);
    await _league('m5', 'd', 'e', sa: 15, sb: 15);
    await _open(tester);
    expect(find.textContaining('top-4 cutoff'), findsOneWidget);
  });

  testWidgets('with a 2-team bracket the cutoff is top 2', (tester) async {
    for (final t in ['a', 'b', 'c']) {
      await _team(t);
    }
    await _league('m1', 'a', 'b', sa: 21, sb: 15);
    await _league('m2', 'a', 'c', sa: 21, sb: 15);
    await _league('m3', 'b', 'c', sa: 21, sb: 15); // a: 4, b: 2, c: 0 → no tie
    await _knockout('KOF', 1, 2);
    await _open(tester);
    expect(find.textContaining('tied on points'), findsNothing);

    // Now make b and c level at the top-2 cutoff.
    await db.collection('matches').doc('m3').update({'scoreA': 15, 'scoreB': 15, 'result': 'tie'});
    await db.collection('matches').doc('m1').update({'scoreA': 21, 'scoreB': 15});
    await _open(tester);
    // b: 1 pt (tie with c) , c: 1 pt?  a beat both, so b and c are level on points and scored.
    expect(find.textContaining('top-2 cutoff'), findsOneWidget);
  });
}
