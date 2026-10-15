import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/match_rules_stamp.dart';
import 'package:flow_sports_app/core/cricket/tournament_plan.dart';
import 'package:flow_sports_app/screens/viewer/standings_screen.dart';
import 'package:flow_sports_app/services/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The viewer's cricket points table: ranked by points, wins and net run rate,
// with the NRR shown, and the qualifier line taken from the tournament plan.

const _rules = CricketRules(overs: 5);
late FakeFirebaseFirestore db;

Future<void> _team(String id, {String? section}) => db.collection('teams').doc(id).set({
      'sport': 'cricket', 'category': 'boys', 'season': '2026', 'name': 'Team $id',
      'section': ?section,
    });

Map<String, dynamic> _inn(String side, int runs) => {
      'batting': side, 'strikerId': 'x', 'nonStrikerId': 'y', 'maxOvers': null,
      'runs': runs, 'wickets': 2, 'legalBalls': 30, 'ended': true, 'allOut': false,
    };

Future<void> _played(String id, String a, String b, int ra, int rb) => db.collection('matches').doc(id).set({
      'sport': 'cricket', 'category': 'boys', 'season': '2026', 'stage': 'league', 'matchNumber': 1,
      'label': id, 'matchCode': id, 'notifyTopic': '', 'status': 'completed',
      'teamA': {'teamId': a, 'name': 'Team $a'}, 'teamB': {'teamId': b, 'name': 'Team $b'},
      'scoreA': ra, 'scoreB': rb, 'result': ra > rb ? 'teamA' : (ra < rb ? 'teamB' : 'tie'),
      'rules': _rules.toMap(), 'innings': [_inn('A', ra), _inn('B', rb)],
    });

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(822, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: StandingsScreen(
      sport: 'cricket',
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

  testWidgets('shows the cricket table: order, W/L and net run rate', (tester) async {
    for (final t in ['a', 'b', 'c']) {
      await _team(t);
    }
    await _played('m1', 'a', 'b', 60, 30);
    await _played('m2', 'a', 'c', 40, 38);
    await _played('m3', 'b', 'c', 50, 20);
    await _open(tester);

    final names = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    expect(names.indexOf('Team a') < names.indexOf('Team b'), isTrue);
    expect(names.indexOf('Team b') < names.indexOf('Team c'), isTrue);
    expect(find.textContaining('NRR +'), findsWidgets);
    expect(find.textContaining('NRR −'), findsWidgets);
    expect(find.textContaining('Scored'), findsNothing, reason: 'cricket shows NRR, not "points scored"');
    expect(find.text('4'), findsWidgets); // a's points
  });

  testWidgets('the tournament plan decides the qualifier line: 2 qualify', (tester) async {
    for (final t in ['a', 'b', 'c']) {
      await _team(t);
    }
    // a beats b and c the same way; b and c are dead level for 2nd and 3rd.
    await _played('m1', 'a', 'b', 40, 30);
    await _played('m2', 'a', 'c', 40, 30);
    await db
        .collection('config')
        .doc(cricketPlanDocId('boys', '2026'))
        .set(const CricketTournamentConfig(qualifiers: 2).toMap());
    await _open(tester);
    expect(find.textContaining('top-2 cutoff'), findsOneWidget);
  });

  testWidgets('without a plan the default is the top 4', (tester) async {
    for (final t in ['a', 'b', 'c']) {
      await _team(t);
    }
    await _played('m1', 'a', 'b', 40, 30);
    await _played('m2', 'a', 'c', 40, 30);
    await _open(tester);
    expect(find.textContaining('top-4 cutoff'), findsOneWidget);
  });

  testWidgets('no tie warning before anything is played', (tester) async {
    for (final t in ['a', 'b']) {
      await _team(t);
    }
    await _open(tester);
    expect(find.textContaining('tied on points'), findsNothing);
  });

  testWidgets('sections: each section has its own table', (tester) async {
    await _team('a', section: 'A');
    await _team('b', section: 'A');
    await _team('c', section: 'B');
    await _team('d', section: 'B');
    await _played('m1', 'a', 'b', 50, 30);
    await _played('m2', 'c', 'd', 30, 50);
    await _open(tester);
    expect(find.text('Section A'), findsOneWidget);
    expect(find.text('Section B'), findsOneWidget);
    expect(find.textContaining('NRR'), findsNWidgets(4));
  });
}
