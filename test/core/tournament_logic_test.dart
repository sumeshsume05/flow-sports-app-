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

Team _team(String id, String name, {String? section}) => Team(
      id: id,
      sport: 'badminton',
      category: 'boys',
      name: name,
      season: '2026',
      section: section,
    );

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

  group('generateSectionedLeagueMatches', () {
    test('teams only play others in their own section', () {
      final teams = [
        _team('a1', 'A1', section: 'A'),
        _team('a2', 'A2', section: 'A'),
        _team('a3', 'A3', section: 'A'),
        _team('a4', 'A4', section: 'A'),
        _team('b1', 'B1', section: 'B'),
        _team('b2', 'B2', section: 'B'),
        _team('b3', 'B3', section: 'B'),
        _team('b4', 'B4', section: 'B'),
      ];
      final matches = generateSectionedLeagueMatches(
        teams: teams,
        sport: 'badminton',
        category: 'boys',
        season: '2026',
      );
      // 4 teams -> 6 pairs per section, 2 sections -> 12 total.
      expect(matches.length, 12);
      expect(matches.every((m) => m.section != null), isTrue);
      for (final m in matches) {
        final aInA = teams.firstWhere((t) => t.id == m.teamA.teamId).section;
        final bInB = teams.firstWhere((t) => t.id == m.teamB.teamId).section;
        expect(aInA, bInB); // never a cross-section pairing
        expect(m.section, aInA);
      }
    });

    test('unequal section sizes (girls: 3 + 3) still only pair within a section', () {
      final teams = [
        _team('a1', 'A1', section: 'A'),
        _team('a2', 'A2', section: 'A'),
        _team('a3', 'A3', section: 'A'),
        _team('b1', 'B1', section: 'B'),
        _team('b2', 'B2', section: 'B'),
        _team('b3', 'B3', section: 'B'),
      ];
      final matches = generateSectionedLeagueMatches(
        teams: teams,
        sport: 'badminton',
        category: 'girls',
        season: '2026',
      );
      expect(matches.length, 6); // 3 pairs per section * 2 sections
      expect(matches.where((m) => m.section == 'A').length, 3);
      expect(matches.where((m) => m.section == 'B').length, 3);
    });
  });

  group('candidatesForTopFour / decidingTieCluster with cutoffCount', () {
    StandingRow row(String id, int points, int scored) {
      final r = StandingRow(teamId: id, teamName: id);
      r.points = points;
      r.pointsScored = scored;
      return r;
    }

    test('cutoffCount: 2 widens past 2 only for a genuine tie at the cutoff', () {
      final rows = [row('a', 6, 50), row('b', 4, 40), row('c', 4, 40), row('d', 2, 20)];
      final candidates = candidatesForTopFour(rows, cutoffCount: 2);
      expect(candidates.map((r) => r.teamId), ['a', 'b', 'c']); // c ties b at the 2nd-place cutoff

      final cluster = decidingTieCluster(candidates, cutoffCount: 2);
      expect(cluster?.map((r) => r.teamId), ['b', 'c']);
    });

    test('cutoffCount: 2 with no tie at the cutoff returns exactly the top 2', () {
      final rows = [row('a', 6, 50), row('b', 4, 40), row('c', 2, 20)];
      final candidates = candidatesForTopFour(rows, cutoffCount: 2);
      expect(candidates.map((r) => r.teamId), ['a', 'b']);
      expect(decidingTieCluster(candidates, cutoffCount: 2), isNull);
    });

    test('default cutoffCount (4) is unchanged from before this parameter existed', () {
      final rows = List.generate(5, (i) => row('t$i', 6 - i, 50 - i * 5));
      expect(candidatesForTopFour(rows).length, 4);
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

  group('candidatesForTopFour', () {
    StandingRow row(String id, int points, int scored) {
      final r = StandingRow(teamId: id, teamName: id);
      r.points = points;
      r.pointsScored = scored;
      return r;
    }

    test(
        'reported bug: 3rd place sharing points with 4th but ahead on points-scored '
        'is kept, not dropped', () {
      // Exact shape of the reported scenario: 3rd and 4th both on 5 pts, but
      // 3rd scored 85 vs 4th's 69 — 3rd clearly outranks 4th already, isn't
      // tied with anyone, and must not be excluded just for sharing points
      // with the cutoff row.
      final standings = [
        row('Christina', 8, 77),
        row('Jisha', 7, 73),
        row('Devi', 5, 85),
        row('Renosha', 5, 69),
        row('Elain', 3, 74),
        row('Rebisha', 2, 75),
      ];
      final candidates = candidatesForTopFour(standings);
      expect(candidates.map((r) => r.teamId).toList(), ['Christina', 'Jisha', 'Devi', 'Renosha']);
    });

    test('no widening needed: returns exactly the top 4 when unambiguous', () {
      final standings = [
        row('A', 8, 90),
        row('B', 6, 83),
        row('C', 4, 72),
        row('D', 2, 60),
        row('E', 1, 50),
      ];
      expect(candidatesForTopFour(standings).map((r) => r.teamId).toList(), ['A', 'B', 'C', 'D']);
    });

    test('widens past 4 only for a genuine tie (same points AND scored) with the cutoff', () {
      final standings = [
        row('A', 8, 90),
        row('B', 6, 83),
        row('C', 4, 72),
        row('D', 4, 72), // cutoff
        row('E', 4, 72), // genuinely tied with cutoff — pulled in
        row('F', 3, 60), // not tied — stays out
      ];
      final candidates = candidatesForTopFour(standings);
      expect(candidates.map((r) => r.teamId).toSet(), {'A', 'B', 'C', 'D', 'E'});
    });

    test('4 or fewer teams total returns them all as-is', () {
      final standings = [row('A', 8, 90), row('B', 6, 83), row('C', 4, 72)];
      expect(candidatesForTopFour(standings), standings);
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

    test('scales to a full 6-team tie (every pair exactly once, C(6,2)=15 matches)', () {
      final teams = List.generate(6, (i) => StandingRow(teamId: 't$i', teamName: 'Team $i'));
      final matches = generateTiebreakerMatches(
        tiedTeams: teams,
        sport: 'badminton',
        category: 'girls',
        season: '2026',
        round: 1,
      );
      expect(matches.length, 15);
      final pairs = matches.map((m) => {m.teamA.teamId, m.teamB.teamId}).toSet();
      expect(pairs.length, 15); // no duplicate or missing pairing
    });

    test('section tags the match and prefixes its matchCode/label', () {
      final matches = generateTiebreakerMatches(
        tiedTeams: [StandingRow(teamId: 'a', teamName: 'A'), StandingRow(teamId: 'b', teamName: 'B')],
        sport: 'badminton',
        category: 'boys',
        season: '2026',
        round: 1,
        section: 'A',
      );
      expect(matches.single.section, 'A');
      expect(matches.single.matchCode, 'A-TB1_1');
      expect(matches.single.label, contains('Section A'));
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

  group('GenerateBracketScreen candidate resolution (full pipeline)', () {
    // Mirrors exactly what generate_bracket_screen.dart's _load() does:
    // candidatesForTopFour -> decidingTieCluster -> (if a cluster exists)
    // resolveTieChain -> splice the chain's resolved order back into the
    // candidate list. This group exercises that *composition* end to end,
    // not just each function alone — the reported bug (3rd place dropped
    // entirely) only showed up in how pieces combined, not in either piece
    // in isolation, so per-function tests alone weren't enough to catch it.
    ({List<StandingRow> candidates, TieChainResult? chain}) resolve(
      List<StandingRow> standings,
      List<Match> tiebreakerMatches,
    ) {
      final raw = candidatesForTopFour(standings);
      final cluster = decidingTieCluster(raw);
      if (cluster == null) return (candidates: raw, chain: null);
      final chain = resolveTieChain(originalCluster: cluster, allTiebreakerMatches: tiebreakerMatches);
      final candidates = List<StandingRow>.of(raw);
      final startIndex = candidates.indexWhere((r) => r.teamId == cluster.first.teamId);
      for (var k = 0; k < chain.order.length; k++) {
        candidates[startIndex + k] = chain.order[k];
      }
      return (candidates: candidates, chain: chain);
    }

    StandingRow row(String id, int points, int scored) {
      final r = StandingRow(teamId: id, teamName: id);
      r.points = points;
      r.pointsScored = scored;
      return r;
    }

    Match tb(String category, int round, String a, String b, int scoreA, int scoreB, int n) => Match(
          id: 'tb-$category-$round-$n',
          sport: 'badminton',
          category: category,
          season: '2026',
          stage: MatchStage.tiebreaker,
          matchNumber: n,
          label: 'Tie-Breaker',
          matchCode: 'TB${round}_$n',
          teamA: TeamRef(teamId: a, name: a),
          teamB: TeamRef(teamId: b, name: b),
          scoreA: scoreA,
          scoreB: scoreB,
          result: Match.computeResult(scoreA, scoreB),
          status: MatchStatus.completed,
          notifyTopic: 'badminton_$category',
          tiebreakerRound: round,
        );

    test('all 6 teams fully tied (same pts, same score): all 6 are contested until played', () {
      final standings = [
        row('A', 4, 70),
        row('B', 4, 70),
        row('C', 4, 70),
        row('D', 4, 70),
        row('E', 4, 70),
        row('F', 4, 70),
      ];
      final result = resolve(standings, []);
      expect(result.chain, isNotNull);
      expect(result.chain!.contestedGroup?.map((r) => r.teamId).toSet(),
          {'A', 'B', 'C', 'D', 'E', 'F'});
    });

    test('all 6 teams fully tied: a clean round-robin tie-breaker picks the correct top 4', () {
      final standings = [
        row('A', 4, 70),
        row('B', 4, 70),
        row('C', 4, 70),
        row('D', 4, 70),
        row('E', 4, 70),
        row('F', 4, 70),
      ];
      // Strict dominance order A>B>C>D>E>F, so the round-robin resolves
      // fully in one round with no sub-ties left over.
      const order = ['A', 'B', 'C', 'D', 'E', 'F'];
      final matches = <Match>[];
      var n = 1;
      for (var i = 0; i < order.length; i++) {
        for (var j = i + 1; j < order.length; j++) {
          matches.add(tb('boys', 1, order[i], order[j], 21, 10, n++));
        }
      }
      final result = resolve(standings, matches);
      expect(result.chain!.contestedGroup, isNull);
      expect(result.candidates.take(4).map((r) => r.teamId).toList(), ['A', 'B', 'C', 'D']);
      expect(result.candidates.skip(4).map((r) => r.teamId).toSet(), {'E', 'F'});
    });

    test('top 3 safely tied + bottom 3 tied for the last spot: only the bottom 3 are contested', () {
      final standings = [
        row('A', 6, 83),
        row('B', 6, 83),
        row('C', 6, 83),
        row('D', 4, 72),
        row('E', 4, 72),
        row('F', 4, 72),
      ];
      final matches = [
        tb('girls', 1, 'D', 'E', 21, 15, 1),
        tb('girls', 1, 'D', 'F', 21, 15, 2),
        tb('girls', 1, 'E', 'F', 21, 15, 3),
      ]; // D wins both its matches outright
      final result = resolve(standings, matches);
      expect(result.chain!.contestedGroup, isNull);
      // Top 3 keep their given order — they were never part of the
      // contested cluster — and D wins the tie-breaker outright for 4th.
      expect(result.candidates.take(4).map((r) => r.teamId).toList(), ['A', 'B', 'C', 'D']);
      expect(result.candidates.skip(4).map((r) => r.teamId).toSet(), {'E', 'F'});
    });

    test('mixed: a 2nd/3rd tie needs no tie-breaker, only the 4th/5th tie for the cutoff does', () {
      final standings = [
        row('A', 10, 100), // clear 1st
        row('B', 6, 80), row('C', 6, 80), // tied for 2nd/3rd — both safely qualify regardless
        row('D', 4, 60), row('E', 4, 60), // tied for the one remaining spot
        row('F', 1, 40), // clearly out
      ];
      final raw = candidatesForTopFour(standings);
      // The B/C tie never reaches decidingTieCluster — it doesn't share the
      // cutoff's point value, so it can't affect who qualifies, only seed order.
      final cluster = decidingTieCluster(raw);
      expect(cluster!.map((r) => r.teamId).toSet(), {'D', 'E'});

      final matches = [tb('boys', 1, 'D', 'E', 21, 18, 1)]; // D wins
      final result = resolve(standings, matches);
      expect(result.chain!.contestedGroup, isNull);
      expect(result.candidates.take(4).map((r) => r.teamId).toList(), ['A', 'B', 'C', 'D']);
      // F was never a contender (it doesn't share the cutoff's points/scored),
      // so candidatesForTopFour correctly leaves it out of the list entirely
      // — only E, which genuinely contested and lost, shows up as "OUT".
      expect(result.candidates.length, 5);
      expect(result.candidates.skip(4).map((r) => r.teamId).toSet(), {'E'});
    });

    test('exactly 4 teams, all mutually tied: nobody below to threaten them, so no tie-breaker needed', () {
      final standings = [row('A', 4, 60), row('B', 4, 60), row('C', 4, 60), row('D', 4, 60)];
      final result = resolve(standings, []);
      // No 5th team exists to contest a spot — must never be flagged as a
      // qualification ambiguity, only a (harmless, optional) seeding one.
      expect(result.chain, isNull);
      expect(result.candidates.map((r) => r.teamId).toList(), ['A', 'B', 'C', 'D']);
    });

    test('exactly 5 teams, only 4th and 5th tied', () {
      final standings = [
        row('A', 10, 90),
        row('B', 8, 85),
        row('C', 6, 80),
        row('D', 4, 70),
        row('E', 4, 70),
      ];
      final matches = [tb('girls', 1, 'D', 'E', 15, 21, 1)]; // E wins
      final result = resolve(standings, matches);
      expect(result.chain!.contestedGroup, isNull);
      expect(result.candidates.take(4).map((r) => r.teamId).toList(), ['A', 'B', 'C', 'E']);
      expect(result.candidates.skip(4).map((r) => r.teamId).toSet(), {'D'});
    });

    test('boys and girls run through identical logic — category never changes the outcome', () {
      final standings = [
        row('A', 6, 83),
        row('B', 6, 83),
        row('C', 6, 83),
        row('D', 4, 72),
        row('E', 4, 72),
        row('F', 4, 72),
      ];
      List<String> seedsFor(String category) {
        final matches = [
          tb(category, 1, 'D', 'E', 21, 15, 1),
          tb(category, 1, 'D', 'F', 21, 15, 2),
          tb(category, 1, 'E', 'F', 21, 15, 3),
        ];
        return resolve(standings, matches).candidates.take(4).map((r) => r.teamId).toList();
      }

      expect(seedsFor('boys'), seedsFor('girls'));
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

    test(
        'reported bug: a tied knockout result throws instead of silently advancing team B', () {
      final matches = generateKnockoutMatches(
        top4Seeds: seeds(),
        sport: 'badminton',
        category: 'boys',
        season: '2026',
      ).map((m) => Match(
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
          )).toList();

      final ko2 = matches.firstWhere((m) => m.matchCode == 'KO2');
      // Exact shape of the reported scenario: an equal score, which
      // Match.computeResult treats as MatchResult.tie.
      final tiedKo2 = Match(
        id: ko2.id,
        sport: ko2.sport,
        category: ko2.category,
        season: ko2.season,
        stage: ko2.stage,
        matchNumber: ko2.matchNumber,
        label: ko2.label,
        matchCode: ko2.matchCode,
        teamA: ko2.teamA,
        teamB: ko2.teamB,
        scoreA: 21,
        scoreB: 21,
        result: Match.computeResult(21, 21),
        status: MatchStatus.completed,
        notifyTopic: ko2.notifyTopic,
      );

      expect(
        () => resolveDependentSlots(
          completed: tiedKo2,
          otherKnockoutMatches: matches.where((m) => m.matchCode != 'KO2').toList(),
        ),
        throwsStateError,
      );
    });
  });

  group('generateKnockoutMatchesForTwo', () {
    test('a single Final, both teams known directly (no TBD)', () {
      final seeds = [
        StandingRow(teamId: 's1', teamName: 'Seed1'),
        StandingRow(teamId: 's2', teamName: 'Seed2'),
      ];
      final matches = generateKnockoutMatchesForTwo(
        twoSeeds: seeds,
        sport: 'badminton',
        category: 'girls',
        season: '2026',
      );
      expect(matches.length, 1);
      expect(matches.single.matchCode, 'KOF');
      expect(matches.single.teamA.name, 'Seed1');
      expect(matches.single.teamB.name, 'Seed2');
      expect(matches.single.teamA.isTbd, isFalse);
      expect(matches.single.teamB.isTbd, isFalse);
    });
  });

  group('generateKnockoutMatchesForThree', () {
    List<StandingRow> seeds() => [
          StandingRow(teamId: 's1', teamName: 'Seed1'),
          StandingRow(teamId: 's2', teamName: 'Seed2'),
          StandingRow(teamId: 's3', teamName: 'Seed3'),
        ];

    test('Seed 1 has a bye in the Final; Seed 2 vs Seed 3 play the Semifinal', () {
      final matches = generateKnockoutMatchesForThree(
        threeSeeds: seeds(),
        sport: 'badminton',
        category: 'girls',
        season: '2026',
      );
      final byCode = {for (final m in matches) m.matchCode: m};

      expect(byCode['KO1']!.teamA.name, 'Seed2');
      expect(byCode['KO1']!.teamB.name, 'Seed3');
      expect(byCode['KOF']!.teamA.name, 'Seed1'); // the bye, known directly
      expect(byCode['KOF']!.teamA.isTbd, isFalse);
      expect(byCode['KOF']!.teamB.isTbd, isTrue); // winner of KO1
    });

    test('resolveDependentSlots fills the Final once the Semifinal completes', () {
      final matches = generateKnockoutMatchesForThree(
        threeSeeds: seeds(),
        sport: 'badminton',
        category: 'girls',
        season: '2026',
      ).map((m) => Match(
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
        scoreA: 15,
        scoreB: 21,
        result: MatchResult.teamB, // Seed3 wins the Semifinal
        status: MatchStatus.completed,
        notifyTopic: ko1.notifyTopic,
      );

      final updates = resolveDependentSlots(
        completed: completedKo1,
        otherKnockoutMatches: matches.where((m) => m.matchCode != 'KO1').toList(),
      );

      final finalUpdate = updates.firstWhere((m) => m.matchCode == 'KOF');
      expect(finalUpdate.teamB.name, 'Seed3');
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

    test(
        'reported-bug-adjacent: a tied KO2/KO3 result is treated as undecided, '
        'not silently resolved to team B', () {
      // KO2 tied (a badminton game can't legitimately finish level — same
      // invalid-data shape as the knockout tie-guard bug) — must not be
      // treated as "Seed4 won" just because it isn't MatchResult.teamA.
      final matches = [
        ko('KO1', 'Seed1', 'Seed2', MatchResult.teamA),
        ko('KO2', 'Seed3', 'Seed4', MatchResult.tie),
        ko('KO3', 'Seed2', 'Seed4', MatchResult.teamB),
        ko('KOF', 'Seed1', 'Seed4', MatchResult.teamA),
      ];
      expect(computePodium(matches), isNull);
    });

    test('2-team shape: champion/runner-up from the Final alone, no semifinalists', () {
      final matches = [ko('KOF', 'Seed1', 'Seed2', MatchResult.teamA)];
      final podium = computePodium(matches);
      expect(podium, isNotNull);
      expect(podium!.champion.teamId, 'Seed1');
      expect(podium.runnerUp.teamId, 'Seed2');
      expect(podium.semifinalists, isEmpty);
    });

    test('3-team shape: the Semifinal loser is the lone "3rd place", not a pair', () {
      final matches = [
        ko('KO1', 'Seed2', 'Seed3', MatchResult.teamB), // Seed3 wins the Semifinal
        ko('KOF', 'Seed1', 'Seed3', MatchResult.teamA), // Seed1 (bye) wins the Final
      ];
      final podium = computePodium(matches);
      expect(podium, isNotNull);
      expect(podium!.champion.teamId, 'Seed1');
      expect(podium.runnerUp.teamId, 'Seed3');
      expect(podium.semifinalists.map((t) => t.teamId).toList(), ['Seed2']);
    });

    test('3-team shape: null until the Semifinal is decided too, not just the Final', () {
      final matches = [
        ko('KO1', 'Seed2', 'Seed3', null),
        ko('KOF', 'Seed1', 'Seed3', MatchResult.teamA),
      ];
      expect(computePodium(matches), isNull);
    });
  });

  group('groupMatchesForDisplay', () {
    Match m(MatchStage stage, int number, {int? round, String? section}) => Match(
          id: '${stage.name}-$number-${round ?? 0}-${section ?? ""}',
          sport: 'badminton',
          category: 'boys',
          season: '2026',
          stage: stage,
          matchNumber: number,
          label: 'M$number',
          matchCode: '${stage.name}$number',
          section: section,
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

    test('a sectioned league splits into one group per section instead of one flat group', () {
      final matches = [
        m(MatchStage.league, 1, section: 'A'),
        m(MatchStage.league, 2, section: 'A'),
        m(MatchStage.league, 3, section: 'B'),
      ];
      final sections = groupMatchesForDisplay(matches);
      expect(sections.map((s) => s.title).toList(), ['League — Section A', 'League — Section B']);
      expect(sections[0].matches.length, 2);
      expect(sections[1].matches.length, 1);
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
