import 'dart:math';

import 'package:flow_sports_app/core/cricket/auto_play.dart';
import 'package:flow_sports_app/core/cricket/cricket_event.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/cricket_toss.dart';
import 'package:flow_sports_app/core/cricket/innings_replay.dart';
import 'package:flow_sports_app/core/cricket/match_display.dart';
import 'package:flow_sports_app/core/cricket/match_scoring.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/models/player.dart';
import 'package:flow_sports_app/models/team.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cricket_test_utils.dart';

String nameOf(String id) => 'N-$id';

Match matchWith({
  MatchStatus status = MatchStatus.upcoming,
  List<InningsRecord> innings = const [],
  MatchResult? result,
  String? resultText,
  String? summaryText,
  CricketToss? toss,
  CricketRules? rules,
}) =>
    Match(
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
      innings: innings,
      result: result,
      resultText: resultText,
      summaryText: summaryText,
      toss: toss,
      rules: rules,
    );

const _start = InningsStart(strikerId: 'a1', nonStrikerId: 'a2');

void main() {
  group('overs and scores', () {
    test('overs text', () {
      expect(oversTextFor(27, 6), '4.3');
      expect(oversTextFor(0, 6), '0.0');
      expect(oversTextFor(13, 5), '2.3');
      expect(oversTextFor(7, 0), '1.1'); // bad rule value falls back to 6
    });

    test('upcoming match: nobody has batted', () {
      final s = sideScores(matchWith());
      expect(s.map((e) => e.hasBatted), [false, false]);
      expect(s.map((e) => e.batting), [false, false]);
    });

    test('live: the side still batting is flagged, the other is yet to bat', () {
      final s = sideScores(matchWith(
        status: MatchStatus.live,
        innings: const [InningsRecord(batting: 'B', start: _start, runs: 45, wickets: 2, legalBalls: 27)],
      ));
      expect(s[0].hasBatted, isFalse); // Reds yet to bat
      expect(s[1].score, '45/2');
      expect(s[1].overs, '4.3');
      expect(s[1].batting, isTrue);
    });

    test('an ended innings is no longer "batting"; the chase is', () {
      final s = sideScores(matchWith(
        status: MatchStatus.live,
        innings: const [
          InningsRecord(batting: 'A', start: _start, runs: 60, wickets: 3, legalBalls: 36, ended: true),
          InningsRecord(batting: 'B', start: _start, runs: 10, wickets: 0, legalBalls: 6),
        ],
      ));
      expect(s[0].batting, isFalse);
      expect(s[1].batting, isTrue);
      expect(s[0].overs, '6.0');
    });

    test('completed match: nobody is batting', () {
      final s = sideScores(matchWith(
        status: MatchStatus.completed,
        innings: const [
          InningsRecord(batting: 'A', start: _start, runs: 60, wickets: 3, legalBalls: 36, ended: true),
          InningsRecord(batting: 'B', start: _start, runs: 61, wickets: 3, legalBalls: 30, ended: true),
        ],
      ));
      expect(s.any((e) => e.batting), isFalse);
    });

    test('uses the match\'s own balls per over', () {
      final s = sideScores(matchWith(
        rules: const CricketRules(ballsPerOver: 5),
        innings: const [InningsRecord(batting: 'A', start: _start, runs: 9, wickets: 0, legalBalls: 13)],
      ));
      expect(s[0].overs, '2.3');
    });
  });

  group('status line', () {
    const toss = CricketToss(winner: 'B', elected: 'bowl');

    test('toss text', () {
      expect(tossText(null, 'Reds', 'Blues'), isNull);
      expect(tossText(toss, 'Reds', 'Blues'), 'Blues won the toss and chose to bowl');
      expect(tossText(const CricketToss(winner: 'A', elected: 'bat'), 'Reds', 'Blues'),
          'Reds won the toss and chose to bat');
    });

    test('upcoming shows the toss, live the summary, completed the result', () {
      expect(matchStatusLine(matchWith(toss: toss)), 'Blues won the toss and chose to bowl');
      expect(matchStatusLine(matchWith()), isNull);
      expect(
        matchStatusLine(matchWith(status: MatchStatus.live, summaryText: 'Reds 5/0 (1.0 ov)')),
        'Reds 5/0 (1.0 ov)',
      );
      expect(
        matchStatusLine(matchWith(
            status: MatchStatus.completed, resultText: 'Reds won by 3 runs', summaryText: 'old')),
        'Reds won by 3 runs',
      );
      expect(
        matchStatusLine(matchWith(status: MatchStatus.completed, summaryText: 'fallback')),
        'fallback',
      );
    });
  });

  group('dismissal text', () {
    BatterStats out(WicketKind kind, {String? bowler, String? fielder}) =>
        BatterStats('x', BatterStatus.out)..dismissal = Dismissal(kind, bowlerId: bowler, fielderId: fielder);

    test('every kind', () {
      expect(dismissalText(out(WicketKind.bowled, bowler: 'b1'), nameOf), 'b N-b1');
      expect(dismissalText(out(WicketKind.caught, bowler: 'b1', fielder: 'f1'), nameOf), 'c N-f1 b N-b1');
      expect(dismissalText(out(WicketKind.caught, bowler: 'b1', fielder: 'b1'), nameOf), 'c & b N-b1');
      expect(dismissalText(out(WicketKind.caught, bowler: 'b1'), nameOf), 'caught b N-b1');
      expect(dismissalText(out(WicketKind.lbw, bowler: 'b1'), nameOf), 'lbw b N-b1');
      expect(dismissalText(out(WicketKind.stumped, bowler: 'b1', fielder: 'k1'), nameOf), 'st N-k1 b N-b1');
      expect(dismissalText(out(WicketKind.hitWicket, bowler: 'b1'), nameOf), 'hit wicket b N-b1');
      expect(dismissalText(out(WicketKind.runOut, fielder: 'f1'), nameOf), 'run out (N-f1)');
      expect(dismissalText(out(WicketKind.runOut), nameOf), 'run out');
      expect(dismissalText(out(WicketKind.obstructingField), nameOf), 'obstructing the field');
      expect(dismissalText(out(WicketKind.hitBallTwice), nameOf), 'hit the ball twice');
      expect(dismissalText(out(WicketKind.handledBall), nameOf), 'handled the ball');
      expect(dismissalText(out(WicketKind.bowled), nameOf), 'bowled');
    });

    test('not out, retired, did not bat', () {
      expect(dismissalText(BatterStats('x', BatterStatus.batting), nameOf), 'not out');
      expect(dismissalText(BatterStats('x', BatterStatus.retired), nameOf), 'retired');
      expect(dismissalText(BatterStats('x', BatterStatus.yetToBat), nameOf), 'did not bat');
    });
  });

  group('names', () {
    test('lookup reads both rosters and never crashes on a stranger', () {
      Team team(String id, List<Player> players) =>
          Team(id: id, sport: 'cricket', category: 'boys', name: id, season: '2026', players: players);
      final lookup = playerNameLookup(
        team('tA', const [Player(id: 'a1', name: 'Ravi')]),
        team('tB', const [Player(id: 'b1', name: 'Sam')]),
      );
      expect(lookup('a1'), 'Ravi');
      expect(lookup('b1'), 'Sam');
      expect(lookup('zzz'), 'Unknown player');
      expect(playerNameLookup(null, null)('a1'), 'Unknown player');
    });
  });

  group('scorecard pieces', () {
    test('extras and fall of wickets text', () {
      expect(extrasText(Extras()), 'Extras 0');
      expect(
        extrasText(Extras()
          ..wides = 2
          ..noBalls = 1
          ..legByes = 3),
        'Extras 6 (wd 2, nb 1, lb 3)',
      );
      expect(fallOfWicketText(const FallOfWicket(2, 31, 'a3', '3.4'), nameOf), '2-31 (N-a3, 3.4)');
    });

    test('batting order: openers, then replacements in the order they came in', () {
      final r = replayInnings(openRules, setupFor(), [
        CricketEvent.dot(1, 'b1'),
        // a1 bowled: the scorer brings a5 in (not a3), then a3 later.
        CricketEvent.wicketBall(
            2, 'b1', const Wicket(kind: WicketKind.bowled, outBatterId: 'a1', newBatterId: 'a5')),
        CricketEvent.dot(3, 'b1'),
        CricketEvent.wicketBall(
            4, 'b1', const Wicket(kind: WicketKind.bowled, outBatterId: 'a5', newBatterId: 'a3')),
      ]);
      expect(battingOrder(r), ['a1', 'a2', 'a5', 'a3']);
    });

    test('a batter sent in on the last ball is still listed', () {
      final r = replayInnings(openRules, setupFor(), [
        CricketEvent.wicketBall(
            1, 'b1', const Wicket(kind: WicketKind.bowled, outBatterId: 'a1', newBatterId: 'a4')),
      ]);
      expect(battingOrder(r), ['a1', 'a2', 'a4']);
    });

    test('overs are grouped newest first with a plain heading and ball numbers', () {
      final r = replayInnings(openRules, setupFor(), [
        for (var i = 1; i <= 6; i++) CricketEvent.bat(i, 'b1', 1),
        // Over 2 by b2: a wide, a four, a wicket.
        const CricketEvent.wide(7, 'b2'),
        const CricketEvent.bat(8, 'b2', 4, boundary: Boundary.four),
        CricketEvent.wicketBall(
            9, 'b2', const Wicket(kind: WicketKind.bowled, outBatterId: 'a2', newBatterId: 'a3')),
      ]);
      final groups = overGroups(r, nameOf);
      expect(groups.length, 2);
      expect(groups.first.number, 2); // newest over first
      expect(groups.first.header, 'Over 2 · N-b2 bowling · 5 runs · 1 wicket · in progress');
      expect(groups.last.header, 'Over 1 · N-b1 bowling · 6 runs');
      // Newest ball first, numbered inside the over; the wide has no number.
      expect(groups.first.lines.map((l) => l.label), ['2', '1', 'Wd']);
      expect(groups.first.lines[0].wicket, isTrue);
      expect(groups.first.lines[1].boundary, isTrue);
      expect(groups.last.lines.map((l) => l.label), ['6', '5', '4', '3', '2', '1']);
      // Limiting the number of overs keeps the newest.
      expect(overGroups(r, nameOf, maxOvers: 1).single.number, 2);
    });

    test('ball labels and places', () {
      final r = replayInnings(openRules, setupFor(), [
        const CricketEvent.dot(1, 'b1'),
        const CricketEvent.wide(2, 'b1'),
        const CricketEvent.noBall(3, 'b1'),
        const CricketEvent(seq: 4, bowlerId: 'b1', delivery: Delivery.deadBall),
        const CricketEvent.bat(5, 'b1', 1),
      ]);
      final b = r.balls;
      expect(b.map(ballLabel), ['1', 'Wd', 'Nb', 'Dead', '2']);
      expect(b.map(ballLabelLong), ['Ball 1', 'Wide', 'No ball', 'Dead ball', 'Ball 2']);
      expect(ballPlace(b.last), 'Over 1 · Ball 2');
    });
  });

  group('buildCricketView', () {
    final teamA = Team(
      id: 'tA',
      sport: 'cricket',
      category: 'boys',
      name: 'Reds',
      season: '2026',
      players: [for (var i = 1; i <= 4; i++) Player(id: 'a$i', name: 'Red $i')],
    );
    final teamB = Team(
      id: 'tB',
      sport: 'cricket',
      category: 'boys',
      name: 'Blues',
      season: '2026',
      players: [for (var i = 1; i <= 4; i++) Player(id: 'b$i', name: 'Blue $i')],
    );
    const rules = CricketRules(
      overs: 2,
      lastManStands: false,
      maxOversPerBowler: null,
      legByesAllowed: true,
      allowedWickets: CricketRules.allWickets,
    );

    Match finished(SimulatedMatch sim) {
      final state = deriveMatchState(
        rules: rules,
        lineupA: ['a1', 'a2', 'a3', 'a4'],
        lineupB: ['b1', 'b2', 'b3', 'b4'],
        toss: const CricketToss(winner: 'A', elected: 'bat'),
        starts: sim.starts,
        events: sim.events,
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
        status: MatchStatus.completed,
        rules: rules,
        lineupA: ['a1', 'a2', 'a3', 'a4'],
        lineupB: ['b1', 'b2', 'b3', 'b4'],
        toss: const CricketToss(winner: 'A', elected: 'bat'),
        innings: [for (final v in state.innings) inningsRecordOf(v, sim.starts[v.index])],
      );
    }

    test('no rules or no innings: nothing to show yet', () {
      final data = buildCricketView(match: matchWith(), teamA: teamA, teamB: teamB, events: const []);
      expect(data.state, isNull);
      expect(data.hasScorecard, isFalse);
      expect(data.nameOf('a1'), 'Red 1');
    });

    test('ball log not loaded yet: no scorecard rather than an empty 0/0 one', () {
      final sim = simulateMatch(
        rules: rules,
        lineupA: ['a1', 'a2', 'a3', 'a4'],
        lineupB: ['b1', 'b2', 'b3', 'b4'],
        battingFirst: 'A',
        random: Random(1),
      );
      final data = buildCricketView(match: finished(sim), teamA: teamA, teamB: teamB, events: null);
      expect(data.hasScorecard, isFalse);
    });

    test('a full simulated match gives a scorecard whose totals match the cached innings', () {
      for (var seed = 0; seed < 25; seed++) {
        final sim = simulateMatch(
          rules: rules,
          lineupA: ['a1', 'a2', 'a3', 'a4'],
          lineupB: ['b1', 'b2', 'b3', 'b4'],
          battingFirst: 'A',
          random: Random(seed),
        );
        final match = finished(sim);
        final data = buildCricketView(match: match, teamA: teamA, teamB: teamB, events: sim.events);
        expect(data.hasScorecard, isTrue, reason: 'seed $seed');
        expect(data.state!.phase, ScoringPhase.finished, reason: 'seed $seed');
        for (final v in data.state!.innings) {
          final cached = match.innings[v.index];
          expect(v.result.runs, cached.runs, reason: 'seed $seed');
          expect(v.result.wickets, cached.wickets, reason: 'seed $seed');
          // Every batter's runs plus extras add up to the innings total.
          final batRuns = v.result.batters.values.fold(0, (s, b) => s + b.runs);
          expect(batRuns + v.result.extras.total, v.result.runs, reason: 'seed $seed');
          // Every dismissed batter reads as something other than "not out".
          for (final id in battingOrder(v.result)) {
            final b = v.result.batters[id]!;
            if (b.status == BatterStatus.out) {
              expect(dismissalText(b, data.nameOf), isNot('not out'));
            }
          }
        }
      }
    });
  });
}
