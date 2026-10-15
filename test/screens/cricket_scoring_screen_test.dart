import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/models/player.dart';
import 'package:flow_sports_app/screens/admin/admin_cricket_scoring_screen.dart';
import 'package:flow_sports_app/screens/admin/cricket_scoring/scoring_controller.dart';
import 'package:flow_sports_app/services/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The scoring screen itself, on phone-sized screens, driven by taps like a
// scorer would — against an in-memory Firestore. Layout overflows and build
// exceptions fail these tests.

const _rules = CricketRules(
  overs: 2,
  lastManStands: false,
  maxOversPerBowler: null,
  legByesAllowed: true,
  allowedWickets: CricketRules.allWickets,
);

late FakeFirebaseFirestore db;
late CricketScoringController controller;

Future<void> _seed({bool ready = true, String stage = 'league', int overs = 2}) async {
  db = FakeFirebaseFirestore();
  List<Map<String, dynamic>> players(String p) =>
      [for (var i = 1; i <= 4; i++) Player(id: '$p$i', name: '${p.toUpperCase()}$i').toMap()];
  await db.collection('teams').doc('tA').set({'sport': 'cricket', 'category': 'boys', 'season': '2026', 'name': 'Reds', 'players': players('a')});
  await db.collection('teams').doc('tB').set({'sport': 'cricket', 'category': 'boys', 'season': '2026', 'name': 'Blues', 'players': players('b')});
  await db.collection('matches').doc('m1').set({
    'sport': 'cricket', 'category': 'boys', 'season': '2026', 'stage': stage, 'matchNumber': 1,
    'label': 'Match 1', 'matchCode': 'L1', 'status': 'upcoming', 'notifyTopic': '',
    'teamA': {'teamId': 'tA', 'name': 'Reds'}, 'teamB': {'teamId': 'tB', 'name': 'Blues'},
    'rules': _rules.copyWith(overs: overs).toMap(),
    if (ready) ...{
      'lineupA': ['a1', 'a2', 'a3', 'a4'],
      'lineupB': ['b1', 'b2', 'b3', 'b4'],
      'toss': {'winner': 'A', 'elected': 'bat'},
    },
  });
}

Future<void> _pumpScreen(WidgetTester tester, {Size size = const Size(411, 869)}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  controller = CricketScoringController('m1', service: FirestoreService(firestore: db));
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(home: AdminCricketScoringScreen(matchId: 'm1', controller: controller)));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<List<Map<String, dynamic>>> _balls(WidgetTester tester) async => (await tester.runAsync(() async =>
        (await db.collection('matches').doc('m1').collection('balls').orderBy('seq').get()).docs.map((d) => d.data()).toList()))!;

Future<Map<String, dynamic>> _match(WidgetTester tester) async =>
    (await tester.runAsync(() async => (await db.collection('matches').doc('m1').get()).data()))!;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump(); // the scroll has to land before the tap's position is read
  await tester.tap(f, warnIfMissed: false);
  await _settle(tester);
}

/// Like [_tap] for a widget inside a long, lazily built sheet on a small
/// screen: scrolls the sheet until the widget exists.
Future<void> _tapInSheet(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    final sheet = find.byType(Scrollable).last;
    try {
      await tester.scrollUntilVisible(f, 150, scrollable: sheet);
    } on StateError {
      await tester.scrollUntilVisible(f, -150, scrollable: sheet);
    }
  } else {
    // Built but maybe below the fold of the sheet: scroll it into view first.
    await tester.ensureVisible(f.first);
    await tester.pump();
  }
  await _tap(tester, f);
}

Finder _key(String text) => find.widgetWithText(FilledButton, text);

Future<void> _startAndPickBowler(WidgetTester tester) async {
  await _tap(tester, find.text('Start innings'));
  expect(find.text('Who bowls the first over?'), findsOneWidget);
  await _tap(tester, find.text('B1'));
}

void main() {
  for (final size in const [Size(411, 869), Size(360, 640)]) {
    group('scoring screen on ${size.width.toInt()}x${size.height.toInt()}', () {
      testWidgets('start, pick bowler, score runs / wide / wicket / undo', (tester) async {
        await _seed();
        await _pumpScreen(tester, size: size);

        expect(find.text('Start the match'), findsOneWidget);
        expect(find.textContaining('Reds bat first'), findsOneWidget);
        await _startAndPickBowler(tester);
        expect(find.text('0/0'), findsOneWidget);
        expect(find.text('Bowler: B1'), findsOneWidget);

        // a four
        await _tap(tester, _key('4'));
        expect(find.text('4/0'), findsOneWidget);
        var balls = await _balls(tester);
        expect(balls.single['runs'], 4);
        expect(balls.single['boundary'], 'four');
        expect(balls.single['bowlerId'], 'b1');

        // wide + 1 extra run: one wide ball worth 2, strike changes (1 run run)
        await _tap(tester, find.widgetWithText(FilterChip, 'Wide'));
        expect(find.textContaining('Wide —'), findsOneWidget);
        await _tap(tester, _key('1'));
        expect(find.text('6/0'), findsOneWidget);
        balls = await _balls(tester);
        expect(balls[1]['delivery'], 'wide');
        expect(balls[1]['runs'], 1);
        // the wide chip cleared itself after the ball
        expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Wide')).selected, isFalse);

        // wicket: A1 (striker at the time) bowled; next batter A3
        await _tap(tester, _key('W'));
        expect(find.text('Wicket'), findsOneWidget);
        await _tap(tester, find.widgetWithText(ChoiceChip, 'A3'));
        await _tap(tester, find.text('Save wicket'));
        expect(find.text('6/1'), findsOneWidget);
        balls = await _balls(tester);
        expect(balls[2]['wicket']['kind'], 'bowled');
        expect(balls[2]['wicket']['newBatterId'], 'a3');

        // undo takes the wicket back
        await _tap(tester, find.text('Undo'));
        expect(find.text('6/0'), findsOneWidget);
        expect((await _balls(tester)).length, 2);
        expect(tester.takeException(), isNull);
      });

      testWidgets('no-ball starts a free hit, shown to the scorer', (tester) async {
        await _seed();
        await _pumpScreen(tester, size: size);
        await _startAndPickBowler(tester);
        await _tap(tester, find.widgetWithText(FilterChip, 'No ball'));
        await _tap(tester, _key('0'));
        expect(find.textContaining('FREE HIT'), findsOneWidget);
        await _tap(tester, _key('0'));
        expect(find.textContaining('FREE HIT'), findsNothing);
      });

      testWidgets('after an over the next bowler must be picked; the same bowler is warned about', (tester) async {
        await _seed();
        await _pumpScreen(tester, size: size);
        await _startAndPickBowler(tester);
        for (var i = 0; i < 6; i++) {
          await _tap(tester, _key('1'));
        }
        expect(find.text('Over finished — who bowls next?'), findsOneWidget);
        expect(_key('1'), findsNothing, reason: 'no keypad until a bowler is picked');
        expect(find.text('Bowled the last over'), findsOneWidget);
        await _tap(tester, find.text('B2'));
        expect(find.text('Bowler: B2'), findsOneWidget);
        await _tap(tester, _key('2'));
        final balls = await _balls(tester);
        expect(balls.last['bowlerId'], 'b2');
        expect(tester.takeException(), isNull);
      });

      testWidgets('edit a past ball from the ball list; score follows, later balls untouched', (tester) async {
        await _seed();
        await _pumpScreen(tester, size: size);
        await _startAndPickBowler(tester);
        await _tap(tester, _key('0'));
        await _tap(tester, _key('4'));
        await _tap(tester, _key('2'));
        expect(find.text('6/0'), findsOneWidget);

        await _tap(tester, find.byTooltip('All balls — edit'));
        expect(find.textContaining('Over 1 · B1 bowling'), findsOneWidget);
        // tap the second ball (the four)
        await _tap(tester, find.textContaining('FOUR!'));
        expect(find.textContaining('Edit ball — Over 1 · Ball'), findsOneWidget);
        if (size.height < 700) {
          // On a small phone the editor scrolls; here we only check it lays out cleanly.
          expect(tester.takeException(), isNull);
          return;
        }
        // change the boundary four into a single run
        await _tapInSheet(tester, find.widgetWithText(ChoiceChip, 'No')); // boundary: no
        for (var i = 0; i < 3; i++) {
          await _tapInSheet(tester, find.widgetWithIcon(IconButton, Icons.remove)); // 4 -> 1
        }
        await _tapInSheet(tester, find.text('Save ball'));
        final m = await _match(tester);
        expect(m['scoreA'], 3); // 0 + 1 + 2
        final balls = await _balls(tester);
        expect(balls[1]['runs'], 1);
        expect(balls[2]['runs'], 2, reason: 'the ball after it keeps what the scorer entered');
        expect(tester.takeException(), isNull);
      });

      testWidgets('one-tap actions say what happened and can be undone', (tester) async {
        await _seed();
        await _pumpScreen(tester, size: size);
        await _startAndPickBowler(tester);
        await _tap(tester, _key('1'));
        await _tap(tester, find.text('Undo'));
        expect(find.text('Undid: A1 takes 1 run off B1'), findsOneWidget);
        expect(await _balls(tester), isEmpty);

        await _tap(tester, find.text('B1')); // no balls again, so the bowler is asked for
        await _tap(tester, _key('1'));
        await _tap(tester, find.byIcon(Icons.more_vert));
        await _tap(tester, find.text('Swap batters'));
        await tester.pump(const Duration(milliseconds: 700)); // the earlier message slides out first
        expect(find.text('Batters swapped ends'), findsOneWidget);
        expect((await _balls(tester)).length, 2); // the ball and the swap
        await tester.pumpAndSettle(const Duration(milliseconds: 100)); // message fully in
        await _tap(tester, find.text('UNDO'));
        expect((await _balls(tester)).length, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('full match through the screen: both innings, result saved, reopen', (tester) async {
        await _seed();
        await _pumpScreen(tester, size: size);
        await _startAndPickBowler(tester);
        for (var over = 0; over < 2; over++) {
          for (var i = 0; i < 6; i++) {
            await _tap(tester, _key('1'));
          }
          if (over == 0) await _tap(tester, find.text('B2'));
        }
        expect(find.text('Innings break'), findsOneWidget);
        expect(find.textContaining('need 13 runs in 2 overs'), findsOneWidget);
        await _tap(tester, find.text('Start innings'));
        await _tap(tester, find.text('A1'));
        for (var over = 0; over < 2; over++) {
          for (var i = 0; i < 6; i++) {
            // one dot ball, so the chase finishes one run short
            await _tap(tester, _key(over == 0 && i == 0 ? '0' : '1'));
          }
          if (over == 0) await _tap(tester, find.text('A2'));
        }
        expect(find.text('Match over'), findsOneWidget);
        expect(find.text('Reds won by 1 run'), findsOneWidget);
        await _tap(tester, find.text('Save result'));
        // A summary asks first: what will be saved and what it affects.
        expect(find.text('Save this result?'), findsOneWidget);
        expect(find.textContaining('points table'), findsOneWidget);
        // Cancel saves nothing.
        await _tap(tester, find.text('Cancel'));
        await tester.pump(const Duration(seconds: 1)); // let the dialog finish closing
        expect((await _match(tester))['status'], isNot('completed'));
        await _tap(tester, find.text('Save result'));
        await _tap(tester, find.widgetWithText(FilledButton, 'Save result').last);
        expect(find.text('Result saved'), findsOneWidget);
        var m = await _match(tester);
        expect(m['status'], 'completed');
        expect(m['result'], 'teamA');
        expect([m['scoreA'], m['scoreB']], [12, 11]);

        await _tap(tester, find.text('Reopen to edit'));
        await _tap(tester, find.text('Reopen'));
        m = await _match(tester);
        expect(m['status'], 'live');
        expect(m['result'], isNull);
        expect(tester.takeException(), isNull);
      });

      /// Plays a one-over knockout to a 6–6 tie through the screen.
      Future<void> playToTie(WidgetTester tester) async {
        await _seed(stage: 'knockout', overs: 1);
        await _pumpScreen(tester, size: size);
        await _startAndPickBowler(tester);
        for (var i = 0; i < 6; i++) {
          await _tap(tester, _key('1'));
        }
        await _tap(tester, find.text('Start innings'));
        await _tap(tester, find.text('A1'));
        for (var i = 0; i < 6; i++) {
          await _tap(tester, _key('1'));
        }
      }

      testWidgets('a tied knockout offers a super over, plays it, and the result names the winner', (tester) async {
        await playToTie(tester);
        expect(find.text('Match tied'), findsOneWidget);
        expect(find.textContaining('Blues bat first in the super over'), findsOneWidget);
        expect(find.text('Pick the winner by hand'), findsOneWidget);
        expect((await _match(tester))['summaryText'], 'Match tied · super over next');

        // Blues batted second, so they open the super over.
        await _tap(tester, find.text('Start super over innings'));
        await _tap(tester, find.text('A1'));
        expect(find.textContaining('SUPER OVER · 1 over · 2 wickets'), findsOneWidget);
        await _tap(tester, _key('4'));
        for (var i = 0; i < 5; i++) {
          await _tap(tester, _key('0'));
        }
        expect(find.text('Super over — innings break'), findsOneWidget);
        expect(find.textContaining('Reds need 5 runs in 1 over'), findsOneWidget);

        await _tap(tester, find.text('Start super over innings'));
        await _tap(tester, find.text('B1'));
        await _tap(tester, _key('6'));
        expect(find.text('Match over'), findsOneWidget);
        expect(find.text('Match tied — Reds won the super over (6/0 to 4/0)'), findsOneWidget);
        expect(find.text('Super over · Blues: 4/0 (1.0 ov)'), findsOneWidget);

        await _tap(tester, find.text('Save result'));
        expect(find.text('Save this result?'), findsOneWidget);
        expect(find.textContaining('moves on to the next round'), findsOneWidget);
        await _tap(tester, find.widgetWithText(FilledButton, 'Save result').last);
        final m = await _match(tester);
        expect(m['status'], 'completed');
        expect(m['result'], 'teamA');
        expect([m['scoreA'], m['scoreB']], [6, 6]);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the winner can be picked by hand (with a warning), and the pick taken back', (tester) async {
        await playToTie(tester);
        await _tap(tester, find.widgetWithText(OutlinedButton, 'Reds'));
        expect(find.text('Give the win to Reds?'), findsOneWidget);
        // Cancel changes nothing.
        await _tap(tester, find.text('Cancel'));
        await tester.pump(const Duration(seconds: 1));
        expect((await _match(tester))['tieDecision'], isNull);

        await _tap(tester, find.widgetWithText(OutlinedButton, 'Reds'));
        await _tap(tester, find.widgetWithText(FilledButton, 'Give Reds the win'));
        expect(find.text('Match over'), findsOneWidget);
        expect(find.textContaining('given the win'), findsOneWidget);
        expect((await _match(tester))['tieDecision'], 'A');

        await _tap(tester, find.text('Take back my pick'));
        await _tap(tester, find.widgetWithText(FilledButton, 'Take it back'));
        expect(find.text('Match tied'), findsOneWidget);
        expect((await _match(tester))['tieDecision'], isNull);
        expect(tester.takeException(), isNull);
      });

      testWidgets('changing a four to a single in the editor clears the boundary, so the strike changes', (tester) async {
        // The reported case: over 1 = six fours by A1 (24); after the edit ball 1 is a single, so
        // B... the other batter faces balls 2-6 and A1 is back on strike for over 2.
        await _seed();
        await _pumpScreen(tester, size: size);
        await _startAndPickBowler(tester);
        for (var i = 0; i < 6; i++) {
          await _tap(tester, _key('4'));
        }
        await _tap(tester, find.text('B2'));
        await _tap(tester, _key('0')); // first ball of over 2
        expect(controller.state!.current!.result.balls.last.strikerId, 'a2', reason: 'before the edit');

        await _tap(tester, find.byTooltip('All balls — edit'));
        await _tap(tester, find.textContaining('FOUR!').first);
        if (size.height < 700) return; // the editor scrolls on a small phone; covered at full size
        // Only the run count is touched — the boundary chip is NOT.
        for (var i = 0; i < 3; i++) {
          await _tapInSheet(tester, find.widgetWithIcon(IconButton, Icons.remove)); // 4 -> 1
        }
        expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'No').first).selected, isTrue);
        await _tapInSheet(tester, find.text('Save ball'));

        final balls = await _balls(tester);
        expect(balls.first['runs'], 1);
        expect(balls.first['boundary'], 'none');
        final r = controller.state!.current!.result;
        expect(r.runs, 21);
        expect(r.batters['a1']!.runs, 1);
        expect(r.batters['a2']!.runs, 20);
        expect(r.balls.last.strikerId, 'a1', reason: 'A1 is on strike again for over 2');
        expect(tester.takeException(), isNull);
      });

      testWidgets('picking Four / Six in the editor sets the runs to match', (tester) async {
        await _seed();
        await _pumpScreen(tester, size: size);
        await _startAndPickBowler(tester);
        await _tap(tester, _key('1'));
        await _tap(tester, find.byTooltip('All balls — edit'));
        await _tap(tester, find.textContaining('takes 1 run').first);
        if (size.height < 700) return;
        await _tapInSheet(tester, find.widgetWithText(ChoiceChip, 'Six'));
        await _tapInSheet(tester, find.text('Save ball'));
        final first = (await _balls(tester)).first;
        expect([first['runs'], first['boundary']], [6, 'six']);
      });

      testWidgets('a mid-over bowler change is flagged; accepting it clears the review banner', (tester) async {
        await _seed();
        await _pumpScreen(tester, size: size);
        await _startAndPickBowler(tester);
        await _tap(tester, _key('1'));
        // ⋮ → Change bowler → B2 (mid-over)
        await _tap(tester, find.byIcon(Icons.more_vert));
        await _tap(tester, find.text('Change bowler'));
        await _tap(tester, find.text('B2'));
        await _tap(tester, _key('1'));
        expect(find.textContaining('need review'), findsOneWidget);

        await _tap(tester, find.byTooltip('All balls — edit'));
        expect(find.textContaining('bowler changed part-way'), findsOneWidget);
        await _tap(tester, find.text('Accept all'));
        expect(find.textContaining('as they are?'), findsOneWidget);
        await _tap(tester, find.widgetWithText(FilledButton, 'Accept all'));
        expect(find.textContaining('to review'), findsNothing);
        expect((await _balls(tester)).last['acknowledgedFlags'], ['bowlerChangedMidOver']);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a wicket ball opens in the editor with its dismissal filled in', (tester) async {
        await _seed();
        await _pumpScreen(tester, size: size);
        await _startAndPickBowler(tester);
        await _tap(tester, _key('W'));
        await _tap(tester, find.widgetWithText(ChoiceChip, 'A3'));
        await _tap(tester, find.text('Save wicket'));
        await _tap(tester, find.byTooltip('All balls — edit'));
        await _tap(tester, find.textContaining('is bowled'));
        expect(find.textContaining('Edit ball — Over 1 · Ball'), findsOneWidget);
        if (size.height >= 700) {
          await tester.scrollUntilVisible(find.text('A batter is out on this ball'), 150,
              scrollable: find.byType(Scrollable).last);
          expect(find.text('A batter is out on this ball'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('match with no toss yet explains what to do', (tester) async {
        await _seed(ready: false);
        await _pumpScreen(tester, size: size);
        expect(find.textContaining('toss'), findsWidgets);
        expect(find.text('Start innings'), findsNothing);
      });

      testWidgets('permission-denied on the ball log is explained, not a blank screen', (tester) async {
        await _seed();
        // A controller whose ball stream fails, like rules that are not deployed yet.
        final failing = _FailingBallsController();
        addTearDown(failing.dispose);
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(home: AdminCricketScoringScreen(matchId: 'm1', controller: failing)));
        await _settle(tester);
        expect(find.textContaining('permission-denied'), findsOneWidget);
        expect(find.textContaining('rules'), findsWidgets);
      });
    });
  }
}

class _FailingBallsController extends CricketScoringController {
  _FailingBallsController() : super('m1', service: FirestoreService(firestore: db)) {
    Future<void>.microtask(() => error = 'permission-denied (balls)');
    Future<void>.delayed(const Duration(milliseconds: 1), notifyListeners);
  }
}
