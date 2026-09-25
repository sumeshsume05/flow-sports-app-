import 'package:flutter_test/flutter_test.dart';

import 'package:flow_sports_app/core/utils/bracket_resolver.dart';
import 'package:flow_sports_app/core/utils/match_export.dart';
import 'package:flow_sports_app/core/utils/match_grouping.dart';
import 'package:flow_sports_app/core/utils/podium_resolver.dart';
import 'package:flow_sports_app/core/utils/round_robin.dart';
import 'package:flow_sports_app/core/utils/standings_calculator.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/models/standing_row.dart';
import 'package:flow_sports_app/models/team.dart';

Team _team(String id, String name) =>
    Team(id: id, sport: 'badminton', category: 'boys', name: name, season: '2026');

void main() {
  group('generateLeagueMatches', () {
    test('8 teams produce 28 matches, every pair exactly once', () {
      final teams = List.generate(8, (i) => _team('t$i', 'Team $i'));
      final matches = generateLeagueMatches(
        teams: teams,
        sport: 'badminton',
        category: 'boys',
        season: '2026',
      );
      expect(matches.length, 28);

      final pairs = matches.map((m) => {m.teamA.teamId, m.teamB.teamId}).toSet();
      expect(pairs.length, 28); // no duplicate pairings
    });

    test('6 teams produce 15 matches', () {
      final teams = List.generate(6, (i) => _team('t$i', 'Team $i'));
      final matches = generateLeagueMatches(
        teams: teams,
        sport: 'badminton',
        category: 'girls',
        season: '2026',
      );
      expect(matches.length, 15);
    });
  });

  group('computeStandings', () {
    test('win=2, tie=1, loss=0, sorted by points descending', () {
      final teams = [_team('a', 'A'), _team('b', 'B'), _team('c', 'C')];
      final matches = [
        Match(
          id: 'm1',
          sport: 'badminton',
          category: 'boys',
          season: '2026',
          stage: MatchStage.league,
          matchNumber: 1,
          label: 'Match 1',
          matchCode: 'L1',
          teamA: const TeamRef(teamId: 'a', name: 'A'),
          teamB: const TeamRef(teamId: 'b', name: 'B'),
          scoreA: 21,
          scoreB: 15,
          result: MatchResult.teamA,
          status: MatchStatus.completed,
          notifyTopic: 'badminton_boys',
        ),
        Match(
          id: 'm2',
          sport: 'badminton',
          category: 'boys',
          season: '2026',
          stage: MatchStage.league,
          matchNumber: 2,
          label: 'Match 2',
          matchCode: 'L2',
          teamA: const TeamRef(teamId: 'a', name: 'A'),
          teamB: const TeamRef(teamId: 'c', name: 'C'),
          scoreA: 18,
          scoreB: 18,
          result: MatchResult.tie,
          status: MatchStatus.completed,
          notifyTopic: 'badminton_boys',
        ),
      ];

      final standings = computeStandings(teams: teams, leagueMatches: matches);
      final byId = {for (final s in standings) s.teamId: s};

      expect(byId['a']!.points, 3); // win (2) + tie (1)
      expect(byId['a']!.won, 1);
      expect(byId['a']!.tied, 1);
      expect(byId['b']!.points, 0);
      expect(byId['b']!.lost, 1);
      expect(byId['c']!.points, 1);
      expect(byId['c']!.tied, 1);

      expect(standings.first.teamId, 'a'); // highest points ranked first
    });

    test('unplayed matches (no result) are ignored', () {
      final teams = [_team('a', 'A'), _team('b', 'B')];
      final matches = [
        Match(
          id: 'm1',
          sport: 'badminton',
          category: 'boys',
          season: '2026',
          stage: MatchStage.league,
          matchNumber: 1,
          label: 'Match 1',
          matchCode: 'L1',
          teamA: const TeamRef(teamId: 'a', name: 'A'),
          teamB: const TeamRef(teamId: 'b', name: 'B'),
          notifyTopic: 'badminton_boys',
        ),
      ];
      final standings = computeStandings(teams: teams, leagueMatches: matches);
      expect(standings.every((s) => s.played == 0), isTrue);
    });

    test('points-scored breaks a tie on points automatically', () {
      final teams = [_team('a', 'A'), _team('b', 'B'), _team('c', 'C')];
      Match win(String id, String teamAId, String teamBId, int scoreA, int scoreB) => Match(
            id: id,
            sport: 'badminton',
            category: 'boys',
            season: '2026',
            stage: MatchStage.league,
            matchNumber: 1,
            label: 'Match 1',
            matchCode: 'L1',
            teamA: TeamRef(teamId: teamAId, name: teamAId),
            teamB: TeamRef(teamId: teamBId, name: teamBId),
            scoreA: scoreA,
            scoreB: scoreB,
            result: scoreA > scoreB ? MatchResult.teamA : MatchResult.teamB,
            status: MatchStatus.completed,
            notifyTopic: 'badminton_boys',
          );

      // A and B both finish with 2 points (one win each) but A scored more
      // total points across its matches, so A should rank above B without
      // any tie flag — only C, sitting alone, is untouched.
      final matches = [
        win('m1', 'a', 'c', 21, 5), // A beats C 21-5
        win('m2', 'b', 'c', 21, 18), // B beats C 21-18
      ];
      final standings = computeStandings(teams: teams, leagueMatches: matches);
      final byId = {for (final s in standings) s.teamId: s};

      expect(byId['a']!.points, byId['b']!.points); // both 2 pts
      expect(byId['a']!.pointsScored, 21);
      expect(byId['b']!.pointsScored, 21); // scored equally too here...
      // ...so with identical scored totals, this genuinely is a tie:
      expect(byId['a']!.tiedWithAnother, isTrue);
      expect(byId['b']!.tiedWithAnother, isTrue);

      // Now give A a deuce win (badminton games can extend past 21) so its
      // scored total no longer matches B's — no longer a tie.
      final matches2 = [
        win('m1', 'a', 'c', 23, 21), // A wins 23-21 in deuce
        win('m2', 'b', 'c', 21, 18),
      ];
      final standings2 = computeStandings(teams: teams, leagueMatches: matches2);
      final byId2 = {for (final s in standings2) s.teamId: s};
      expect(byId2['a']!.pointsScored, greaterThan(byId2['b']!.pointsScored));
      expect(byId2['a']!.tiedWithAnother, isFalse);
      expect(byId2['b']!.tiedWithAnother, isFalse);
      expect(standings2.first.teamId, 'a'); // ranked above B by points scored
    });
  });

  group('decidingTieCluster', () {
    StandingRow row(String id, int points, int scored) {
      final r = StandingRow(teamId: id, teamName: id);
      r.points = points;
      r.pointsScored = scored;
      return r;
    }

    test('only the group tied at the 4th-place cutoff is the deciding cluster', () {
      // Reported scenario: 6 girls teams. Top 3 all 6pts/83 (safely
      // qualified no matter their mutual order) and bottom 3 all 4pts/72
      // (contesting the single remaining spot). Only the bottom group should
      // come back as the deciding cluster — not the top group.
      final candidates = [
        row('A', 6, 83),
        row('B', 6, 83),
        row('C', 6, 83),
        row('D', 4, 72),
        row('E', 4, 72),
        row('F', 4, 72),
      ];
      final cluster = decidingTieCluster(candidates);
      expect(cluster, isNotNull);
      expect(cluster!.map((r) => r.teamId).toSet(), {'D', 'E', 'F'});
    });

    test('null when the top 4 are unambiguous (no one below is tied with 4th)', () {
      final candidates = [
        row('A', 8, 90),
        row('B', 6, 83),
        row('C', 6, 83),
        row('D', 4, 72),
      ];
      expect(decidingTieCluster(candidates), isNull);
    });

    test('extends upward too if 3rd place is also tied with the cutoff group', () {
      final candidates = [
        row('A', 8, 90),
        row('B', 4, 72),
        row('C', 4, 72),
        row('D', 4, 72), // cutoff (index 3)
        row('E', 4, 72), // pulled in from below, tied with the cutoff
        row('F', 2, 50), // not tied — outside the cluster
      ];
      final cluster = decidingTieCluster(candidates);
      expect(cluster!.map((r) => r.teamId).toSet(), {'B', 'C', 'D', 'E'});
    });
  });

  group('generateTiebreakerMatches', () {
    test('2 tied teams produce exactly 1 match', () {
      final matches = generateTiebreakerMatches(
        tiedTeams: [
          StandingRow(teamId: 'a', teamName: 'A'),
          StandingRow(teamId: 'b', teamName: 'B'),
        ],
        sport: 'badminton',
        category: 'boys',
        season: '2026',
        round: 1,
      );
      expect(matches.length, 1);
      expect(matches.first.stage, MatchStage.tiebreaker);
      expect(matches.first.matchCode, 'TB1_1');
      expect(matches.first.tiebreakerRound, 1);
    });

    test('3 tied teams produce a full mini round-robin (3 matches)', () {
      final matches = generateTiebreakerMatches(
        tiedTeams: [
          StandingRow(teamId: 'a', teamName: 'A'),
          StandingRow(teamId: 'b', teamName: 'B'),
          StandingRow(teamId: 'c', teamName: 'C'),
        ],
        sport: 'badminton',
        category: 'boys',
        season: '2026',
        round: 1,
      );
      expect(matches.length, 3);
      expect(matches.every((m) => m.stage == MatchStage.tiebreaker), isTrue);
      final pairs = matches.map((m) => {m.teamA.teamId, m.teamB.teamId}).toSet();
      expect(pairs.length, 3);
    });
  });

  group('resolveTiebreakerOrder', () {
    Match tbMatch(String teamAId, String teamBId, int scoreA, int scoreB) => Match(
          id: 'tb1',
          sport: 'badminton',
          category: 'boys',
          season: '2026',
          stage: MatchStage.tiebreaker,
          matchNumber: 1,
          label: 'Tie-Breaker',
          matchCode: 'TB1',
          teamA: TeamRef(teamId: teamAId, name: teamAId),
          teamB: TeamRef(teamId: teamBId, name: teamBId),
          scoreA: scoreA,
          scoreB: scoreB,
          result: Match.computeResult(scoreA, scoreB),
          status: MatchStatus.completed,
          notifyTopic: 'badminton_boys',
        );

    test('winner of the tie-breaker ranks first', () {
      final group = [
        StandingRow(teamId: 'a', teamName: 'A'),
        StandingRow(teamId: 'b', teamName: 'B'),
      ];
      final resolved = resolveTiebreakerOrder(
        tiedGroup: group,
        tiebreakerMatches: [tbMatch('a', 'b', 15, 21)], // B wins
      );
      expect(resolved.first.teamId, 'b');
      expect(resolved.first.tiedWithAnother, isFalse);
      expect(resolved.last.tiedWithAnother, isFalse);
    });

    test('a still-level tie-breaker keeps tiedWithAnother true', () {
      final group = [
        StandingRow(teamId: 'a', teamName: 'A'),
        StandingRow(teamId: 'b', teamName: 'B'),
      ];
      final resolved = resolveTiebreakerOrder(
        tiedGroup: group,
        tiebreakerMatches: [tbMatch('a', 'b', 18, 18)], // tie
      );
      expect(resolved.every((r) => r.tiedWithAnother), isTrue);
    });
  });

  group('resolveTieChain', () {
    Match tbMatch(String round, int roundNumber, String teamAId, String teamBId, int scoreA, int scoreB, int n) =>
        Match(
          id: '$round-$n',
          sport: 'badminton',
          category: 'boys',
          season: '2026',
          stage: MatchStage.tiebreaker,
          matchNumber: n,
          label: 'Tie-Breaker',
          matchCode: 'TB${roundNumber}_$n',
          teamA: TeamRef(teamId: teamAId, name: teamAId),
          teamB: TeamRef(teamId: teamBId, name: teamBId),
          scoreA: scoreA,
          scoreB: scoreB,
          result: Match.computeResult(scoreA, scoreB),
          status: MatchStatus.completed,
          notifyTopic: 'badminton_boys',
          tiebreakerRound: roundNumber,
        );

    List<StandingRow> cluster() => [
          StandingRow(teamId: 'A', teamName: 'A'),
          StandingRow(teamId: 'B', teamName: 'B'),
          StandingRow(teamId: 'C', teamName: 'C'),
        ];

    test(
        'a round that itself ends in another full tie is NOT treated as resolved '
        '(reported bug: Generate Bracket was enabling itself here)', () {
      // A beats B, B beats C, C beats A — a 3-way cycle where every team
      // finishes round 1 with 1 win/1 loss and identical total score (36),
      // exactly like the reported scenario (all three level after round 1).
      final round1 = [
        tbMatch('r1', 1, 'A', 'B', 21, 15, 1),
        tbMatch('r1', 1, 'B', 'C', 21, 15, 2),
        tbMatch('r1', 1, 'C', 'A', 21, 15, 3),
      ];
      final result = resolveTieChain(originalCluster: cluster(), allTiebreakerMatches: round1);

      expect(result.contestedGroup, isNotNull);
      expect(result.contestedGroup!.map((r) => r.teamId).toSet(), {'A', 'B', 'C'});
      expect(result.nextRound, 2);
      // Round 1 was completed (not "in progress"), just didn't resolve anything.
      expect(result.contestedGroupMatches, isEmpty); // nothing scheduled yet for round 2
    });

    test('a round that fully resolves the order leaves no contested group', () {
      final round1 = [
        tbMatch('r1', 1, 'A', 'B', 21, 10, 1), // A beats B
        tbMatch('r1', 1, 'A', 'C', 21, 10, 2), // A beats C
        tbMatch('r1', 1, 'B', 'C', 21, 10, 3), // B beats C
      ];
      final result = resolveTieChain(originalCluster: cluster(), allTiebreakerMatches: round1);

      expect(result.contestedGroup, isNull);
      expect(result.order.map((r) => r.teamId).toList(), ['A', 'B', 'C']);
    });

    test('a round that partially resolves recurses into just the still-tied pair', () {
      final round1 = [
        tbMatch('r1', 1, 'A', 'B', 21, 10, 1), // A beats B
        tbMatch('r1', 1, 'A', 'C', 21, 10, 2), // A beats C
        tbMatch('r1', 1, 'B', 'C', 15, 15, 3), // B and C tie with each other
      ];
      final result = resolveTieChain(originalCluster: cluster(), allTiebreakerMatches: round1);

      expect(result.contestedGroup, isNotNull);
      expect(result.contestedGroup!.map((r) => r.teamId).toSet(), {'B', 'C'});
      expect(result.nextRound, 2);
      expect(result.order.first.teamId, 'A'); // A's resolved position is kept
    });

    test('a completed round 2 among the still-tied pair resolves the whole cluster', () {
      final round1 = [
        tbMatch('r1', 1, 'A', 'B', 21, 10, 1),
        tbMatch('r1', 1, 'A', 'C', 21, 10, 2),
        tbMatch('r1', 1, 'B', 'C', 15, 15, 3), // B/C still tied after round 1
      ];
      final round2 = [tbMatch('r2', 2, 'B', 'C', 21, 18, 1)]; // B wins round 2
      final result =
          resolveTieChain(originalCluster: cluster(), allTiebreakerMatches: [...round1, ...round2]);

      expect(result.contestedGroup, isNull);
      expect(result.order.map((r) => r.teamId).toList(), ['A', 'B', 'C']);
    });
  });

  group('generateKnockoutMatches + resolveDependentSlots', () {
    List<StandingRow> seeds() {
      final rows = [
        StandingRow(teamId: 's1', teamName: 'Seed1'),
        StandingRow(teamId: 's2', teamName: 'Seed2'),
        StandingRow(teamId: 's3', teamName: 'Seed3'),
        StandingRow(teamId: 's4', teamName: 'Seed4'),
      ];
      for (var i = 0; i < rows.length; i++) {
        rows[i].rank = i + 1;
      }
      return rows;
    }

    test('creates KO1, KO2 resolved and KO3, KOF as TBD', () {
      final matches = generateKnockoutMatches(
        top4Seeds: seeds(),
        sport: 'badminton',
        category: 'boys',
        season: '2026',
      );
      final byCode = {for (final m in matches) m.matchCode: m};

      expect(byCode['KO1']!.teamA.name, 'Seed1');
      expect(byCode['KO1']!.teamB.name, 'Seed2');
      expect(byCode['KO2']!.teamA.name, 'Seed3');
      expect(byCode['KO2']!.teamB.name, 'Seed4');
      expect(byCode['KO3']!.teamA.isTbd, isTrue);
      expect(byCode['KOF']!.teamA.isTbd, isTrue);
    });

    test('KO1 winner advances directly to Final, loser drops to KO3', () {
      final matches = generateKnockoutMatches(
        top4Seeds: seeds(),
        sport: 'badminton',
        category: 'boys',
        season: '2026',
      ).map((m) => Match(
            id: m.matchCode, // fake ids matching code, for test simplicity
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
          )).toList();

      final ko1 = matches.firstWhere((m) => m.matchCode == 'KO1');
      final completedKo1 = Match(
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
        scoreA: 21,
        scoreB: 10,
        result: MatchResult.teamA, // Seed1 wins
        status: MatchStatus.completed,
        notifyTopic: ko1.notifyTopic,
      );

      final updates = resolveDependentSlots(
        completed: completedKo1,
        otherKnockoutMatches: matches.where((m) => m.matchCode != 'KO1').toList(),
      );

      final ko3Update = updates.firstWhere((m) => m.matchCode == 'KO3');
      final finalUpdate = updates.firstWhere((m) => m.matchCode == 'KOF');

      expect(ko3Update.teamA.name, 'Seed2'); // loser of KO1 -> KO3 teamA slot
      expect(finalUpdate.teamA.name, 'Seed1'); // winner of KO1 -> Final teamA slot
    });
  });

  group('computePodium', () {
    Match ko(String code, String teamAId, String teamBId, MatchResult? result) => Match(
          id: code,
          sport: 'badminton',
          category: 'boys',
          season: '2026',
          stage: MatchStage.knockout,
          matchNumber: 1,
          label: code,
          matchCode: code,
          teamA: TeamRef(teamId: teamAId, name: teamAId),
          teamB: TeamRef(teamId: teamBId, name: teamBId),
          result: result,
          status: result == null ? MatchStatus.upcoming : MatchStatus.completed,
          notifyTopic: 'badminton_boys',
        );

    test('null until the Final has a result', () {
      final matches = [
        ko('KO1', 'Seed1', 'Seed2', MatchResult.teamA),
        ko('KO2', 'Seed3', 'Seed4', MatchResult.teamA),
        ko('KO3', 'Seed2', 'Seed3', MatchResult.teamB),
        ko('KOF', 'Seed1', 'Seed3', null),
      ];
      expect(computePodium(matches), isNull);
    });

    test('champion, runner-up and semifinalists derived correctly', () {
      // Seed1 beats Seed2 (KO1); Seed3 beats Seed4 (KO2); Seed3 beats Seed2
      // (KO3, so Seed2 finishes 3rd, Seed4 finishes 4th); Seed1 beats Seed3
      // in the Final (Seed1 champion, Seed3 runner-up).
      final matches = [
        ko('KO1', 'Seed1', 'Seed2', MatchResult.teamA),
        ko('KO2', 'Seed3', 'Seed4', MatchResult.teamA),
        ko('KO3', 'Seed2', 'Seed3', MatchResult.teamB),
        ko('KOF', 'Seed1', 'Seed3', MatchResult.teamA),
      ];
      final podium = computePodium(matches);
      expect(podium, isNotNull);
      expect(podium!.champion.teamId, 'Seed1');
      expect(podium.runnerUp.teamId, 'Seed3');
      expect(podium.semifinalists.map((t) => t.teamId).toSet(), {'Seed2', 'Seed4'});
    });
  });

  group('groupMatchesForDisplay', () {
    Match m(MatchStage stage, int number, {int? round}) => Match(
          id: '${stage.name}-$number-${round ?? 0}',
          sport: 'badminton',
          category: 'boys',
          season: '2026',
          stage: stage,
          matchNumber: number,
          label: 'M$number',
          matchCode: '${stage.name}$number',
          teamA: const TeamRef(teamId: 'a', name: 'A'),
          teamB: const TeamRef(teamId: 'b', name: 'B'),
          notifyTopic: 'badminton_boys',
          tiebreakerRound: round,
        );

    test('orders sections knockout first, then tie-breaker rounds latest-first, then league last', () {
      final matches = [
        m(MatchStage.league, 1),
        m(MatchStage.league, 2),
        m(MatchStage.tiebreaker, 1, round: 1),
        m(MatchStage.tiebreaker, 1, round: 2),
        m(MatchStage.knockout, 1),
      ];
      final sections = groupMatchesForDisplay(matches);
      expect(sections.map((s) => s.title).toList(), [
        'Knockout (Round 2)',
        'Tie-Breaker — Round 2',
        'Tie-Breaker',
        'League (Round 1)',
      ]);
      expect(sections[0].matches.single.stage, MatchStage.knockout);
      expect(sections.last.matches.length, 2);
    });

    test('a section with all completed matches reports isCompleted', () {
      final done = Match(
        id: 'x',
        sport: 'badminton',
        category: 'boys',
        season: '2026',
        stage: MatchStage.league,
        matchNumber: 1,
        label: 'M1',
        matchCode: 'L1',
        teamA: const TeamRef(teamId: 'a', name: 'A'),
        teamB: const TeamRef(teamId: 'b', name: 'B'),
        status: MatchStatus.completed,
        notifyTopic: 'badminton_boys',
      );
      final sections = groupMatchesForDisplay([done]);
      expect(sections.single.isCompleted, isTrue);
    });
  });

  group('buildMatchesCsv', () {
    test('has a header row plus one row per match, with the winner named', () {
      final matches = [
        Match(
          id: 'm1',
          sport: 'badminton',
          category: 'boys',
          season: '2026',
          stage: MatchStage.league,
          matchNumber: 1,
          label: 'Match 1',
          matchCode: 'L1',
          teamA: const TeamRef(teamId: 'a', name: 'Team A'),
          teamB: const TeamRef(teamId: 'b', name: 'Team B'),
          scoreA: 21,
          scoreB: 15,
          result: MatchResult.teamA,
          status: MatchStatus.completed,
          notifyTopic: 'badminton_boys',
        ),
      ];
      final csv = buildMatchesCsv(matches);
      final lines = csv.trim().split('\n');
      expect(lines.length, 2); // header + 1 match row
      expect(lines.first, contains('Team A'));
      expect(lines.first, contains('Winner'));
      expect(lines[1], contains('Team A')); // winner column names Team A
    });
  });
}
