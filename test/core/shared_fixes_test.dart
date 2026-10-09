import 'package:flow_sports_app/core/utils/bracket_resolver.dart';
import 'package:flow_sports_app/core/utils/match_export.dart';
import 'package:flow_sports_app/core/utils/podium_resolver.dart';
import 'package:flow_sports_app/core/utils/standings_calculator.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/models/standing_row.dart';
import 'package:flow_sports_app/models/team.dart';
import 'package:flutter_test/flutter_test.dart';

Team team(String id) => Team(id: id, sport: 'badminton', category: 'boys', name: 'Team $id', season: '2026');

Match league(String id, String a, String b,
        {MatchResult? result, MatchStatus? status, int scoreA = 0, int scoreB = 0}) =>
    Match(
      id: id,
      sport: 'badminton',
      category: 'boys',
      season: '2026',
      stage: MatchStage.league,
      matchNumber: 1,
      label: 'M',
      matchCode: 'L1',
      teamA: TeamRef(teamId: a, name: 'Team $a'),
      teamB: TeamRef(teamId: b, name: 'Team $b'),
      scoreA: result == null ? null : scoreA,
      scoreB: result == null ? null : scoreB,
      result: result,
      status: status ?? (result == null ? MatchStatus.upcoming : MatchStatus.completed),
      notifyTopic: 'x',
    );

List<StandingRow> seeds(int n) => [for (var i = 1; i <= n; i++) StandingRow(teamId: 't$i', teamName: 'T$i')];

/// 4-team bracket with a played KO1 (A wins), KO2 and KO3 resolved.
List<Match> ko({
  MatchResult ko1 = MatchResult.teamA,
  MatchResult? ko2Result,
  MatchResult? ko3Result,
  MatchResult? finalResult,
}) {
  final base = generateKnockoutMatches(top4Seeds: seeds(4), sport: 'badminton', category: 'boys', season: '2026');
  Match by(String code) => base.firstWhere((m) => m.matchCode == code);
  Match played(Match m, MatchResult r) => Match(
        id: m.id.isEmpty ? m.matchCode : m.id,
        sport: m.sport,
        category: m.category,
        season: m.season,
        stage: m.stage,
        matchNumber: m.matchNumber,
        label: m.label,
        matchCode: m.matchCode,
        teamA: m.teamA,
        teamB: m.teamB,
        teamASource: m.teamASource,
        teamBSource: m.teamBSource,
        scoreA: r == MatchResult.teamA ? 21 : 10,
        scoreB: r == MatchResult.teamB ? 21 : 10,
        result: r,
        status: MatchStatus.completed,
        notifyTopic: m.notifyTopic,
      );
  Match withId(Match m) => Match(
        id: m.matchCode,
        sport: m.sport,
        category: m.category,
        season: m.season,
        stage: m.stage,
        matchNumber: m.matchNumber,
        label: m.label,
        matchCode: m.matchCode,
        teamA: m.teamA,
        teamB: m.teamB,
        teamASource: m.teamASource,
        teamBSource: m.teamBSource,
        notifyTopic: m.notifyTopic,
      );

  var k1 = played(by('KO1'), ko1);
  var k2 = ko2Result == null ? withId(by('KO2')) : played(by('KO2'), ko2Result);
  var k3 = withId(by('KO3'));
  var kf = withId(by('KOF'));
  // Resolve downstream slots the way the app does after each save.
  void resolve(Match completed) {
    final others = [k1, k2, k3, kf].where((m) => m.id != completed.id).toList();
    for (final u in resolveDependentSlots(completed: completed, otherKnockoutMatches: others)) {
      if (u.id == k1.id) k1 = u;
      if (u.id == k2.id) k2 = u;
      if (u.id == k3.id) k3 = u;
      if (u.id == kf.id) kf = u;
    }
  }

  resolve(k1);
  if (ko2Result != null) resolve(k2);
  if (ko3Result != null) {
    k3 = played(k3, ko3Result);
    resolve(k3);
  }
  if (finalResult != null) kf = played(kf, finalResult);
  return [k1, k2, k3, kf];
}

void main() {
  group('a reset match no longer counts (stale result)', () {
    test('hasFinalResult needs both completed status and a result', () {
      expect(league('m', 'a', 'b', result: MatchResult.teamA).hasFinalResult, isTrue);
      expect(league('m', 'a', 'b', result: MatchResult.teamA, status: MatchStatus.upcoming).hasFinalResult, isFalse);
      expect(league('m', 'a', 'b', result: MatchResult.teamA, status: MatchStatus.live).hasFinalResult, isFalse);
      expect(league('m', 'a', 'b').hasFinalResult, isFalse);
    });

    test('standings ignore a match that was reset to upcoming but still carries its old result', () {
      final rows = computeStandings(
        teams: [team('a'), team('b')],
        leagueMatches: [
          league('m1', 'a', 'b', result: MatchResult.teamA, scoreA: 21, scoreB: 15, status: MatchStatus.upcoming),
        ],
      );
      expect(rows.every((r) => r.played == 0 && r.points == 0 && r.pointsScored == 0), isTrue);
    });

    test('a completed match with a result still counts', () {
      final rows = computeStandings(
        teams: [team('a'), team('b')],
        leagueMatches: [league('m1', 'a', 'b', result: MatchResult.teamA, scoreA: 21, scoreB: 15)],
      );
      expect(rows.firstWhere((r) => r.teamId == 'a').points, 2);
      expect(rows.firstWhere((r) => r.teamId == 'a').pointsScored, 21);
    });

    test('the podium is undecided when the Final was reopened but kept its old result', () {
      final done = ko(ko2Result: MatchResult.teamA, ko3Result: MatchResult.teamA, finalResult: MatchResult.teamA);
      expect(computePodium(done), isNotNull);
      final reopened = [
        for (final m in done)
          if (m.matchCode == 'KOF')
            Match(
              id: m.id,
              sport: m.sport,
              category: m.category,
              season: m.season,
              stage: m.stage,
              matchNumber: m.matchNumber,
              label: m.label,
              matchCode: m.matchCode,
              teamA: m.teamA,
              teamB: m.teamB,
              scoreA: m.scoreA,
              scoreB: m.scoreB,
              result: m.result, // stale
              status: MatchStatus.upcoming,
              notifyTopic: m.notifyTopic,
            )
          else
            m,
      ];
      expect(computePodium(reopened), isNull);
    });
  });

  group('correcting a knockout result safely', () {
    test('dependentsOf finds the matches a result feeds', () {
      final all = ko();
      expect(dependentsOf('KO1', all).map((m) => m.matchCode).toSet(), {'KO3', 'KOF'});
      expect(dependentsOf('KO2', all).map((m) => m.matchCode), ['KO3']);
      expect(dependentsOf('KOF', all), isEmpty);
    });

    test('re-saving the same winner (a score fix) is never blocked', () {
      final all = ko(ko2Result: MatchResult.teamA, ko3Result: MatchResult.teamA, finalResult: MatchResult.teamA);
      final ko1 = all.firstWhere((m) => m.matchCode == 'KO1');
      final updates = resolveDependentSlots(
        completed: ko1,
        otherKnockoutMatches: all.where((m) => m.id != ko1.id).toList(),
      );
      expect(updates, isNotEmpty);
      expect(staleDependentUpdates(updates, all), isEmpty);
    });

    test('changing the winner of KO1 after KO3/Final were played is reported', () {
      final all = ko(ko2Result: MatchResult.teamA, ko3Result: MatchResult.teamA, finalResult: MatchResult.teamA);
      final ko1 = all.firstWhere((m) => m.matchCode == 'KO1');
      // Admin flips KO1 so team B wins instead.
      final flipped = Match(
        id: ko1.id,
        sport: ko1.sport,
        category: ko1.category,
        season: ko1.season,
        stage: ko1.stage,
        matchNumber: ko1.matchNumber,
        label: ko1.label,
        matchCode: ko1.matchCode,
        teamA: ko1.teamA,
        teamB: ko1.teamB,
        scoreA: 10,
        scoreB: 21,
        result: MatchResult.teamB,
        status: MatchStatus.completed,
        notifyTopic: ko1.notifyTopic,
      );
      final updates = resolveDependentSlots(
        completed: flipped,
        otherKnockoutMatches: all.where((m) => m.id != ko1.id).toList(),
      );
      final stale = staleDependentUpdates(updates, all);
      expect(stale.map((m) => m.matchCode).toSet(), {'KO3', 'KOF'});
    });

    test('changing the winner is fine while nothing downstream has started', () {
      final all = ko(); // only KO1 played; KO3 and the Final are untouched
      final ko1 = all.firstWhere((m) => m.matchCode == 'KO1');
      final flipped = Match(
        id: ko1.id,
        sport: ko1.sport,
        category: ko1.category,
        season: ko1.season,
        stage: ko1.stage,
        matchNumber: ko1.matchNumber,
        label: ko1.label,
        matchCode: ko1.matchCode,
        teamA: ko1.teamA,
        teamB: ko1.teamB,
        scoreA: 10,
        scoreB: 21,
        result: MatchResult.teamB,
        status: MatchStatus.completed,
        notifyTopic: ko1.notifyTopic,
      );
      final updates = resolveDependentSlots(
        completed: flipped,
        otherKnockoutMatches: all.where((m) => m.id != ko1.id).toList(),
      );
      expect(updates, isNotEmpty);
      expect(staleDependentUpdates(updates, all), isEmpty);
    });

    test('isStarted: a live or completed match counts as started', () {
      Match m(MatchStatus s, {MatchResult? r}) => league('x', 'a', 'b', status: s, result: r);
      expect(isStarted(m(MatchStatus.upcoming)), isFalse);
      expect(isStarted(m(MatchStatus.live)), isTrue);
      expect(isStarted(m(MatchStatus.completed, r: MatchResult.teamA)), isTrue);
    });

    test('reopening KO1 sends the slots it filled back to TBD', () {
      final all = ko(); // KO1 played: Final slot A and KO3 slot A now resolved
      final ko3 = all.firstWhere((m) => m.matchCode == 'KO3');
      final kof = all.firstWhere((m) => m.matchCode == 'KOF');
      expect(ko3.teamA.isTbd, isFalse); // loser of KO1
      expect(kof.teamA.isTbd, isFalse); // winner of KO1
      final cleared = unresolveDependentSlots('KO1', dependentsOf('KO1', all));
      final ko3After = cleared.firstWhere((m) => m.matchCode == 'KO3');
      final kofAfter = cleared.firstWhere((m) => m.matchCode == 'KOF');
      expect(ko3After.teamA.isTbd, isTrue);
      expect(kofAfter.teamA.isTbd, isTrue);
      // Slots fed by other matches are untouched.
      expect(ko3After.teamB.teamId, ko3.teamB.teamId);
      expect(kofAfter.teamB.teamId, kof.teamB.teamId);
    });
  });

  group('viewer-writable counters can never crash a screen', () {
    test('non-integer or odd entries read as 0, valid ones pass through', () {
      expect(parseCountMap({'thumbsUp': 3, 'fire': 'a', 'wow': 2.5, 'x': null}),
          {'thumbsUp': 3, 'fire': 0, 'wow': 0, 'x': 0});
      expect(parseCountMap(null), isEmpty);
      expect(parseCountMap('garbage'), isEmpty);
      expect(parseCountMap(<String, dynamic>{}), isEmpty);
    });
  });

  group('CSV cells are safe to open in a spreadsheet', () {
    test('csvSafe prefixes formula starters only', () {
      expect(csvSafe('=SUM(A1)'), "'=SUM(A1)");
      expect(csvSafe('+1'), "'+1");
      expect(csvSafe('-2'), "'-2");
      expect(csvSafe('@x'), "'@x");
      expect(csvSafe('Ravi & Sam'), 'Ravi & Sam');
      expect(csvSafe(''), '');
    });

    test('a team named like a formula is neutralised in the export', () {
      final m = Match(
        id: '1',
        sport: 'badminton',
        category: 'boys',
        season: '2026',
        stage: MatchStage.league,
        matchNumber: 1,
        label: '=HYPERLINK("x")',
        matchCode: 'L1',
        teamA: const TeamRef(teamId: 'a', name: '=1+1'),
        teamB: const TeamRef(teamId: 'b', name: 'Normal'),
        notifyTopic: 'x',
      );
      final csv = buildMatchesCsv([m]);
      expect(csv.contains("'=1+1"), isTrue);
      expect(csv.contains("'=HYPERLINK"), isTrue);
      expect(csv.contains(',=1+1'), isFalse);
    });
  });
}
