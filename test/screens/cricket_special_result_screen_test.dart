import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/models/player.dart';
import 'package:flow_sports_app/screens/admin/admin_cricket_match_screen.dart';
import 'package:flow_sports_app/services/firestore_service.dart';
import 'package:flow_sports_app/widgets/cricket_score_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The "Not played normally?" card on the cricket match page: No result and
// Walkover, on phone-sized screens, against an in-memory Firestore.

late FakeFirebaseFirestore db;

Future<void> _seed({String stage = 'league'}) async {
  db = FakeFirebaseFirestore();
  List<Map<String, dynamic>> players(String p) =>
      [for (var i = 1; i <= 4; i++) Player(id: '$p$i', name: '${p.toUpperCase()}$i').toMap()];
  await db.collection('teams').doc('tA').set({'sport': 'cricket', 'category': 'boys', 'season': '2026', 'name': 'Reds', 'players': players('a')});
  await db.collection('teams').doc('tB').set({'sport': 'cricket', 'category': 'boys', 'season': '2026', 'name': 'Blues', 'players': players('b')});
  await db.collection('matches').doc('m1').set({
    'sport': 'cricket', 'category': 'boys', 'season': '2026', 'stage': stage, 'matchNumber': 1,
    'label': 'Match 1', 'matchCode': stage == 'knockout' ? 'KOF' : 'L1', 'status': 'upcoming', 'notifyTopic': '',
    'teamA': {'teamId': 'tA', 'name': 'Reds'}, 'teamB': {'teamId': 'tB', 'name': 'Blues'},
    'rules': const CricketRules(overs: 2).toMap(),
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: AdminCricketMatchScreen(matchId: 'm1', service: FirestoreService(firestore: db)),
  ));
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester);
}

Future<Map<String, dynamic>> _match(WidgetTester tester) async =>
    (await tester.runAsync(() async => (await db.collection('matches').doc('m1').get()).data()))!;

void main() {
  for (final size in const [Size(411, 869), Size(360, 640)]) {
    group('on ${size.width.toInt()}x${size.height.toInt()}', () {
      testWidgets('no result: asks, saves with the reason, then offers to take it back', (tester) async {
        await _seed();
        await _pump(tester, size);
        expect(find.text('Not played normally?'), findsOneWidget);
        await _tap(tester, find.text('No result'));
        expect(find.text('Mark as no result?'), findsOneWidget);
        expect(find.textContaining('1 point'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, 'Rain');
        await _tap(tester, find.text('Save no result'));

        final m = await _match(tester);
        expect(m['status'], 'completed');
        expect(m['resultType'], 'noResult');
        expect(m['resultText'], 'No result — Rain');
        expect(find.text('This match was called off with no result.'), findsOneWidget);

        await _tap(tester, find.text('Take this result back'));
        await _tap(tester, find.text('Take it back'));
        final back = await _match(tester);
        expect(back['status'], 'upcoming');
        expect(back['resultType'], isNull);
        expect(find.text('No result'), findsOneWidget);
      });

      testWidgets('cancelling changes nothing', (tester) async {
        await _seed();
        await _pump(tester, size);
        await _tap(tester, find.text('No result'));
        await _tap(tester, find.text('Cancel'));
        expect((await _match(tester))['status'], 'upcoming');
      });

      testWidgets('walkover: Save stays off until a winner is picked', (tester) async {
        await _seed();
        await _pump(tester, size);
        await _tap(tester, find.text('Walkover'));
        FilledButton save() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save walkover'));
        expect(save().onPressed, isNull);
        await _tap(tester, find.widgetWithText(RadioListTile<String>, 'Blues'));
        expect(save().onPressed, isNotNull);
        await tester.enterText(find.byType(TextField).last, 'Reds did not turn up');
        await _tap(tester, find.text('Save walkover'));

        final m = await _match(tester);
        expect(m['result'], 'teamB');
        expect(m['resultType'], 'walkover');
        expect(m['resultText'], 'Blues won by walkover (Reds did not turn up)');
        expect(find.text('This match was given as a walkover.'), findsOneWidget);
      });

      testWidgets('a knockout offers only the walkover', (tester) async {
        await _seed(stage: 'knockout');
        await _pump(tester, size);
        expect(find.text('No result'), findsNothing);
        expect(find.text('Walkover'), findsOneWidget);
        await _tap(tester, find.text('Walkover'));
        expect(find.textContaining('moves to the next round'), findsOneWidget);
      });
    });
  }

  group('what viewers see', () {
    Match finished(String type, String text, MatchResult result) => Match(
          id: 'm1',
          sport: 'cricket',
          category: 'boys',
          season: '2026',
          stage: MatchStage.league,
          matchNumber: 1,
          label: 'Match 1',
          matchCode: 'L1',
          teamA: const TeamRef(teamId: 'tA', name: 'Reds'),
          teamB: const TeamRef(teamId: 'tB', name: 'Blues'),
          notifyTopic: '',
          status: MatchStatus.completed,
          result: result,
          resultType: type,
          resultText: text,
        );

    for (final c in [
      (ResultType.walkover, 'Blues won by walkover', MatchResult.teamB),
      (ResultType.noResult, 'No result — Rain', MatchResult.tie),
    ]) {
      testWidgets('${c.$1}: the result line, and no "Yet to bat"', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: CricketScoreBlock(match: finished(c.$1, c.$2, c.$3))),
        ));
        expect(find.text(c.$2), findsOneWidget);
        expect(find.text('Yet to bat'), findsNothing);
        expect(find.text('Reds'), findsOneWidget);
      });
    }
  });
}
