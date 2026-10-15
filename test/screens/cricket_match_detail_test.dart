import 'dart:async';
import 'dart:math';

import 'package:flow_sports_app/core/cricket/auto_play.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/cricket_toss.dart';
import 'package:flow_sports_app/core/cricket/match_display.dart';
import 'package:flow_sports_app/core/cricket/match_result.dart';
import 'package:flow_sports_app/core/cricket/match_scoring.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/models/player.dart';
import 'package:flow_sports_app/models/team.dart';
import 'package:flow_sports_app/screens/viewer/cricket_match_detail.dart';
import 'package:flow_sports_app/widgets/cricket_score_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// What a viewer sees for a cricket match, on phone-sized screens. Built from
// the real engine's simulated matches, so a layout overflow or a crash on
// realistic data fails here.

const _rules = CricketRules(
  overs: 2,
  lastManStands: false,
  maxOversPerBowler: null,
  legByesAllowed: true,
  allowedWickets: CricketRules.allWickets,
);
const _lineupA = ['a1', 'a2', 'a3', 'a4'];
const _lineupB = ['b1', 'b2', 'b3', 'b4'];
const _toss = CricketToss(winner: 'A', elected: 'bat');

final _teamA = Team(
  id: 'tA',
  sport: 'cricket',
  category: 'boys',
  name: 'Reds',
  season: '2026',
  players: [for (var i = 1; i <= 4; i++) Player(id: 'a$i', name: 'Red$i')],
);
final _teamB = Team(
  id: 'tB',
  sport: 'cricket',
  category: 'boys',
  name: 'Blues',
  season: '2026',
  players: [for (var i = 1; i <= 4; i++) Player(id: 'b$i', name: 'Blue$i')],
);

/// The match doc as live scoring would have left it after [events].
Match _match({
  required List<InningsStart> starts,
  required List<LoggedEvent> events,
  required MatchStatus status,
  String? resultText,
  MatchResult? result,
  bool withSetup = true,
}) {
  final state = deriveMatchState(
    rules: _rules,
    lineupA: _lineupA,
    lineupB: _lineupB,
    toss: _toss,
    starts: starts,
    events: events,
    nameA: 'Reds',
    nameB: 'Blues',
  );
  return Match(
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
    status: status,
    rules: _rules,
    lineupA: withSetup ? _lineupA : const [],
    lineupB: withSetup ? _lineupB : const [],
    toss: withSetup ? _toss : null,
    venue: 'Ground 1',
    innings: [for (final v in state.innings) inningsRecordOf(v, starts[v.index])],
    summaryText: state.current == null ? null : 'Reds ${state.current!.result.scoreText}',
    resultText: resultText,
    result: result,
    scoreA: state.runsFor('A'),
    scoreB: state.runsFor('B'),
  );
}

SimulatedMatch _simulate(int seed) => simulateMatch(
      rules: _rules,
      lineupA: _lineupA,
      lineupB: _lineupB,
      battingFirst: 'A',
      random: Random(seed),
    );

Future<void> _size(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

CricketMatchDetailView _view(Match match, List<LoggedEvent> events) => CricketMatchDetailView(
      match: match,
      data: buildCricketView(match: match, teamA: _teamA, teamB: _teamB, events: events),
      showEngagement: false,
    );

/// The LIVE badge pulses forever, so a live screen never "settles".
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _tab(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await _settle(tester);
}

void main() {
  for (final size in const [Size(411, 869), Size(360, 640)]) {
    group('${size.width.toInt()}x${size.height.toInt()}', () {
      testWidgets('finished match: result, scorecard and info', (tester) async {
        await _size(tester, size);
        // Find a seed whose match has a wicket so the fall-of-wickets block shows.
        late SimulatedMatch sim;
        for (var seed = 0;; seed++) {
          sim = _simulate(seed);
          final probe = _match(starts: sim.starts, events: sim.events, status: MatchStatus.completed);
          if (probe.innings.any((i) => i.wickets > 0)) break;
        }
        final match = _match(
          starts: sim.starts,
          events: sim.events,
          status: MatchStatus.completed,
          resultText: 'Reds won by 4 runs',
          result: MatchResult.teamA,
        );
        await tester.pumpWidget(_app(_view(match, sim.events)));
        await tester.pumpAndSettle();

        // Top block.
        expect(find.byType(CricketScoreBlock), findsOneWidget);
        expect(find.text('Reds won by 4 runs'), findsOneWidget);
        expect(find.text('DONE'), findsOneWidget);

        // Scorecard.
        await _tab(tester, 'Scorecard');
        expect(find.text('Reds innings'), findsOneWidget);
        expect(find.text('Batter'), findsWidgets);
        expect(find.textContaining('Extras'), findsWidgets);
        await tester.scrollUntilVisible(find.text('Blues innings'), 300,
            scrollable: find.byType(Scrollable).last);
        await tester.scrollUntilVisible(find.text('Reds bowling'), 300,
            scrollable: find.byType(Scrollable).last);
        expect(tester.takeException(), isNull);

        // Info.
        await _tab(tester, 'Info');
        expect(find.text('Reds won the toss and chose to bat'), findsOneWidget);
        expect(find.textContaining('2 overs'), findsOneWidget);
        expect(find.textContaining('Red1'), findsOneWidget);
        expect(find.text('Ground 1'), findsOneWidget);
      });

      testWidgets('knockout settled by a super over: both scores, the super over, and its scorecard', (tester) async {
        await _size(tester, size);
        final rules = _rules.copyWith(overs: 1);
        late SimulatedMatch sim;
        for (var seed = 0;; seed++) {
          sim = simulateMatch(
            rules: rules,
            lineupA: _lineupA,
            lineupB: _lineupB,
            battingFirst: 'A',
            superOver: true,
            random: Random(seed),
          );
          if (sim.starts.length > 2) break;
        }
        final state = deriveMatchState(
          rules: rules,
          lineupA: _lineupA,
          lineupB: _lineupB,
          toss: _toss,
          starts: sim.starts,
          events: sim.events,
          nameA: 'Reds',
          nameB: 'Blues',
          knockout: true,
        );
        final match = Match(
          id: 'm1',
          sport: 'cricket',
          category: 'boys',
          season: '2026',
          stage: MatchStage.knockout,
          matchNumber: 1,
          label: 'Semifinal',
          matchCode: 'KO1',
          teamA: const TeamRef(teamId: 'tA', name: 'Reds'),
          teamB: const TeamRef(teamId: 'tB', name: 'Blues'),
          notifyTopic: '',
          status: MatchStatus.completed,
          rules: rules,
          lineupA: _lineupA,
          lineupB: _lineupB,
          toss: _toss,
          innings: [for (final v in state.innings) inningsRecordOf(v, sim.starts[v.index])],
          resultText: state.result!.text,
          result: state.result!.winner == CricketWinner.teamA ? MatchResult.teamA : MatchResult.teamB,
          scoreA: state.runsFor('A'),
          scoreB: state.runsFor('B'),
        );
        await tester.pumpWidget(_app(_view(match, sim.events)));
        await tester.pumpAndSettle();

        // The match score is level; the super over is shown under each side.
        expect(find.textContaining('Super over  '), findsNWidgets(2));
        expect(find.textContaining('won the super over'), findsOneWidget);

        await _tab(tester, 'Scorecard');
        expect(find.text('Reds innings'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Super over · Blues'), 300,
            scrollable: find.byType(Scrollable).last);
        await tester.scrollUntilVisible(find.text('Super over · Reds'), 300,
            scrollable: find.byType(Scrollable).last);
        expect(tester.takeException(), isNull);
      });

      testWidgets('live match: batters, bowler, this over and commentary', (tester) async {
        await _size(tester, size);
        final sim = _simulate(3);
        // Part-way through the first innings.
        final events = sim.events.where((e) => e.innings == 0).take(9).toList();
        final match = _match(starts: [sim.starts[0]], events: events, status: MatchStatus.live);
        await tester.pumpWidget(_app(_view(match, events)));
        await _settle(tester);

        expect(find.text('LIVE'), findsOneWidget);
        expect(find.text('Batting'), findsOneWidget);
        expect(find.text('Bowling'), findsOneWidget);
        expect(find.text('This over'), findsOneWidget);
        expect(find.text('Ball by ball'), findsOneWidget);
        expect(find.text('Blues'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('upcoming match: toss on Live, nothing to score yet', (tester) async {
        await _size(tester, size);
        final match = _match(starts: const [], events: const [], status: MatchStatus.upcoming);
        await tester.pumpWidget(_app(_view(match, const [])));
        await tester.pumpAndSettle();

        expect(find.text('Reds won the toss and chose to bat'), findsWidgets);
        await _tab(tester, 'Scorecard');
        expect(find.text('The scorecard appears once the match starts.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('a match with no setup at all still opens', (tester) async {
    await _size(tester, const Size(360, 640));
    final match = _match(starts: const [], events: const [], status: MatchStatus.upcoming, withSetup: false);
    await tester.pumpWidget(_app(_view(match, const [])));
    await tester.pumpAndSettle();
    expect(find.text('The match has not started yet.'), findsOneWidget);
    await _tab(tester, 'Info');
    expect(find.text('Not picked yet'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the help sheet explains the numbers', (tester) async {
    await _size(tester, const Size(360, 640));
    final match = _match(starts: const [], events: const [], status: MatchStatus.upcoming);
    await tester.pumpWidget(_app(_view(match, const [])));
    await _tab(tester, 'Info');
    await tester.tap(find.text('How to read cricket scores'));
    await tester.pumpAndSettle();
    expect(find.text('45/2'), findsOneWidget);
    expect(find.textContaining('An over is 6 balls'), findsOneWidget);
  });

  testWidgets('share button only when a handler is given', (tester) async {
    await _size(tester, const Size(360, 640));
    final match = _match(starts: const [], events: const [], status: MatchStatus.upcoming);
    var shared = 0;
    await tester.pumpWidget(_app(CricketMatchDetailView(
      match: match,
      data: buildCricketView(match: match, teamA: _teamA, teamB: _teamB, events: const []),
      showEngagement: false,
      onShare: () => shared++,
    )));
    await _tab(tester, 'Info');
    await tester.scrollUntilVisible(find.text('Share result'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Share result'));
    expect(shared, 1);
  });

  group('with streams', () {
    testWidgets('a live match follows the ball log; names come from the rosters', (tester) async {
      await _size(tester, const Size(411, 869));
      final sim = _simulate(5);
      final first = sim.events.where((e) => e.innings == 0).toList();
      final balls = StreamController<List<LoggedEvent>>();
      final teams = StreamController<List<Team>>();
      addTearDown(balls.close);
      addTearDown(teams.close);

      final match = _match(starts: [sim.starts[0]], events: first.take(3).toList(), status: MatchStatus.live);
      await tester.pumpWidget(_app(CricketMatchDetail(
        match: match,
        teamsOverride: teams.stream,
        ballsOverride: balls.stream,
        showEngagement: false,
      )));
      await tester.pump();

      // Nothing loaded yet: no fake 0/0 scorecard.
      await _tab(tester, 'Scorecard');
      expect(find.text('Loading the scorecard…'), findsOneWidget);

      teams.add([_teamA, _teamB]);
      balls.add(first.take(3).toList());
      await _settle(tester);
      expect(find.text('Reds innings'), findsOneWidget);
      expect(find.textContaining('Red1'), findsWidgets);

      // More balls arrive: the scorecard moves (one commentary line per ball).
      await _tab(tester, 'Live');
      int lines() => find.textContaining(RegExp(r'takes|hits|Dot ball|Wide ball|No ball|OUT|bye')).evaluate().length;
      final before = lines();
      balls.add(first.take(6).toList());
      await _settle(tester);
      expect(lines(), greaterThan(before));
    });

    testWidgets('an unreadable ball log is explained, not a blank or fake scorecard', (tester) async {
      await _size(tester, const Size(360, 640));
      final sim = _simulate(2);
      final match = _match(
        starts: sim.starts,
        events: sim.events,
        status: MatchStatus.completed,
        resultText: 'Reds won',
        result: MatchResult.teamA,
      );
      await tester.pumpWidget(_app(CricketMatchDetail(
        match: match,
        teamsOverride: Stream.value([_teamA, _teamB]),
        ballsOverride: Stream<List<LoggedEvent>>.error(StateError('permission-denied')),
        showEngagement: false,
      )));
      await tester.pumpAndSettle();

      // The top scores come from the match doc, so they still show.
      expect(find.text('Reds won'), findsOneWidget);
      await _tab(tester, 'Scorecard');
      expect(find.textContaining('could not be loaded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a finished match reads the ball log once', (tester) async {
      await _size(tester, const Size(360, 640));
      final sim = _simulate(4);
      final match = _match(
        starts: sim.starts,
        events: sim.events,
        status: MatchStatus.completed,
        resultText: 'Reds won',
        result: MatchResult.teamA,
      );
      var listens = 0;
      final balls = StreamController<List<LoggedEvent>>(onListen: () => listens++);
      addTearDown(balls.close);
      await tester.pumpWidget(_app(CricketMatchDetail(
        match: match,
        teamsOverride: Stream.value([_teamA, _teamB]),
        ballsOverride: balls.stream,
        showEngagement: false,
      )));
      balls.add(sim.events);
      await tester.pumpAndSettle();
      expect(listens, 1);
      await _tab(tester, 'Scorecard');
      expect(find.text('Reds innings'), findsOneWidget);
      // The single read has been taken: the controller stream was cancelled.
      expect(balls.hasListener, isFalse);
    });
  });
}
