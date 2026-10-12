import 'package:flow_sports_app/core/utils/bracket_resolver.dart';
import 'package:flow_sports_app/core/utils/standings_calculator.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/models/standing_row.dart';
import 'package:flutter_test/flutter_test.dart';

StandingRow row(String id, {int points = 0, int scored = 0}) {
  final r = StandingRow(teamId: id, teamName: 'Team $id');
  r.points = points;
  r.pointsScored = scored;
  return r;
}

/// A finished tie-breaker match between two teams of a round.
Match tb(String a, String b, int sa, int sb, {int round = 1, MatchStatus status = MatchStatus.completed}) =>
    Match(
      id: 'tb-$a-$b-$round',
      sport: 'badminton',
      category: 'boys',
      season: '2026',
      stage: MatchStage.tiebreaker,
      matchNumber: 1,
      label: 'TB',
      matchCode: 'TB${round}_$a$b',
      teamA: TeamRef(teamId: a, name: 'Team $a'),
      teamB: TeamRef(teamId: b, name: 'Team $b'),
      scoreA: status == MatchStatus.completed ? sa : null,
      scoreB: status == MatchStatus.completed ? sb : null,
      result: status == MatchStatus.completed ? Match.computeResult(sa, sb) : null,
      status: status,
      notifyTopic: 'x',
      tiebreakerRound: round,
    );

Match league(String id, {MatchResult? result, MatchStatus? status}) => Match(
      id: id,
      sport: 'badminton',
      category: 'boys',
      season: '2026',
      stage: MatchStage.league,
      matchNumber: 1,
      label: 'L',
      matchCode: 'L1',
      teamA: const TeamRef(teamId: 'a', name: 'A'),
      teamB: const TeamRef(teamId: 'b', name: 'B'),
      scoreA: result == null ? null : 21,
      scoreB: result == null ? null : 10,
      result: result,
      status: status ?? (result == null ? MatchStatus.upcoming : MatchStatus.completed),
      notifyTopic: 'x',
    );

void main() {
  // ---------------------------------------------------------------- fix 1
  group('league progress (Generate Bracket needs a finished league)', () {
    test('counts finished vs remaining; a reset match is not finished', () {
      final p = leagueProgress([
        league('1', result: MatchResult.teamA),
        league('2', result: MatchResult.tie),
        league('3'),
        league('4', result: MatchResult.teamA, status: MatchStatus.upcoming), // reset: stale result
        league('5', result: MatchResult.teamA, status: MatchStatus.live),
      ]);
      expect(p.total, 5);
      expect(p.completed, 2);
      expect(p.remaining, 3);
      expect(p.isFinished, isFalse);
    });

    test('finished only when every match is done', () {
      expect(leagueProgress([league('1', result: MatchResult.teamA)]).isFinished, isTrue);
      expect(leagueProgress([league('1', result: MatchResult.teamA), league('2')]).isFinished, isFalse);
    });

    test('no league matches at all is NOT finished (nothing to rank from)', () {
      final p = leagueProgress(const []);
      expect(p.total, 0);
      expect(p.isFinished, isFalse);
    });
  });

  // ---------------------------------------------------------------- fix 2
  group('tie-breaker chain only continues when it can change who qualifies', () {
    // Five teams level on the league: cutoff 3 means places 0-2 qualify.
    List<StandingRow> cluster5() => [for (final id in ['p', 'q', 'r', 's', 't']) row(id, points: 6, scored: 100)];

    // Round 1 round-robin: P beats everyone; Q and R beat S and T, lose to P, tie
    // each other; S and T lose to everyone else and tie each other.
    final round1 = [
      tb('p', 'q', 21, 10), tb('p', 'r', 21, 10), tb('p', 's', 21, 10), tb('p', 't', 21, 10),
      tb('q', 'r', 15, 15), tb('q', 's', 21, 10), tb('q', 't', 21, 10),
      tb('r', 's', 21, 10), tb('r', 't', 21, 10),
      tb('s', 't', 15, 15),
    ];

    test('legacy walk (no cutoff) is unchanged: it recurses into every level team, even ones that cannot matter', () {
      final legacy = resolveTieChain(originalCluster: cluster5(), allTiebreakerMatches: round1);
      expect(legacy.contestedGroup?.map((r) => r.teamId).toSet(), {'q', 'r', 's', 't'});
    });

    test('with a cutoff, level pairs that are both safely in / both out force no extra round', () {
      // Q=R level at places 1-2 (both qualify with cutoff 3), S=T level at 3-4 (both out).
      final r = resolveTieChain(
        originalCluster: cluster5(),
        allTiebreakerMatches: round1,
        cutoffCount: 3,
        clusterStartIndex: 0,
      );
      expect(r.contestedGroup, isNull);
      expect(r.order.first.teamId, 'p');
      // The still-level pairs are reported as runs, for the seed-order check.
      expect(r.levelRuns.map((run) => run.map((x) => x.teamId).toList()),
          [['p'], ['q', 'r'], ['s', 't']]);
    });

    test('a still-level group that straddles the cutoff IS contested again', () {
      // Cutoff 2: places 0-1 qualify, so Q/R level at 1-2 straddle the line.
      final r = resolveTieChain(
        originalCluster: cluster5(),
        allTiebreakerMatches: round1,
        cutoffCount: 2,
        clusterStartIndex: 0,
      );
      expect(r.contestedGroup?.map((x) => x.teamId).toSet(), {'q', 'r'});
      expect(r.nextRound, 2);
      expect(r.contestedGroupMatches, isEmpty); // not scheduled yet
    });

    test('separate level pairs are never merged into one group', () {
      // Cutoff 4 over 5 teams: S/T (places 3-4) straddle the line; Q/R (1-2) do not.
      final r = resolveTieChain(
        originalCluster: cluster5(),
        allTiebreakerMatches: round1,
        cutoffCount: 4,
        clusterStartIndex: 0,
      );
      expect(r.contestedGroup?.map((x) => x.teamId).toSet(), {'s', 't'},
          reason: 'only the pair at the cut-off needs another round, not Q and R as well');
      // Order of the resolved top places is intact (the legacy walk could overwrite it).
      expect(r.order.first.teamId, 'p');
    });

    test('a cluster that starts below the top uses absolute positions', () {
      // Cluster occupies places 2-4 of the qualifier list; cutoff 4 -> positions 2,3 qualify... (index<4).
      final c = [row('x', points: 4, scored: 50), row('y', points: 4, scored: 50), row('z', points: 4, scored: 50)];
      final matches = [tb('x', 'y', 21, 10), tb('x', 'z', 21, 10), tb('y', 'z', 15, 15)];
      final r = resolveTieChain(
        originalCluster: c,
        allTiebreakerMatches: matches,
        cutoffCount: 4,
        clusterStartIndex: 2, // x at place 2, y/z at places 3-4 straddle the line at 4
      );
      expect(r.contestedGroup?.map((e) => e.teamId).toSet(), {'y', 'z'});
    });

    test('an unplayed or in-progress round still blocks (contested, with its matches)', () {
      final inProgress = [
        tb('p', 'q', 0, 0, status: MatchStatus.upcoming),
        tb('p', 'r', 21, 10),
      ];
      final r = resolveTieChain(
        originalCluster: [row('p'), row('q'), row('r')],
        allTiebreakerMatches: inProgress,
        cutoffCount: 2,
        clusterStartIndex: 0,
      );
      expect(r.contestedGroup, isNotNull);
      expect(r.contestedGroupMatches, isNotEmpty);
    });

    test('everyone separated by the round: nothing left to contest', () {
      final c = [row('a', points: 2, scored: 20), row('b', points: 2, scored: 20), row('c', points: 2, scored: 20)];
      final matches = [tb('a', 'b', 21, 10), tb('a', 'c', 21, 10), tb('b', 'c', 21, 10)];
      final r = resolveTieChain(originalCluster: c, allTiebreakerMatches: matches, cutoffCount: 2, clusterStartIndex: 0);
      expect(r.contestedGroup, isNull);
      expect(r.order.map((x) => x.teamId), ['a', 'b', 'c']);
      expect(r.levelRuns.every((run) => run.length == 1), isTrue);
    });
  });

  // ---------------------------------------------------------------- fix 3
  group('level teams whose order decides who plays whom', () {
    List<List<StandingRow>> runsOf(List<StandingRow> rows) => levelRuns(rows);

    test('path boundaries per bracket shape', () {
      expect(pathBoundaries(qualifyCount: 4, sectioned: false), {2});
      expect(pathBoundaries(qualifyCount: 3, sectioned: false), {1});
      expect(pathBoundaries(qualifyCount: 2, sectioned: false), isEmpty);
      expect(pathBoundaries(qualifyCount: 2, sectioned: true), {1});
    });

    test('levelRuns groups consecutive dead-level teams by points AND score', () {
      final rows = [
        row('a', points: 6, scored: 90),
        row('b', points: 4, scored: 70),
        row('c', points: 4, scored: 70),
        row('d', points: 4, scored: 65), // same points, different score: NOT level with b/c
        row('e', points: 2, scored: 40),
      ];
      expect(runsOf(rows).map((r) => r.map((x) => x.teamId).toList()),
          [['a'], ['b', 'c'], ['d'], ['e']]);
    });

    List<String> tieIds(List<List<StandingRow>> t) => [for (final run in t) run.map((x) => x.teamId).join()];

    test('flat top 4: a tie between 2nd and 3rd matters; 1st/2nd and 3rd/4th do not', () {
      List<List<StandingRow>> ties(List<StandingRow> rows) =>
          seedDecidingTies(runsOf(rows), qualifyCount: 4, sectioned: false);
      expect(tieIds(ties([row('a', points: 8, scored: 90), row('b', points: 6, scored: 70), row('c', points: 6, scored: 70), row('d', points: 2, scored: 30)])), ['bc']);
      // 1st and 2nd level: they play each other in the same match, so no path change.
      expect(ties([row('a', points: 6, scored: 70), row('b', points: 6, scored: 70), row('c', points: 4, scored: 50), row('d', points: 2, scored: 30)]), isEmpty);
      // 3rd and 4th level: same match again.
      expect(ties([row('a', points: 8, scored: 90), row('b', points: 6, scored: 70), row('c', points: 4, scored: 50), row('d', points: 4, scored: 50)]), isEmpty);
      // Three-way tie for 2nd-4th crosses the boundary.
      expect(tieIds(ties([row('a', points: 8, scored: 90), row('b', points: 4, scored: 50), row('c', points: 4, scored: 50), row('d', points: 4, scored: 50)])), ['bcd']);
    });

    test('flat top 3: 1st (bye) vs 2nd matters; 2nd vs 3rd does not', () {
      List<List<StandingRow>> ties(List<StandingRow> rows) =>
          seedDecidingTies(runsOf(rows), qualifyCount: 3, sectioned: false);
      expect(tieIds(ties([row('a', points: 6, scored: 70), row('b', points: 6, scored: 70), row('c', points: 2, scored: 30)])), ['ab']);
      expect(ties([row('a', points: 8, scored: 90), row('b', points: 4, scored: 50), row('c', points: 4, scored: 50)]), isEmpty);
    });

    test('top 2 only: they meet in the Final, so no seed tie ever matters', () {
      expect(seedDecidingTies(runsOf([row('a', points: 6, scored: 70), row('b', points: 6, scored: 70)]), qualifyCount: 2, sectioned: false),
          isEmpty);
    });

    test('a section\'s 1st/2nd level matters (they meet different opponents)', () {
      final rows = [row('a', points: 4, scored: 50), row('b', points: 4, scored: 50), row('c', points: 0, scored: 10)];
      expect(tieIds(seedDecidingTies(runsOf(rows), qualifyCount: 2, sectioned: true)), ['ab']);
    });

    test('a run that reaches the cut-off is a qualification tie, not a seed tie', () {
      // top 4 with 3rd..5th level: spills past the line, handled by tie-breakers.
      final rows = [
        row('a', points: 8, scored: 90),
        row('b', points: 6, scored: 80),
        row('c', points: 4, scored: 50),
        row('d', points: 4, scored: 50),
        row('e', points: 4, scored: 50),
      ];
      expect(seedDecidingTies(runsOf(rows), qualifyCount: 4, sectioned: false), isEmpty);
    });

    test('a tie-breaker that separated the teams removes the seed tie', () {
      final cluster = [row('x', points: 4, scored: 50), row('y', points: 4, scored: 50), row('z', points: 4, scored: 50)];
      final chain = resolveTieChain(
        originalCluster: cluster,
        allTiebreakerMatches: [tb('x', 'y', 21, 10), tb('x', 'z', 21, 10), tb('y', 'z', 21, 10)],
        cutoffCount: 4,
        clusterStartIndex: 1,
      );
      final candidates = [row('w', points: 8, scored: 90), ...chain.order];
      final runs = levelRuns(candidates, chain: chain, clusterStart: 1);
      expect(runs.map((r) => r.length), [1, 1, 1, 1]);
      expect(seedDecidingTies(runs, qualifyCount: 4, sectioned: false), isEmpty);
    });

    test('a tie-breaker that stays level keeps the seed tie (nothing guessed)', () {
      final cluster = [row('x', points: 4, scored: 50), row('y', points: 4, scored: 50), row('z', points: 4, scored: 50)];
      // x and y tie each other and both beat z -> x/y stay level at places 2-3 (index 1-2).
      final chain = resolveTieChain(
        originalCluster: cluster,
        allTiebreakerMatches: [tb('x', 'y', 15, 15), tb('x', 'z', 21, 10), tb('y', 'z', 21, 10)],
        cutoffCount: 4,
        clusterStartIndex: 1,
      );
      expect(chain.contestedGroup, isNull); // both are safely in: no tie-breaker needed
      final candidates = [row('w', points: 8, scored: 90), ...chain.order];
      final ties = seedDecidingTies(levelRuns(candidates, chain: chain, clusterStart: 1), qualifyCount: 4, sectioned: false);
      expect(tieIds(ties), ['xy']); // 2nd vs 3rd decides the bracket path, so it must be confirmed
    });

    test('level teams that end up as 3rd and 4th stay harmless', () {
      final cluster = [row('x', points: 4, scored: 50), row('y', points: 4, scored: 50), row('z', points: 4, scored: 50)];
      final chain = resolveTieChain(
        originalCluster: cluster,
        allTiebreakerMatches: [tb('x', 'y', 21, 10), tb('x', 'z', 21, 10), tb('y', 'z', 15, 15)],
        cutoffCount: 4,
        clusterStartIndex: 1,
      );
      final candidates = [row('w', points: 8, scored: 90), ...chain.order];
      expect(seedDecidingTies(levelRuns(candidates, chain: chain, clusterStart: 1), qualifyCount: 4, sectioned: false),
          isEmpty);
    });
  });

  // ---------------------------------------------------------------- fix 4
  group('slot-level writes (two admins saving at the same time)', () {
    List<Match> bracket() {
      final raw = generateKnockoutMatches(
        top4Seeds: [for (var i = 1; i <= 4; i++) StandingRow(teamId: 't$i', teamName: 'T$i')],
        sport: 'badminton',
        category: 'boys',
        season: '2026',
      );
      return [
        for (final m in raw)
          Match(
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
          ),
      ];
    }

    Match completed(Match m, MatchResult r) => Match(
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
          scoreA: 21,
          scoreB: 10,
          result: r,
          status: MatchStatus.completed,
          notifyTopic: m.notifyTopic,
        );

    test('a result writes only the slots that name it as a source', () {
      final all = bracket();
      final ko1 = completed(all.firstWhere((m) => m.matchCode == 'KO1'), MatchResult.teamA); // T1 beats T2
      final writes = dependentSlotWrites(completed: ko1, otherKnockoutMatches: all.where((m) => m.id != 'KO1').toList());
      expect(writes.map((w) => '${w.matchId}.${w.slot}=${w.team.name}').toSet(),
          {'KO3.teamA=T2', 'KOF.teamA=T1'}); // loser -> KO3 slot A, winner -> Final slot A
      final ko2 = completed(all.firstWhere((m) => m.matchCode == 'KO2'), MatchResult.teamB); // T4 beats T3
      final w2 = dependentSlotWrites(completed: ko2, otherKnockoutMatches: all.where((m) => m.id != 'KO2').toList());
      expect(w2.map((w) => '${w.matchId}.${w.slot}=${w.team.name}'), ['KO3.teamB=T4']);
    });

    test('agrees with resolveDependentSlots slot by slot', () {
      final all = bracket();
      final ko1 = completed(all.firstWhere((m) => m.matchCode == 'KO1'), MatchResult.teamB);
      final others = all.where((m) => m.id != 'KO1').toList();
      final updates = resolveDependentSlots(completed: ko1, otherKnockoutMatches: others);
      final writes = dependentSlotWrites(completed: ko1, otherKnockoutMatches: others);
      for (final u in updates) {
        for (final slot in ['teamA', 'teamB']) {
          final w = writes.where((x) => x.matchId == u.id && x.slot == slot).firstOrNull;
          if (w != null) {
            final ref = slot == 'teamA' ? u.teamA : u.teamB;
            expect(w.team.teamId, ref.teamId);
          }
        }
      }
    });

    test('best-of-3 Final: both games get the slot from one result', () {
      final raw = generateKnockoutMatches(
        top4Seeds: [for (var i = 1; i <= 4; i++) StandingRow(teamId: 't$i', teamName: 'T$i')],
        sport: 'badminton',
        category: 'boys',
        season: '2026',
        bestOfThreeFinal: true,
      );
      final all = [
        for (final m in raw)
          Match(
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
          ),
      ];
      final ko1 = completed(all.firstWhere((m) => m.matchCode == 'KO1'), MatchResult.teamA);
      final writes = dependentSlotWrites(completed: ko1, otherKnockoutMatches: all.where((m) => m.id != 'KO1').toList());
      expect(writes.where((w) => w.team.name == 'T1').map((w) => w.matchId).toSet(), {'KOF1', 'KOF2'});
    });

    /// Applies slot-write field maps to a pretend Firestore document, the way
    /// a dotted-path update does: only the named fields change.
    Map<String, Map<String, String?>> applyTo(Map<String, Map<String, String?>> docs, List<SlotWrite> writes) {
      final next = {for (final e in docs.entries) e.key: Map<String, String?>.of(e.value)};
      for (final e in slotWriteFields(writes).entries) {
        for (final f in e.value.entries) {
          next[e.key]![f.key] = f.value as String?;
        }
      }
      return next;
    }

    test('two admins saving KO1 and KO2 at nearly the same time: BOTH slots survive, in either order', () {
      final all = bracket();
      final ko1 = completed(all.firstWhere((m) => m.matchCode == 'KO1'), MatchResult.teamA);
      final ko2 = completed(all.firstWhere((m) => m.matchCode == 'KO2'), MatchResult.teamA);
      // Both admins computed their writes from the same, still-empty snapshot.
      final w1 = dependentSlotWrites(completed: ko1, otherKnockoutMatches: all.where((m) => m.id != 'KO1').toList());
      final w2 = dependentSlotWrites(completed: ko2, otherKnockoutMatches: all.where((m) => m.id != 'KO2').toList());
      final Map<String, Map<String, String?>> empty = {
        'KO3': {'teamA.teamId': null, 'teamA.name': null, 'teamB.teamId': null, 'teamB.name': null},
        'KOF': {'teamA.teamId': null, 'teamA.name': null, 'teamB.teamId': null, 'teamB.name': null},
      };
      for (final order in [[w1, w2], [w2, w1]]) {
        var docs = empty;
        for (final w in order) {
          docs = applyTo(docs, w);
        }
        expect(docs['KO3']!['teamA.teamId'], 't2'); // loser of KO1
        expect(docs['KO3']!['teamB.teamId'], 't3'); // winner of KO2 (T3 beats T4)
        expect(docs['KOF']!['teamA.teamId'], 't1');
      }
    });

    test('the old whole-match write DID lose a slot (why this fix is needed)', () {
      final all = bracket();
      final ko1 = completed(all.firstWhere((m) => m.matchCode == 'KO1'), MatchResult.teamA);
      final ko2 = completed(all.firstWhere((m) => m.matchCode == 'KO2'), MatchResult.teamA);
      final u1 = resolveDependentSlots(completed: ko1, otherKnockoutMatches: all.where((m) => m.id != 'KO1').toList());
      final u2 = resolveDependentSlots(completed: ko2, otherKnockoutMatches: all.where((m) => m.id != 'KO2').toList());
      // Each update carries BOTH slots of KO3 as read from the shared snapshot.
      final ko3From1 = u1.firstWhere((m) => m.id == 'KO3');
      final ko3From2 = u2.firstWhere((m) => m.id == 'KO3');
      // Last writer wins wholesale: whichever is written second replaces both slots.
      expect(ko3From1.teamB.isTbd, isTrue); // admin 1's write puts TBD back in slot B
      expect(ko3From2.teamA.isTbd, isTrue); // admin 2's write puts TBD back in slot A
    });

    test('reopening a match clears exactly its own slots and nothing else', () {
      final all = bracket();
      final ko1 = completed(all.firstWhere((m) => m.matchCode == 'KO1'), MatchResult.teamA);
      final clears = unresolveSlotWrites('KO1', dependentsOf('KO1', all.where((m) => m.id != 'KO1').toList()));
      expect(clears.map((w) => '${w.matchId}.${w.slot}').toSet(), {'KO3.teamA', 'KOF.teamA'});
      expect(clears.every((w) => w.team.isTbd), isTrue);
      expect(ko1.matchCode, 'KO1');
    });

    test('field maps use dotted paths and group writes per match', () {
      final fields = slotWriteFields(const [
        SlotWrite('KO3', 'teamA', TeamRef(teamId: 't2', name: 'T2')),
        SlotWrite('KO3', 'teamB', TeamRef(teamId: 't3', name: 'T3')),
        SlotWrite('KOF', 'teamA', TeamRef(teamId: 't1', name: 'T1')),
      ]);
      expect(fields['KO3'], {
        'teamA.teamId': 't2',
        'teamA.name': 'T2',
        'teamB.teamId': 't3',
        'teamB.name': 'T3',
      });
      expect(fields['KOF'], {'teamA.teamId': 't1', 'teamA.name': 'T1'});
    });

    test('a tied result still refuses to advance anyone', () {
      final all = bracket();
      final tied = completed(all.firstWhere((m) => m.matchCode == 'KO1'), MatchResult.tie);
      expect(() => dependentSlotWrites(completed: tied, otherKnockoutMatches: all), throwsStateError);
    });

    test('no result yet writes nothing', () {
      final all = bracket();
      expect(dependentSlotWrites(completed: all.first, otherKnockoutMatches: all), isEmpty);
    });
  });
}
