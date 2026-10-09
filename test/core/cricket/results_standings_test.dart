import 'package:flow_sports_app/core/cricket/commentary_text.dart';
import 'package:flow_sports_app/core/cricket/cricket_event.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/cricket_standings.dart';
import 'package:flow_sports_app/core/cricket/innings_replay.dart';
import 'package:flow_sports_app/core/cricket/match_result.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cricket_test_utils.dart';

void main() {
  group('CricketRules', () {
    test('presets', () {
      const tape = CricketRules.tapeBall();
      expect(tape.overs, 6);
      expect(tape.squadSize, 8);
      expect(tape.lastManStands, isTrue);
      expect(tape.freeHit, isTrue);
      expect(tape.legByesAllowed, isFalse);
      expect(tape.allowedWickets.contains(WicketKind.lbw), isFalse);
      expect(tape.allowedWickets.contains(WicketKind.stumped), isFalse);
      expect(tape.maxOversPerBowler, 2);

      const t20 = CricketRules.t20();
      expect(t20.overs, 20);
      expect(t20.squadSize, 11);
      expect(t20.lastManStands, isFalse);
      expect(t20.allowedWickets.contains(WicketKind.lbw), isTrue);
      expect(t20.maxOversPerBowler, 4);
    });

    test('maxWickets: last-man-stands uses the whole side', () {
      expect(const CricketRules.t20().maxWickets(11), 10);
      expect(const CricketRules.tapeBall().maxWickets(8), 8);
      expect(const CricketRules.tapeBall().maxBalls, 36);
    });

    test('toMap/fromMap round trip (including a null bowler limit)', () {
      for (final rules in [
        const CricketRules.tapeBall(),
        const CricketRules.t20(),
        const CricketRules(maxOversPerBowler: null, widePenalty: 2, wideReBowl: false),
      ]) {
        final back = CricketRules.fromMap(rules.toMap());
        expect(back.toMap(), rules.toMap());
      }
      expect(CricketRules.fromMap(const CricketRules(maxOversPerBowler: null).toMap()).maxOversPerBowler,
          isNull);
    });

    test('fromMap tolerates a missing/partial map by using the default', () {
      expect(CricketRules.fromMap(null).overs, 6);
      final partial = CricketRules.fromMap({'overs': 10});
      expect(partial.overs, 10);
      expect(partial.squadSize, 8);
      expect(partial.maxOversPerBowler, 2);
    });
  });

  group('CricketEvent serialisation', () {
    test('every kind of event survives toMap/fromMap', () {
      final events = [
        const CricketEvent.dot(1, 'b1'),
        const CricketEvent.bat(2, 'b1', 4, boundary: Boundary.four),
        const CricketEvent.wide(3, 'b1', extraRuns: 2),
        const CricketEvent.noBall(4, 'b1', runType: RunType.bye, runs: 1),
        const CricketEvent.legBye(5, 'b2', 1),
        const CricketEvent(
          seq: 6,
          bowlerId: 'b2',
          runType: RunType.bat,
          runs: 5,
          boundary: Boundary.four,
          completedRunsOverride: 1,
          acknowledgedFlags: {'bowlerOverLimit'},
        ),
        const CricketEvent.wicketBall(
          7,
          'b2',
          Wicket(
            kind: WicketKind.caught,
            outBatterId: 'a1',
            fielderId: 'b3',
            crossed: true,
            newBatterId: 'a3',
            newBatterEnd: NewBatterEnd.offStrike,
          ),
        ),
        const CricketEvent.swapStrike(8),
        const CricketEvent.retire(seq: 9, retiredBatterId: 'a2', newBatterId: 'a4'),
        const CricketEvent.endInnings(10),
      ];
      for (final e in events) {
        expect(CricketEvent.fromMap(e.toMap()), e, reason: 'seq ${e.seq}');
      }
    });

    test('copyWith can clear the wicket and the override', () {
      final e = CricketEvent.wicketBall(1, 'b1', bowledA1())
          .copyWith(completedRunsOverride: 2);
      expect(e.completedRunsOverride, 2);
      expect(e.copyWith(wicket: null).wicket, isNull);
      expect(e.copyWith(completedRunsOverride: null).completedRunsOverride, isNull);
      expect(e.copyWith(runs: 3).wicket, e.wicket); // untouched when not mentioned
    });
  });

  group('match result', () {
    const oneOver = CricketRules(
      overs: 1,
      lastManStands: false,
      maxOversPerBowler: null,
      allowedWickets: CricketRules.allWickets,
    );

    InningsResult firstInnings(int fours) => replay(
          [
            for (var i = 0; i < 6; i++)
              i < fours
                  ? CricketEvent.bat(i + 1, 'b1', 4, boundary: Boundary.four)
                  : CricketEvent.dot(i + 1, 'b1'),
          ],
          rules: oneOver,
        ); // 4 runs per four

    test('chasing side wins: by wickets, with balls left', () {
      final first = firstInnings(5); // 20 runs
      expect(first.runs, 20);
      final second = replay(
        [
          const CricketEvent.bat(1, 'b1', 6, boundary: Boundary.six),
          const CricketEvent.bat(2, 'b1', 6, boundary: Boundary.six),
          const CricketEvent.bat(3, 'b1', 6, boundary: Boundary.six),
          const CricketEvent.bat(4, 'b1', 4, boundary: Boundary.four),
        ],
        rules: oneOver,
        setup: setupFor(target: first.runs + 1),
      );
      final res = computeMatchResult(
        first: first,
        second: second,
        firstBattingSide: 'A',
        teamAName: 'Team A',
        teamBName: 'Team B',
      )!;
      expect(res.winner, CricketWinner.teamB);
      expect(res.text, 'Team B won by 7 wickets (2 balls left)');
    });

    test('defending side wins: by runs', () {
      final first = firstInnings(5);
      final second = replay(dots(1, 'b1', 6), rules: oneOver, setup: setupFor(target: 21));
      final res = computeMatchResult(
        first: first,
        second: second,
        firstBattingSide: 'B',
        teamAName: 'Team A',
        teamBName: 'Team B',
      )!;
      expect(res.winner, CricketWinner.teamB); // B batted first and defended
      expect(res.text, 'Team B won by 20 runs');
    });

    test('1 run / 1 wicket wording is singular', () {
      final first = firstInnings(1); // 4 runs
      final second = replay(
        [
          const CricketEvent.bat(1, 'b1', 4, boundary: Boundary.four),
          const CricketEvent.bat(2, 'b1', 1),
        ],
        rules: oneOver,
        setup: setupFor(target: 5, batting: ['a1', 'a2']),
      );
      expect(second.maxWickets, 1);
      final res = computeMatchResult(
        first: first,
        second: second,
        firstBattingSide: 'A',
        teamAName: 'A',
        teamBName: 'B',
      )!;
      expect(res.text, 'B won by 1 wicket (4 balls left)');
    });

    test('level scores after the chase ends is a tie', () {
      final first = firstInnings(5);
      final second = replay(
        [
          for (var i = 0; i < 5; i++) CricketEvent.bat(i + 1, 'b1', 4, boundary: Boundary.four),
          const CricketEvent.dot(6, 'b1'),
        ],
        rules: oneOver,
        setup: setupFor(target: 21),
      );
      expect(second.runs, 20);
      final res = computeMatchResult(
        first: first,
        second: second,
        firstBattingSide: 'A',
        teamAName: 'A',
        teamBName: 'B',
      )!;
      expect(res.winner, CricketWinner.tie);
      expect(res.text, 'Match tied');
    });

    test('undecided while the chase is still going', () {
      final first = firstInnings(5);
      final second = replay(dots(1, 'b1', 3), rules: oneOver, setup: setupFor(target: 21));
      expect(
        computeMatchResult(
            first: first, second: second, firstBattingSide: 'A', teamAName: 'A', teamBName: 'B'),
        isNull,
      );
      expect(chaseText(second, 'Team B'), 'Team B need 21 runs in 3 balls');
      expect(chaseText(first, 'Team A'), isNull); // no target on the first innings
    });
  });

  group('standings & net run rate', () {
    const rules = CricketRules(); // 2 / 1 / 1
    final teams = [
      (id: 'A', name: 'Alpha'),
      (id: 'B', name: 'Bravo'),
      (id: 'C', name: 'Charlie'),
    ];

    CricketMatchSummary m(
      String a,
      String b,
      CricketWinner w, {
      int runsA = 0,
      int runsB = 0,
      int ballsA = 36,
      int ballsB = 36,
      bool allOutA = false,
      bool allOutB = false,
      bool countsForNrr = true,
    }) =>
        CricketMatchSummary(
          teamAId: a,
          teamBId: b,
          winner: w,
          runsA: runsA,
          runsB: runsB,
          ballsFacedA: ballsA,
          ballsFacedB: ballsB,
          allOutA: allOutA,
          allOutB: allOutB,
          quotaBalls: 36,
          countsForNrr: countsForNrr,
        );

    test('points: win 2, tie 1, no result 1, loss 0', () {
      final rows = computeCricketStandings(
        teams: teams,
        matches: [
          m('A', 'B', CricketWinner.teamA, runsA: 40, runsB: 30),
          m('B', 'C', CricketWinner.tie, runsA: 30, runsB: 30),
          m('A', 'C', CricketWinner.noResult),
        ],
        rules: rules,
      );
      final byId = {for (final r in rows) r.teamId: r};
      expect(byId['A']!.points, 3); // win + no result
      expect(byId['B']!.points, 1); // loss + tie
      expect(byId['C']!.points, 2); // tie + no result
      expect(byId['A']!.won, 1);
      expect(byId['A']!.noResult, 1);
      expect(byId['B']!.tied, 1);
      expect(byId['B']!.lost, 1);
      expect(byId['A']!.played, 2);
    });

    test('NRR = runs/over scored minus runs/over conceded', () {
      final rows = computeCricketStandings(
        teams: teams,
        matches: [m('A', 'B', CricketWinner.teamA, runsA: 42, runsB: 30)], // both 6 overs
        rules: rules,
      );
      final a = rows.firstWhere((r) => r.teamId == 'A');
      final b = rows.firstWhere((r) => r.teamId == 'B');
      expect(a.nrr, closeTo(42 / 6 - 30 / 6, 1e-9)); // +2.0
      expect(b.nrr, closeTo(-2.0, 1e-9));
    });

    test('a side bowled out early is charged its full quota of overs', () {
      // B all out after only 3 overs (18 balls) for 20 — NRR still uses 6 overs.
      final rows = computeCricketStandings(
        teams: teams,
        matches: [
          m('A', 'B', CricketWinner.teamA,
              runsA: 36, runsB: 20, ballsA: 36, ballsB: 18, allOutB: true),
        ],
        rules: rules,
      );
      final b = rows.firstWhere((r) => r.teamId == 'B');
      expect(b.nrr, closeTo(20 / 6 - 36 / 6, 1e-9));
      // Without the rule it would have been 20/3 - 36/6.
      expect(b.nrr, isNot(closeTo(20 / 3 - 36 / 6, 1e-3)));
    });

    test('a chase that ends early on reaching the target uses the overs actually faced', () {
      final rows = computeCricketStandings(
        teams: teams,
        matches: [
          m('A', 'B', CricketWinner.teamB,
              runsA: 20, runsB: 21, ballsA: 36, ballsB: 24), // B chased down in 4 overs
        ],
        rules: rules,
      );
      final b = rows.firstWhere((r) => r.teamId == 'B');
      expect(b.nrr, closeTo(21 / 4 - 20 / 6, 1e-9));
    });

    test('no-result and walkover matches do not feed NRR', () {
      final rows = computeCricketStandings(
        teams: teams,
        matches: [
          m('A', 'B', CricketWinner.noResult, runsA: 99, runsB: 1),
          m('A', 'C', CricketWinner.teamA, runsA: 99, runsB: 0, countsForNrr: false),
        ],
        rules: rules,
      );
      for (final r in rows) {
        expect(r.nrr, 0);
      }
      expect(rows.firstWhere((r) => r.teamId == 'A').points, 3); // points still awarded
    });

    test('ranking order: points, then wins, then NRR', () {
      final rows = computeCricketStandings(
        teams: teams,
        matches: [
          // A and B each beat C once: 2 points and 1 win apiece, so NRR decides.
          m('A', 'C', CricketWinner.teamA, runsA: 30, runsB: 28),
          m('B', 'C', CricketWinner.teamA, runsA: 60, runsB: 10),
        ],
        rules: rules,
      );
      // A: 2 pts, B: 2 pts (same wins), B's NRR is much better.
      expect(rows.map((r) => r.teamId).toList(), ['B', 'A', 'C']);
      expect(rows.any((r) => r.unresolvedTie), isFalse);
    });

    test('exactly two teams level on everything: head-to-head decides', () {
      final rows = computeCricketStandings(
        teams: teams,
        matches: [
          // A beat B, B beat C, C beat A: all 2 points, 1 win each... three-way.
          // Make it two-way instead: A beat B, then both lose nothing else.
          m('A', 'B', CricketWinner.teamB, runsA: 30, runsB: 30), // B won (e.g. super over)
        ],
        rules: rules,
      );
      // NRR is exactly equal (30/6 vs 30/6 both ways) so h2h puts B first.
      expect(rows.first.teamId, 'B');
      expect(rows[1].teamId, 'A');
    });

    test('a three-way tie is flagged for the admin to settle', () {
      final rows = computeCricketStandings(
        teams: teams,
        matches: [
          // A beat B, B beat C, C beat A — a perfect cycle.
          m('A', 'B', CricketWinner.teamA, runsA: 30, runsB: 30),
          m('B', 'C', CricketWinner.teamA, runsA: 30, runsB: 30),
          m('C', 'A', CricketWinner.teamA, runsA: 30, runsB: 30),
        ],
        rules: rules,
      );
      expect(rows.every((r) => r.points == 2), isTrue);
      expect(rows.every((r) => r.unresolvedTie), isTrue);
    });

    test('two teams level with no meeting between them are flagged', () {
      final rows = computeCricketStandings(teams: teams, matches: const [], rules: rules);
      expect(rows.every((r) => r.unresolvedTie), isTrue);
    });

    test('custom points from the rules are used', () {
      final rows = computeCricketStandings(
        teams: teams,
        matches: [m('A', 'B', CricketWinner.teamA, runsA: 30, runsB: 20)],
        rules: const CricketRules(pointsWin: 4),
      );
      expect(rows.first.points, 4);
    });
  });

  group('commentary', () {
    String nameOf(String id) => {'a1': 'Ravi', 'b1': 'Sam', 'b2': 'Anil'}[id] ?? id;

    BallRecord rec(CricketEvent e, {List<CricketEvent> before = const []}) {
      final r = replay([...before, e]);
      return r.balls.last;
    }

    test('boundaries, runs and dots', () {
      expect(ballCommentary(rec(const CricketEvent.bat(1, 'b1', 4, boundary: Boundary.four)), nameOf),
          'Sam to Ravi, FOUR!');
      expect(ballCommentary(rec(const CricketEvent.bat(1, 'b1', 6, boundary: Boundary.six)), nameOf),
          'Sam to Ravi, SIX!');
      expect(ballCommentary(rec(const CricketEvent.bat(1, 'b1', 2)), nameOf), 'Sam to Ravi, 2 runs');
      expect(ballCommentary(rec(const CricketEvent.bat(1, 'b1', 1)), nameOf), 'Sam to Ravi, 1 run');
      expect(ballCommentary(rec(const CricketEvent.dot(1, 'b1')), nameOf), 'Sam to Ravi, no run');
    });

    test('extras and dead ball', () {
      expect(ballCommentary(rec(const CricketEvent.wide(1, 'b1')), nameOf), 'Sam to Ravi, Wide');
      expect(ballCommentary(rec(const CricketEvent.noBall(1, 'b1')), nameOf),
          'Sam to Ravi, No ball — free hit next');
      expect(
          ballCommentary(
              rec(const CricketEvent(seq: 1, bowlerId: 'b1', delivery: Delivery.deadBall)), nameOf),
          'Dead ball — bowled again.');
    });

    test('wickets name the batter and fielder', () {
      final bowled = rec(CricketEvent.wicketBall(1, 'b1', bowledA1()));
      expect(ballCommentary(bowled, nameOf), 'Sam to Ravi, OUT! Ravi is bowled!');
      final caught = rec(const CricketEvent.wicketBall(
        1,
        'b1',
        Wicket(kind: WicketKind.caught, outBatterId: 'a1', fielderId: 'b2', newBatterId: 'a3'),
      ));
      expect(ballCommentary(caught, nameOf), 'Sam to Ravi, OUT! Ravi is caught by Anil!');
    });

    test('names are resolved at read time (a rename changes the text, nothing stored)', () {
      final record = rec(const CricketEvent.bat(1, 'b1', 4, boundary: Boundary.four));
      expect(ballCommentary(record, (id) => 'Renamed-$id'), 'Renamed-b1 to Renamed-a1, FOUR!');
    });
  });
}
