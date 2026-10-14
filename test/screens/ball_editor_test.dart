import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flow_sports_app/core/cricket/cricket_event.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/innings_replay.dart';
import 'package:flow_sports_app/models/player.dart';
import 'package:flow_sports_app/screens/admin/admin_cricket_scoring_screen.dart';
import 'package:flow_sports_app/screens/admin/cricket_scoring/scoring_controller.dart';
import 'package:flow_sports_app/services/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// One test per option of the Edit-ball screen: drive the real screen with taps
// and check what is stored AND what the replay makes of it (score, strike,
// legal balls, free hit, wickets).

const _rules = CricketRules(
  overs: 3,
  lastManStands: false,
  maxOversPerBowler: null,
  legByesAllowed: true,
  allowedWickets: CricketRules.allWickets,
);

late FakeFirebaseFirestore db;
late CricketScoringController c;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Seeds a started innings (A1 on strike, A2 at the other end, B1 bowling)
/// with [balls] already scored, and opens the screen.
Future<void> _open(WidgetTester tester, List<CricketEvent> balls) async {
  db = FakeFirebaseFirestore();
  List<Map<String, dynamic>> players(String p) =>
      [for (var i = 1; i <= 4; i++) Player(id: '$p$i', name: '${p.toUpperCase()}$i').toMap()];
  await db.collection('teams').doc('tA').set({'sport': 'cricket', 'category': 'boys', 'season': '2026', 'name': 'Reds', 'players': players('a')});
  await db.collection('teams').doc('tB').set({'sport': 'cricket', 'category': 'boys', 'season': '2026', 'name': 'Blues', 'players': players('b')});
  await db.collection('matches').doc('m1').set({
    'sport': 'cricket', 'category': 'boys', 'season': '2026', 'stage': 'league', 'matchNumber': 1,
    'label': 'Match 1', 'matchCode': 'L1', 'status': 'live', 'notifyTopic': '',
    'teamA': {'teamId': 'tA', 'name': 'Reds'}, 'teamB': {'teamId': 'tB', 'name': 'Blues'},
    'rules': _rules.toMap(),
    'lineupA': ['a1', 'a2', 'a3', 'a4'], 'lineupB': ['b1', 'b2', 'b3', 'b4'],
    'toss': {'winner': 'A', 'elected': 'bat'},
    'innings': [{'batting': 'A', 'strikerId': 'a1', 'nonStrikerId': 'a2', 'maxOvers': null}],
  });
  tester.view.physicalSize = const Size(822, 4400); // tall, so the whole sheet is built at once
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  c = CricketScoringController('m1', service: FirestoreService(firestore: db));
  addTearDown(c.dispose);
  await tester.pumpWidget(MaterialApp(home: AdminCricketScoringScreen(matchId: 'm1', controller: c)));
  await _settle(tester);
  for (final e in balls) {
    await tester.runAsync(() => c.addBall((s) => e.copyWith(seq: s)));
    await _settle(tester);
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    final sheet = find.byType(Scrollable).last;
    try {
      await tester.scrollUntilVisible(f, 150, scrollable: sheet);
    } on StateError {
      await tester.scrollUntilVisible(f, -150, scrollable: sheet);
    }
  }
  await tester.ensureVisible(f);
  await tester.tap(f, warnIfMissed: false);
  await _settle(tester);
}

/// Opens "Edit ball" for the [index]-th ball (0-based) of the innings.
Future<void> _openEditor(WidgetTester tester, int index) async {
  // (After a save the ball list is still showing; from the scoring screen open it first.)
  if (find.byTooltip('All balls — edit').evaluate().isNotEmpty) {
    await _tap(tester, find.byTooltip('All balls — edit'));
  }
  await _tap(tester, find.byType(ListTile).at(index));
  expect(find.textContaining('Edit ball —'), findsOneWidget);
}

Future<void> _save(WidgetTester tester) => _tap(tester, find.text('Save ball'));

Future<List<Map<String, dynamic>>> _stored(WidgetTester tester) async => (await tester.runAsync(() async =>
        (await db.collection('matches').doc('m1').collection('balls').orderBy('seq').get()).docs.map((d) => d.data()).toList()))!;

dynamic get _r => c.state!.current!.result;

CricketEvent _bat(int runs, {Boundary b = Boundary.none}) => CricketEvent.bat(0, 'b1', runs, boundary: b);

void main() {
  _clarityTests();
  group('Delivery', () {
    testWidgets('Normal → Wide: one wide run, not a legal ball, strike does not change', (tester) async {
      await _open(tester, [_bat(1), _bat(0), _bat(0)]); // ball 1 is a single: A2 faces balls 2-3
      expect(_r.balls[1].strikerId, 'a2');
      await _openEditor(tester, 0);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Wide'));
      await _save(tester);
      final first = (await _stored(tester)).first;
      expect([first['delivery'], first['runType'], first['runs']], ['wide', 'none', 0]);
      expect(_r.runs, 1); // the wide itself
      expect(_r.legalBalls, 2, reason: 'a wide is not a counted ball');
      expect(_r.extras.wides, 1);
      expect(_r.balls[1].strikerId, 'a1', reason: 'no single was run, so A1 still faces');
    });

    testWidgets('Normal → No ball: a free hit follows', (tester) async {
      await _open(tester, [_bat(0), _bat(0)]);
      await _openEditor(tester, 0);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'No ball'));
      await _save(tester);
      expect(_r.extras.noBalls, 1);
      expect(_r.balls[1].freeHit, isTrue, reason: 'the ball after the no-ball is a free hit');
      expect(_r.legalBalls, 1);
    });

    testWidgets('Normal → Dead ball: no runs, not counted, any wicket removed', (tester) async {
      await _open(tester, [_bat(4, b: Boundary.four), _bat(1)]);
      await _openEditor(tester, 0);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Dead ball'));
      await _save(tester);
      final first = (await _stored(tester)).first;
      expect([first['delivery'], first['runs'], first['boundary']], ['deadBall', 0, 'none']);
      expect(_r.runs, 1);
      expect(_r.legalBalls, 1);
    });

    testWidgets('Normal ↔ No ball keeps the bat runs (both can have runs off the bat)', (tester) async {
      await _open(tester, [_bat(2), _bat(0)]);
      await _openEditor(tester, 0);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'No ball'));
      await _save(tester);
      final first = (await _stored(tester)).first;
      expect([first['delivery'], first['runType'], first['runs']], ['noBall', 'bat', 2]);
      expect(_r.runs, 3); // 1 no-ball + 2 off the bat
      expect(_r.batters['a1']!.runs, 2);
    });

    testWidgets('a four edited into a Wide starts fresh: just the wide, no boundary left behind', (tester) async {
      await _open(tester, [_bat(4, b: Boundary.four), _bat(0)]);
      await _openEditor(tester, 0);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Wide'));
      await _save(tester);
      final first = (await _stored(tester)).first;
      expect([first['delivery'], first['runs'], first['boundary']], ['wide', 0, 'none']);
      expect(_r.runs, 1);
      expect(_r.batters['a1']!.fours, 0);
    });

    testWidgets('Wide → Normal puts the ball back as a counted ball', (tester) async {
      await _open(tester, [CricketEvent.wide(0, 'b1'), _bat(0)]);
      expect(_r.legalBalls, 1);
      await _openEditor(tester, 0);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Normal'));
      await _save(tester);
      expect(_r.legalBalls, 2);
      expect(_r.extras.wides, 0);
    });
  });

  group('Runs (None / Off the bat / Byes / Leg byes)', () {
    testWidgets('Off the bat → Byes: team gets the runs, the batter does not', (tester) async {
      await _open(tester, [_bat(1)]);
      await _openEditor(tester, 0);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Byes'));
      await _save(tester);
      expect(_r.runs, 1);
      expect(_r.batters['a1']!.runs, 0);
      expect(_r.extras.byes, 1);
      expect(_r.bowlers['b1']!.runsConceded, 0, reason: 'byes are not charged to the bowler');
    });

    testWidgets('Leg byes work the same way', (tester) async {
      await _open(tester, [_bat(2)]);
      await _openEditor(tester, 0);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Leg byes'));
      await _save(tester);
      expect(_r.extras.legByes, 2);
      expect(_r.batters['a1']!.runs, 0);
    });

    testWidgets('+ and − change the runs; None sets them to 0', (tester) async {
      await _open(tester, [_bat(1)]);
      await _openEditor(tester, 0);
      await _tap(tester, find.widgetWithIcon(IconButton, Icons.add));
      await _tap(tester, find.widgetWithIcon(IconButton, Icons.add));
      await _save(tester);
      expect(_r.runs, 3);
      expect(_r.batters['a1']!.runs, 3);
      await _openEditor(tester, 0);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'None'));
      await _save(tester);
      expect(_r.runs, 0);
    });

    testWidgets('a dot ball edited to 3 swaps the strike (odd runs run)', (tester) async {
      await _open(tester, [_bat(0), _bat(0)]);
      await _openEditor(tester, 0);
      for (var i = 0; i < 3; i++) {
        await _tap(tester, find.widgetWithIcon(IconButton, Icons.add));
      }
      await _save(tester);
      expect((await _stored(tester)).first['runType'], 'bat', reason: 'adding runs to a dot makes them bat runs');
      expect(_r.balls[1].strikerId, 'a2');
    });
  });

  group('Reached the boundary?', () {
    testWidgets('Four / Six set the runs; the strike does not change', (tester) async {
      await _open(tester, [_bat(1), _bat(0)]);
      await _openEditor(tester, 0);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Four'));
      await _save(tester);
      var first = (await _stored(tester)).first;
      expect([first['runs'], first['boundary']], [4, 'four']);
      expect(_r.batters['a1']!.fours, 1);
      expect(_r.balls[1].strikerId, 'a1', reason: 'a boundary is not run, so no swap');

      await _openEditor(tester, 0);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Six'));
      await _save(tester);
      first = (await _stored(tester)).first;
      expect([first['runs'], first['boundary']], [6, 'six']);
      expect(_r.batters['a1']!.sixes, 1);
    });

    testWidgets('Four → No keeps the 4 runs but now they were run (even → same batter)', (tester) async {
      await _open(tester, [_bat(4, b: Boundary.four), _bat(0)]);
      await _openEditor(tester, 0);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'No').first);
      await _save(tester);
      expect(_r.runs, 4);
      expect(_r.batters['a1']!.fours, 0, reason: 'no longer counted as a four');
      expect(_r.balls[1].strikerId, 'a1', reason: 'four runs run = even, no swap');
    });
  });

  group('Runs actually run were different (overthrows)', () {
    testWidgets('a four with one run actually run swaps the strike', (tester) async {
      await _open(tester, [_bat(4, b: Boundary.four), _bat(0)]);
      expect(_r.balls[1].strikerId, 'a1');
      await _openEditor(tester, 0);
      await _tap(tester, find.byType(SwitchListTile).first);
      expect(find.text('Runs run:'), findsOneWidget);
      // starts at 0 (boundary); make it 1
      await _tap(tester, find.widgetWithIcon(IconButton, Icons.add).last);
      await _save(tester);
      final first = (await _stored(tester)).first;
      expect(first['completedRunsOverride'], 1);
      expect(_r.runs, 4, reason: 'the team still gets the 4');
      expect(_r.balls[1].strikerId, 'a2', reason: 'one run was physically run, so the batters crossed');
    });

    testWidgets('switching it off again removes the override', (tester) async {
      await _open(tester, [CricketEvent(seq: 0, bowlerId: 'b1', runType: RunType.bat, runs: 4, boundary: Boundary.four, completedRunsOverride: 1), _bat(0)]);
      expect(_r.balls[1].strikerId, 'a2');
      await _openEditor(tester, 0);
      await _tap(tester, find.byType(SwitchListTile).first);
      await _save(tester);
      expect((await _stored(tester)).first['completedRunsOverride'], isNull);
      expect(_r.balls[1].strikerId, 'a1');
    });
  });

  group('Bowler', () {
    testWidgets('changing the bowler of a ball is stored (and flagged if it splits an over)', (tester) async {
      await _open(tester, [_bat(0), _bat(0)]);
      await _openEditor(tester, 0);
      await _tap(tester, find.byType(DropdownButtonFormField<String>).first);
      await _tap(tester, find.text('B2').last);
      await _save(tester);
      expect((await _stored(tester)).first['bowlerId'], 'b2');
      expect(c.state!.hasBlockingFlags, isTrue, reason: 'two bowlers in one over needs a decision');
    });
  });

  group('A batter is out on this ball', () {
    testWidgets('switch on → choose how out and who comes in → saved as a wicket', (tester) async {
      await _open(tester, [_bat(0), _bat(1)]);
      await _openEditor(tester, 0);
      await _tap(tester, find.text('A batter is out on this ball'));
      await _tap(tester, find.widgetWithText(ChoiceChip, 'A3'));
      await _save(tester);
      final first = (await _stored(tester)).first;
      expect(first['wicket']['kind'], isNotNull);
      expect(first['wicket']['newBatterId'], 'a3');
      expect(_r.wickets, 1);
      expect(_r.batters['a1']!.status, BatterStatus.out);
    });

    testWidgets('switch off removes the wicket', (tester) async {
      await _open(tester, [
        CricketEvent.wicketBall(0, 'b1', const Wicket(kind: WicketKind.bowled, outBatterId: 'a1', newBatterId: 'a3')),
        _bat(1),
      ]);
      expect(_r.wickets, 1);
      await _openEditor(tester, 0);
      await _tap(tester, find.text('A batter is out on this ball'));
      await _save(tester);
      expect((await _stored(tester)).first['wicket'], isNull);
      expect(_r.wickets, 0);
    });
  });

  group('Delete this ball', () {
    testWidgets('removes it and everything after is re-worked', (tester) async {
      await _open(tester, [_bat(1), _bat(2), _bat(3)]);
      await _openEditor(tester, 1);
      await _tap(tester, find.text('Delete this ball'));
      await _tap(tester, find.widgetWithText(FilledButton, 'Delete'));
      expect((await _stored(tester)).length, 2);
      expect(_r.runs, 4);
    });
  });
}

void _clarityTests() {
  group('Clarity', () {
    testWidgets('names who bowled, who faced and what was recorded', (tester) async {
      await _open(tester, [_bat(1), _bat(4, b: Boundary.four)]);
      await _openEditor(tester, 1);
      expect(find.text('Edit ball — Over 1 · Ball 2'), findsOneWidget);
      expect(find.text('Bowler'), findsWidgets);
      expect(find.text('Batter on strike'), findsOneWidget);
      expect(find.text('Other batter'), findsOneWidget);
      // ball 1 was a single, so A2 faces ball 2 and A1 is at the other end
      expect(find.text('Recorded as: FOUR! A2 hits B1 for 4'), findsOneWidget);
    });

    testWidgets('previews the effect live: four → single', (tester) async {
      await _open(tester, [_bat(0), _bat(4, b: Boundary.four), _bat(2)]);
      await _openEditor(tester, 1);
      expect(find.text('If you save this'), findsOneWidget);
      expect(find.text('Innings score stays 6/0'), findsOneWidget);
      // 4 → 1: tap "−" three times and clear the boundary
      await _tap(tester, find.widgetWithText(ChoiceChip, 'No'));
      for (var i = 0; i < 3; i++) {
        await _tap(tester, find.widgetWithIcon(IconButton, Icons.remove));
      }
      expect(find.text('Innings score: 6/0 → 3/0'), findsOneWidget);
      expect(find.textContaining('is faced by'), findsOneWidget);
      // nothing was saved by looking
      expect(_r.runs, 6);
    });
  });
}
