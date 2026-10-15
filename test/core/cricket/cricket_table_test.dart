import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/cricket_standings.dart';
import 'package:flow_sports_app/core/cricket/cricket_table.dart';
import 'package:flow_sports_app/core/cricket/match_result.dart';
import 'package:flow_sports_app/core/cricket/match_scoring.dart';
import 'package:flow_sports_app/core/utils/sport_standings.dart';
import 'package:flow_sports_app/core/utils/standings_calculator.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/models/standing_row.dart';
import 'package:flow_sports_app/models/team.dart';
import 'package:flutter_test/flutter_test.dart';

// The cricket points table from finished matches' cached innings: points,
// wins, net run rate, head-to-head — and what counts as a genuine tie.

const _rules = CricketRules(overs: 5); // 30 balls an innings

Team team(String id) =>
    Team(id: id, sport: 'cricket', category: 'boys', name: 'T$id', season: '2026');

InningsRecord inn(String side, int runs, int balls, {bool allOut = false, int? maxOvers}) => InningsRecord(
      batting: side,
      start: InningsStart(strikerId: 'x', nonStrikerId: 'y', maxOvers: maxOvers),
      runs: runs,
      wickets: allOut ? 5 : 2,
      legalBalls: balls,
      ended: true,
      allOut: allOut,
    );

/// A finished league match: team [a] batted first with [ra]/[ballsA], [b] chased.
Match played(
  String a,
  String b, {
  required int ra,
  required int rb,
  int ballsA = 30,
  int ballsB = 30,
  bool allOutA = false,
  bool allOutB = false,
  int? chaseOvers,
  bool withInnings = true,
  CricketRules? rules = _rules,
  String id = '',
}) {
  final result = ra == rb ? MatchResult.tie : (ra > rb ? MatchResult.teamA : MatchResult.teamB);
  return Match(
    id: id.isEmpty ? '$a$b' : id,
    sport: 'cricket',
    category: 'boys',
    season: '2026',
    stage: MatchStage.league,
    matchNumber: 1,
    label: 'M',
    matchCode: 'L',
    teamA: TeamRef(teamId: a, name: 'T$a'),
    teamB: TeamRef(teamId: b, name: 'T$b'),
    notifyTopic: '',
    status: MatchStatus.completed,
    scoreA: ra,
    scoreB: rb,
    result: result,
    rules: rules,
    innings: withInnings
        ? [
            inn('A', ra, ballsA, allOut: allOutA),
            inn('B', rb, ballsB, allOut: allOutB, maxOvers: chaseOvers),
          ]
        : const [],
  );
}

void main() {
  group('one match → table input', () {
    test('runs, balls, all-out and quota come from the innings records', () {
      final s = summaryOfMatch(played('a', 'b', ra: 50, rb: 40, ballsA: 30, ballsB: 24, allOutB: true))!;
      expect((s.runsA, s.runsB, s.ballsFacedA, s.ballsFacedB), (50, 40, 30, 24));
      expect(s.allOutB, isTrue);
      expect((s.quotaBallsA, s.quotaBallsB), (30, 30));
      expect(s.winner, CricketWinner.teamA);
      expect(s.countsForNrr, isTrue);
    });

    test('a shortened chase uses its own quota', () {
      final s = summaryOfMatch(played('a', 'b', ra: 50, rb: 20, chaseOvers: 3, allOutB: true))!;
      expect((s.quotaBallsA, s.quotaBallsB), (30, 18));
    });

    test('not finished, or a team still unknown: nothing', () {
      final live = Match(
        id: 'x', sport: 'cricket', category: 'boys', season: '2026', stage: MatchStage.league,
        matchNumber: 1, label: 'M', matchCode: 'L', notifyTopic: '', status: MatchStatus.live,
        teamA: const TeamRef(teamId: 'a', name: 'Ta'), teamB: const TeamRef(teamId: 'b', name: 'Tb'),
      );
      expect(summaryOfMatch(live), isNull);
      final unknown = Match(
        id: 'x', sport: 'cricket', category: 'boys', season: '2026', stage: MatchStage.knockout,
        matchNumber: 1, label: 'M', matchCode: 'L', notifyTopic: '', status: MatchStatus.completed,
        result: MatchResult.teamA, teamA: const TeamRef(teamId: 'a', name: 'Ta'), teamB: TeamRef.tbd,
      );
      expect(summaryOfMatch(unknown), isNull);
    });

    test('a result without innings still earns points but does not feed NRR', () {
      final s = summaryOfMatch(played('a', 'b', ra: 40, rb: 30, withInnings: false))!;
      expect(s.countsForNrr, isFalse);
      expect(s.winner, CricketWinner.teamA);
    });
  });

  group('the table', () {
    test('ranks by points, then wins, then NRR', () {
      final rows = computeCricketStandingRows(
        teams: [team('a'), team('b'), team('c')],
        leagueMatches: [
          played('a', 'b', ra: 60, rb: 30), // a beats b
          played('a', 'c', ra: 40, rb: 38), // a beats c narrowly
          played('b', 'c', ra: 50, rb: 20), // b beats c
        ],
      );
      expect(rows.map((r) => r.teamId), ['a', 'b', 'c']);
      expect(rows.map((r) => r.points), [4, 2, 0]);
      expect(rows.map((r) => r.rank), [1, 2, 3]);
      expect(rows.first.nrr, isNotNull);
      expect(rows.first.tiedWithAnother, isFalse);
    });

    test('level on points: the better net run rate goes first', () {
      // a and b each win one and lose one; a's win was big, b's was small.
      final rows = computeCricketStandingRows(
        teams: [team('a'), team('b'), team('c')],
        leagueMatches: [
          played('a', 'c', ra: 80, rb: 20),
          played('c', 'a', ra: 40, rb: 30), // a loses a close one
          played('b', 'c', ra: 40, rb: 38),
          played('c', 'b', ra: 50, rb: 30), // b loses
        ],
      );
      final order = rows.map((r) => r.teamId).toList();
      expect(order.indexOf('a') < order.indexOf('b'), isTrue);
      final a = rows.firstWhere((r) => r.teamId == 'a');
      final b = rows.firstWhere((r) => r.teamId == 'b');
      expect(a.points, b.points);
      expect(a.nrr! > b.nrr!, isTrue);
      expect(a.tiedWithAnother, isFalse);
    });

    test('an all-out side is charged its full quota of overs', () {
      // b is bowled out for 10 in 12 balls; it still faced 30 balls' worth.
      final rows = computeCricketStandings(
        teams: const [(id: 'a', name: 'Ta'), (id: 'b', name: 'Tb')],
        matches: [summaryOfMatch(played('a', 'b', ra: 60, rb: 10, ballsB: 12, allOutB: true))!],
        rules: _rules,
      );
      final b = rows.firstWhere((r) => r.teamId == 'b');
      expect(b.oversFaced, 5.0); // 30 balls / 6, not 2.0
    });

    test('a shortened chase that ends all out is charged its own (shorter) quota in the table', () {
      final rows = computeCricketStandingRows(
        teams: [team('a'), team('b')],
        leagueMatches: [played('a', 'b', ra: 60, rb: 10, ballsB: 12, allOutB: true, chaseOvers: 3)],
      );
      final a = rows.firstWhere((r) => r.teamId == 'a');
      final b = rows.firstWhere((r) => r.teamId == 'b');
      // a faced 5.0 overs, b is charged 3.0 (its own quota), not 5.0.
      expect(b.nrr, closeTo(10 / 3 - 60 / 5, 1e-9));
      expect(a.nrr, closeTo(60 / 5 - 10 / 3, 1e-9));
    });

    test('head-to-head separates two teams level on points, wins and NRR', () {
      // a and b both 1 win; equal runs => equal NRR; a beat b directly.
      final rows = computeCricketStandingRows(
        teams: [team('a'), team('b')],
        leagueMatches: [played('a', 'b', ra: 40, rb: 30)],
      );
      expect(rows.map((r) => r.teamId), ['a', 'b']);
      expect(rows.every((r) => !r.tiedWithAnother), isTrue);
    });

    test('dead level: flagged, and separate tied pairs get separate tie keys', () {
      // Four teams, nobody has played anybody → all level at 0: one group of 4.
      final fresh = computeCricketStandingRows(
        teams: [team('a'), team('b'), team('c'), team('d')],
        leagueMatches: const [],
      );
      expect(fresh.every((r) => r.tiedWithAnother), isTrue);
      expect(fresh.map((r) => r.tieKey).toSet().length, 1);

      // Pair (a,b) level high up, pair (c,d) level at the bottom.
      final rows = computeCricketStandingRows(
        teams: [team('a'), team('b'), team('c'), team('d')],
        leagueMatches: [
          played('a', 'c', ra: 40, rb: 30),
          played('b', 'd', ra: 40, rb: 30),
          played('c', 'b', ra: 20, rb: 30),
          played('d', 'a', ra: 20, rb: 30),
        ],
      );
      // a: 2 wins 70 for 50 against; b: same; c, d: 0 wins.
      final byId = {for (final r in rows) r.teamId: r};
      expect(byId['a']!.tiedWithAnother, isTrue);
      expect(byId['c']!.tiedWithAnother, isTrue);
      expect(byId['a']!.tieKey, byId['b']!.tieKey);
      expect(byId['c']!.tieKey, byId['d']!.tieKey);
      expect(byId['a']!.tieKey, isNot(byId['c']!.tieKey));
    });

    test('uses the points of the match rules', () {
      final rows = computeCricketStandingRows(
        teams: [team('a'), team('b')],
        leagueMatches: [played('a', 'b', ra: 40, rb: 30, rules: const CricketRules(overs: 5, pointsWin: 4))],
      );
      expect(rows.first.points, 4);
    });

    test('a rules-less match counts for points only', () {
      final rows = computeCricketStandingRows(
        teams: [team('a'), team('b')],
        leagueMatches: [played('a', 'b', ra: 40, rb: 30, rules: null)],
      );
      expect(rows.first.teamId, 'a');
      expect(rows.first.points, 2);
    });
  });

  group('the bracket uses the same tie rules', () {
    // Five teams, 4 qualify. a, b, c beat both d and e by different margins
    // (so they are all separated by NRR); d and e lose the same way to
    // everyone and never meet, so they are dead level for 4th and 5th place
    // — unless [eLosesBigger], which gives e a worse net run rate.
    List<StandingRow> five({required bool eLosesBigger}) {
      final teams = [team('a'), team('b'), team('c'), team('d'), team('e')];
      return computeCricketStandingRows(
        teams: teams,
        leagueMatches: [
          for (final (w, runs) in [('a', 40), ('b', 41), ('c', 42)]) ...[
            played(w, 'd', ra: runs, rb: 30, id: '${w}d'),
            played(w, 'e', ra: runs + (eLosesBigger ? 15 : 0), rb: 30, id: '${w}e'),
          ],
        ],
      );
    }

    test('teams level at the cutoff widen the candidates and form the deciding cluster', () {
      final rows = five(eLosesBigger: false);
      expect(rows.map((r) => r.teamId).take(3), ['c', 'b', 'a']);
      expect(rows.skip(3).every((r) => r.tiedWithAnother), isTrue);
      final candidates = candidatesForTopFour(rows);
      expect(candidates.length, 5);
      final cluster = decidingTieCluster(candidates);
      expect(cluster!.map((r) => r.teamId).toSet(), {'d', 'e'});
      expect(topFourHasAmbiguousTie(rows), isTrue);
    });

    test('a clear NRR gap means no tie to settle', () {
      final rows = five(eLosesBigger: true);
      expect(rows.last.teamId, 'e');
      expect(rows.every((r) => !r.tiedWithAnother), isTrue);
      expect(decidingTieCluster(candidatesForTopFour(rows)), isNull);
      expect(topFourHasAmbiguousTie(rows), isFalse);
    });

    test('exactly the cutoff tie: 2 qualify, 2nd and 3rd dead level', () {
      final rows = computeCricketStandingRows(
        teams: [team('a'), team('b'), team('c')],
        leagueMatches: [
          played('a', 'b', ra: 50, rb: 40),
          played('a', 'c', ra: 50, rb: 40),
          played('b', 'c', ra: 40, rb: 40), // b and c tie; level on points, wins and NRR vs a
        ],
      );
      // b: 1 pt (tie), c: 1 pt (tie), identical records → level.
      expect(rows.first.teamId, 'a');
      expect(rows[1].tiedWithAnother && rows[2].tiedWithAnother, isTrue);
      final cand = candidatesForTopFour(rows, cutoffCount: 2);
      expect(cand.length, 3);
      final cluster = decidingTieCluster(cand, cutoffCount: 2);
      expect(cluster!.map((r) => r.teamId).toSet(), {'b', 'c'});
      expect(topFourHasAmbiguousTie(rows, cutoffCount: 2), isTrue);
    });
  });

  group('sport dispatch and the line under each team', () {
    test('cricket uses the cricket table, badminton its own', () {
      final c = computeSportStandings(
        sport: 'cricket',
        teams: [team('a'), team('b')],
        leagueMatches: [played('a', 'b', ra: 40, rb: 30)],
      );
      expect(c.first.nrr, isNotNull);
      final b = computeSportStandings(
        sport: 'badminton',
        teams: [team('a'), team('b')],
        leagueMatches: const [],
      );
      expect(b.first.nrr, isNull);
    });

    test('detail text: badminton shows points scored, cricket shows NRR', () {
      expect(standingDetail(StandingRow(teamId: 'a', teamName: 'A')..played = 5..won = 4..lost = 1..pointsScored = 96),
          'P 5 · W 4 · T 0 · L 1 · Scored 96');
      final cricket = StandingRow(teamId: 'a', teamName: 'A')
        ..played = 3
        ..won = 2
        ..lost = 1
        ..nrr = 1.23456;
      expect(standingDetail(cricket), 'P 3 · W 2 · L 1 · T 0 · NRR +1.235');
      cricket
        ..nrr = -0.5
        ..noResult = 1;
      expect(standingDetail(cricket), 'P 3 · W 2 · L 1 · T 0 · NR 1 · NRR −0.500');
    });
  });
}
