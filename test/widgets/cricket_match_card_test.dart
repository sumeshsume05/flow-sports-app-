import 'package:flow_sports_app/core/cricket/cricket_toss.dart';
import 'package:flow_sports_app/core/cricket/match_scoring.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/widgets/match_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The cricket match card in the viewer's match list: two innings lines and
// one status line, on a small phone, with long team names.

const _start = InningsStart(strikerId: 'a1', nonStrikerId: 'a2');

Match _match({
  required MatchStatus status,
  List<InningsRecord> innings = const [],
  String? summaryText,
  String? resultText,
  String? liveText,
  MatchResult? result,
  CricketToss? toss,
  String sport = 'cricket',
}) =>
    Match(
      id: 'm1',
      sport: sport,
      category: 'boys',
      season: '2026',
      stage: MatchStage.league,
      matchNumber: 1,
      label: 'Match 1',
      matchCode: 'L1',
      teamA: const TeamRef(teamId: 'tA', name: 'The Thunder Strikers of the North'),
      teamB: const TeamRef(teamId: 'tB', name: 'Blues'),
      notifyTopic: '',
      status: status,
      innings: innings,
      summaryText: summaryText,
      resultText: resultText,
      liveText: liveText,
      result: result,
      toss: toss,
      scoreA: 99,
      scoreB: 77,
    );

Future<void> _pump(WidgetTester tester, Match match) async {
  tester.view.physicalSize = const Size(360, 640) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: MatchCard(match: match, showReactions: false)),
  ));
  // A live card pulses forever, so don't wait for it to settle.
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('upcoming: names and the toss, no scores', (tester) async {
    await _pump(
      tester,
      _match(status: MatchStatus.upcoming, toss: const CricketToss(winner: 'B', elected: 'bowl')),
    );
    expect(find.text('Blues won the toss and chose to bowl'), findsOneWidget);
    expect(find.text('Yet to bat'), findsNothing);
    expect(find.text('99'), findsNothing); // badminton-style score is not used
    expect(tester.takeException(), isNull);
  });

  testWidgets('live: the batting side shows its score and overs, the chase line is below', (tester) async {
    await _pump(
      tester,
      _match(
        status: MatchStatus.live,
        innings: const [
          InningsRecord(batting: 'A', start: _start, runs: 60, wickets: 3, legalBalls: 36, ended: true),
          InningsRecord(batting: 'B', start: _start, runs: 22, wickets: 1, legalBalls: 15),
        ],
        summaryText: 'Blues 22/1 (2.3 ov) · Blues need 39 runs in 21 balls',
      ),
    );
    expect(find.text('60/3'), findsOneWidget);
    expect(find.text('(6.0 ov)'), findsOneWidget);
    expect(find.text('22/1'), findsOneWidget);
    expect(find.text('(2.3 ov)'), findsOneWidget);
    expect(find.textContaining('Blues need 39 runs in 21 balls'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live: shows who is batting and who is bowling; finished does not', (tester) async {
    const text = 'Arun 12* (8), Gopi 3 (2) · Bowling: Dinesh 1-0-8-1';
    await _pump(
      tester,
      _match(
        status: MatchStatus.live,
        innings: const [InningsRecord(batting: 'A', start: _start, runs: 15, wickets: 0, legalBalls: 10)],
        liveText: text,
      ),
    );
    expect(find.text(text), findsOneWidget);
    await _pump(tester, _match(status: MatchStatus.completed, liveText: text));
    expect(find.text(text), findsNothing);
  });

  testWidgets('live, first innings: the side yet to bat says so', (tester) async {
    await _pump(
      tester,
      _match(
        status: MatchStatus.live,
        innings: const [InningsRecord(batting: 'A', start: _start, runs: 5, wickets: 0, legalBalls: 3)],
        summaryText: 'The Thunder Strikers of the North 5/0 (0.3 ov)',
      ),
    );
    expect(find.text('Yet to bat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed: the result line and a trophy for the winner', (tester) async {
    await _pump(
      tester,
      _match(
        status: MatchStatus.completed,
        innings: const [
          InningsRecord(batting: 'A', start: _start, runs: 60, wickets: 3, legalBalls: 36, ended: true),
          InningsRecord(batting: 'B', start: _start, runs: 58, wickets: 4, legalBalls: 36, ended: true),
        ],
        resultText: 'The Thunder Strikers of the North won by 2 runs',
        result: MatchResult.teamA,
      ),
    );
    expect(find.text('The Thunder Strikers of the North won by 2 runs'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('badminton cards are untouched', (tester) async {
    await _pump(tester, _match(status: MatchStatus.completed, sport: 'badminton', result: MatchResult.teamA));
    expect(find.text('99'), findsOneWidget);
    expect(find.text('77'), findsOneWidget);
  });
}
