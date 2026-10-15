import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/cricket_standings.dart';
import 'package:flow_sports_app/core/cricket/cricket_table.dart';
import 'package:flow_sports_app/core/cricket/match_result.dart';
import 'package:flow_sports_app/core/cricket/match_scoring.dart';
import 'package:flow_sports_app/core/cricket/special_result.dart';
import 'package:flow_sports_app/core/utils/match_export.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/models/team.dart';
import 'package:flutter_test/flutter_test.dart';

// No result and walkover: how they are recorded, who may use them, and what
// they do to the points table.

const _rules = CricketRules(overs: 5);

Team team(String id) => Team(id: id, sport: 'cricket', category: 'boys', name: 'T$id', season: '2026');

Match match({
  String a = 'a',
  String b = 'b',
  MatchStage stage = MatchStage.league,
  MatchStatus status = MatchStatus.upcoming,
  MatchResult? result,
  String? resultType,
  List<InningsRecord> innings = const [],
  int? scoreA,
  int? scoreB,
}) =>
    Match(
      id: '$a$b',
      sport: 'cricket',
      category: 'boys',
      season: '2026',
      stage: stage,
      matchNumber: 1,
      label: 'M',
      matchCode: 'L1',
      teamA: TeamRef(teamId: a, name: 'T$a'),
      teamB: TeamRef(teamId: b, name: 'T$b'),
      notifyTopic: '',
      status: status,
      result: result,
      resultType: resultType,
      rules: _rules,
      innings: innings,
      scoreA: scoreA,
      scoreB: scoreB,
    );

Match noResult(String a, String b, {List<InningsRecord> innings = const []}) => match(
      a: a,
      b: b,
      status: MatchStatus.completed,
      result: MatchResult.tie,
      resultType: ResultType.noResult,
      innings: innings,
    );

Match walkover(String winner, String loser) => match(
      a: winner,
      b: loser,
      status: MatchStatus.completed,
      result: MatchResult.teamA,
      resultType: ResultType.walkover,
    );

Match played(String a, String b, {required int ra, required int rb}) => match(
      a: a,
      b: b,
      status: MatchStatus.completed,
      result: ra > rb ? MatchResult.teamA : MatchResult.teamB,
      scoreA: ra,
      scoreB: rb,
      innings: [
        InningsRecord(
          batting: 'A',
          start: const InningsStart(strikerId: 'x', nonStrikerId: 'y'),
          runs: ra,
          wickets: 2,
          legalBalls: 30,
          ended: true,
          allOut: false,
        ),
        InningsRecord(
          batting: 'B',
          start: const InningsStart(strikerId: 'x', nonStrikerId: 'y'),
          runs: rb,
          wickets: 2,
          legalBalls: 30,
          ended: true,
          allOut: false,
        ),
      ],
    );

void main() {
  group('who can use them', () {
    test('a league match can be called off; a knockout cannot (it needs a winner)', () {
      expect(noResultProblem(match()), isNull);
      expect(noResultProblem(match(stage: MatchStage.knockout)), contains('needs a winner'));
      expect(noResultProblem(match(stage: MatchStage.friendly)), isNull);
    });

    test('a finished match cannot get a second result', () {
      final done = match(status: MatchStatus.completed, result: MatchResult.teamA);
      expect(noResultProblem(done), isNotNull);
      expect(walkoverProblem(done), isNotNull);
    });

    test('a walkover works in a knockout, needs both teams, and not once scoring started', () {
      expect(walkoverProblem(match(stage: MatchStage.knockout)), isNull);
      final unknown = Match(
        id: 'x', sport: 'cricket', category: 'boys', season: '2026', stage: MatchStage.knockout,
        matchNumber: 1, label: 'M', matchCode: 'KO2', notifyTopic: '',
        teamA: const TeamRef(teamId: 'a', name: 'Ta'), teamB: TeamRef.tbd,
      );
      expect(walkoverProblem(unknown), contains('Both teams'));
      final started = match(
        status: MatchStatus.live,
        innings: [
          const InningsRecord(
            batting: 'A',
            start: InningsStart(strikerId: 'x', nonStrikerId: 'y'),
            runs: 3,
            wickets: 0,
            legalBalls: 2,
            ended: false,
            allOut: false,
          ),
        ],
      );
      expect(walkoverProblem(started), contains('Scoring has already started'));
    });
  });

  group('what is written', () {
    test('no result: finished, marked, reason in the text', () {
      final f = noResultFields(' rain ');
      expect(f['resultType'], 'noResult');
      expect(f['status'], 'completed');
      expect(f['result'], 'tie'); // only so it counts as finished
      expect(f['resultText'], 'No result — rain');
      expect(noResultFields(null)['resultText'], 'No result');
      expect(noResultFields('  ')['resultText'], 'No result');
    });

    test('walkover: the chosen side wins, with its name in the text', () {
      final a = walkoverFields('A', 'Reds', 'Blues did not turn up');
      expect(a['result'], 'teamA');
      expect(a['resultType'], 'walkover');
      expect(a['resultText'], 'Reds won by walkover (Blues did not turn up)');
      expect(walkoverFields('B', 'Blues', null)['result'], 'teamB');
      expect(walkoverFields('B', 'Blues', null)['resultText'], 'Blues won by walkover');
    });
  });

  group('the points table', () {
    test('summary: no result shares the points and skips NRR; walkover is a win without NRR', () {
      final nr = summaryOfMatch(noResult('a', 'b'))!;
      expect(nr.winner, CricketWinner.noResult);
      expect(nr.countsForNrr, isFalse);
      final w = summaryOfMatch(walkover('a', 'b'))!;
      expect(w.winner, CricketWinner.teamA);
      expect(w.countsForNrr, isFalse);
    });

    test('no result: 1 point each, played +1, NR +1, no win/loss, no NRR', () {
      final rows = computeCricketStandingRows(
        teams: [team('a'), team('b')],
        leagueMatches: [noResult('a', 'b')],
      );
      for (final r in rows) {
        expect(r.points, 1);
        expect(r.played, 1);
        expect(r.noResult, 1);
        expect((r.won, r.lost, r.tied), (0, 0, 0));
        expect(r.nrr, 0);
      }
    });

    test('a no result after some play still leaves the runs out of net run rate', () {
      final withBalls = noResult('a', 'b', innings: [
        const InningsRecord(
          batting: 'A',
          start: InningsStart(strikerId: 'x', nonStrikerId: 'y'),
          runs: 90,
          wickets: 1,
          legalBalls: 12,
          ended: false,
          allOut: false,
        ),
      ]);
      final rows = computeCricketStandings(
        teams: [(id: 'a', name: 'Ta'), (id: 'b', name: 'Tb')],
        matches: [summaryOfMatch(withBalls)!],
        rules: _rules,
      );
      expect(rows.every((r) => r.runsFor == 0 && r.runsAgainst == 0), isTrue);
    });

    test('walkover: winner gets the win points, loser 0, and the others\' NRR is untouched', () {
      final base = [played('a', 'c', ra: 60, rb: 30), played('b', 'c', ra: 50, rb: 40)];
      final without = computeCricketStandingRows(teams: [team('a'), team('b'), team('c')], leagueMatches: base);
      final withWalkover = computeCricketStandingRows(
        teams: [team('a'), team('b'), team('c')],
        leagueMatches: [...base, walkover('a', 'b')],
      );
      final a = withWalkover.firstWhere((r) => r.teamId == 'a');
      final b = withWalkover.firstWhere((r) => r.teamId == 'b');
      expect(a.points, without.firstWhere((r) => r.teamId == 'a').points + 2);
      expect(b.points, without.firstWhere((r) => r.teamId == 'b').points);
      expect(a.nrr, without.firstWhere((r) => r.teamId == 'a').nrr);
      expect(b.nrr, without.firstWhere((r) => r.teamId == 'b').nrr);
      expect(a.played, 2);
      expect(b.lost, 1);
    });

    test('the CSV says "No result", not "Tie"', () {
      final csv = buildMatchesCsv([noResult('a', 'b')]);
      expect(csv, contains('No result'));
      expect(csv, isNot(contains('Tie')));
    });
  });
}
