import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/match_rules_stamp.dart';
import 'package:flow_sports_app/core/cricket/rules_summary.dart';
import 'package:flow_sports_app/core/cricket/tournament_plan.dart';
import 'package:flow_sports_app/core/utils/bracket_resolver.dart';
import 'package:flow_sports_app/core/utils/round_robin.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/models/standing_row.dart';
import 'package:flow_sports_app/models/team.dart';
import 'package:flutter_test/flutter_test.dart';

const _noKnockout = CricketTournamentConfig(knockout: false);

TournamentPreview preview(
  int teams, {
  List<int> sections = const [],
  int unassigned = 0,
  CricketTournamentConfig config = const CricketTournamentConfig(),
  int defaultOvers = 6,
}) =>
    previewTournament(
      teamCount: teams,
      sectionSizes: sections,
      unassigned: unassigned,
      config: config,
      defaultOvers: defaultOvers,
    );

Team _team(String id) =>
    Team(id: id, sport: 'cricket', category: 'boys', name: 'Team $id', season: '2026');

List<StandingRow> _seeds(int n) =>
    [for (var i = 1; i <= n; i++) StandingRow(teamId: 't$i', teamName: 'T$i')];

void main() {
  group('match counts — the proposal examples', () {
    test('round robin formula', () {
      expect([for (final n in [0, 1, 2, 3, 4, 6, 8, 12]) roundRobinMatches(n)], [0, 0, 1, 3, 6, 15, 28, 66]);
    });

    test('3 teams: league only 3, +top 2 = 4, +all 3 (seed 1 bye) = 5', () {
      expect(preview(3, config: _noKnockout).totalMin, 3);
      expect(preview(3, config: const CricketTournamentConfig(qualifiers: 2)).totalMin, 4);
      expect(preview(3, config: const CricketTournamentConfig(qualifiers: 3)).totalMin, 5);
    });

    test('4 teams: league 6, +top 2 = 7, +top 3 = 8, +top 4 (page playoff) = 10', () {
      expect(preview(4, config: _noKnockout).totalMin, 6);
      expect(preview(4, config: const CricketTournamentConfig(qualifiers: 2)).totalMin, 7);
      expect(preview(4, config: const CricketTournamentConfig(qualifiers: 3)).totalMin, 8);
      expect(preview(4).totalMin, 10);
    });

    test('6 teams: no sections 15 (+4 = 19); 2 sections of 3 = 6 (+4 = 10)', () {
      expect(preview(6).leagueMatches, 15);
      expect(preview(6).totalMin, 19);
      final sec = preview(6,
          sections: [3, 3], config: const CricketTournamentConfig(sections: 2, qualifiers: 2));
      expect(sec.leagueMatches, 6);
      expect(sec.sections.map((s) => s.leagueMatches), [3, 3]);
      expect(sec.qualifiers, 4);
      expect(sec.totalMin, 10);
      expect(sec.canGenerate, isTrue);
    });

    test('8 teams: no sections 28 (+4 = 32); 2 sections of 4 = 12 league (+4 = 16)', () {
      expect(preview(8).totalMin, 32);
      final sec = preview(8,
          sections: [4, 4], config: const CricketTournamentConfig(sections: 2, qualifiers: 2));
      expect(sec.leagueMatches, 12);
      expect(sec.sections.map((s) => s.leagueMatches), [6, 6]);
      expect(sec.totalMin, 16);
      final top1 = preview(8,
          sections: [4, 4], config: const CricketTournamentConfig(sections: 2, qualifiers: 1));
      expect(top1.totalMin, 13); // 12 league + a Final
    });

    test('12 teams: no sections 66 (+4 = 70); 3 sections of 4 = 18 league', () {
      expect(preview(12).leagueMatches, 66);
      expect(preview(12).totalMin, 70);
      final top1 = preview(12,
          sections: [4, 4, 4], config: const CricketTournamentConfig(sections: 3, qualifiers: 1));
      expect(top1.leagueMatches, 18);
      expect(top1.qualifiers, 3);
      expect(top1.totalMin, 20); // seed 1 bye + semifinal + final
      final top2 = preview(12,
          sections: [4, 4, 4], config: const CricketTournamentConfig(sections: 3, qualifiers: 2));
      expect(top2.qualifiers, 6);
      expect(top2.totalMin, 23); // 18 + 5
      expect(top2.warnings.any((w) => w.contains("can't be generated yet")), isTrue);
    });

    test('best-of-3 Final adds 1 to 2 matches and shows as a range', () {
      final four = preview(4, config: const CricketTournamentConfig(bestOfThreeFinal: true));
      expect([four.totalMin, four.totalMax], [11, 12]);
      final two = preview(2, config: const CricketTournamentConfig(qualifiers: 2, bestOfThreeFinal: true));
      expect([two.knockoutMin, two.knockoutMax], [2, 3]);
    });

    test('the preview agrees with what the real generators produce', () {
      final teams = [for (var i = 1; i <= 8; i++) _team('t$i')];
      final sectioned = generateSectionedLeagueMatches(
        teams: [
          for (var i = 0; i < teams.length; i++)
            Team(
              id: teams[i].id,
              sport: 'cricket',
              category: 'boys',
              name: teams[i].name,
              season: '2026',
              section: i.isEven ? 'A' : 'B',
            ),
        ],
        sport: 'cricket',
        category: 'boys',
        season: '2026',
      );
      expect(
        sectioned.length,
        preview(8, sections: [4, 4], config: const CricketTournamentConfig(sections: 2)).leagueMatches,
      );

      int count(List<Match> m) => m.length;
      for (final bo3 in [false, true]) {
        final cfg = CricketTournamentConfig(bestOfThreeFinal: bo3);
        expect(
          count(generateKnockoutMatches(
              top4Seeds: _seeds(4), sport: 'cricket', category: 'boys', season: '2026', bestOfThreeFinal: bo3)),
          preview(4, config: cfg.copyWith(qualifiers: 4)).knockoutMin,
        );
        expect(
          count(generateKnockoutMatchesForThree(
              threeSeeds: _seeds(3), sport: 'cricket', category: 'boys', season: '2026', bestOfThreeFinal: bo3)),
          preview(3, config: cfg.copyWith(qualifiers: 3)).knockoutMin,
        );
        expect(
          count(generateKnockoutMatchesForTwo(
              twoSeeds: _seeds(2), sport: 'cricket', category: 'boys', season: '2026', bestOfThreeFinal: bo3)),
          preview(2, config: cfg.copyWith(qualifiers: 2)).knockoutMin,
        );
      }
    });
  });

  group('blockers and warnings', () {
    test('fewer than 2 teams', () {
      expect(preview(1).blockers, contains('Add at least 2 teams.'));
      expect(preview(0).canGenerate, isFalse);
    });

    test('unassigned teams and tiny sections block generation', () {
      final r = preview(7,
          sections: [4, 2, 1],
          unassigned: 0,
          config: const CricketTournamentConfig(sections: 3, qualifiers: 1));
      expect(r.blockers.single, 'Section C needs at least 2 teams (it has 1).');
      final u = preview(6,
          sections: [2, 2],
          unassigned: 2,
          config: const CricketTournamentConfig(sections: 2, qualifiers: 1));
      expect(u.blockers, contains('2 teams have no section yet.'));
    });

    test('qualifiers can\'t exceed the smallest section or the team count', () {
      final s = preview(7,
          sections: [4, 3], config: const CricketTournamentConfig(sections: 2, qualifiers: 4));
      expect(s.blockers.single, contains('more than the smallest section'));
      final f = preview(3, config: const CricketTournamentConfig(qualifiers: 4));
      expect(f.blockers.single, contains("Only 3 teams"));
    });

    test('unequal section sizes warn (but do not block)', () {
      final r = preview(7,
          sections: [4, 3], config: const CricketTournamentConfig(sections: 2, qualifiers: 2));
      expect(r.canGenerate, isTrue);
      expect(r.warnings.any((w) => w.contains('different sizes')), isTrue);
      expect(r.leagueMatches, 6 + 3);
    });

    test('wildcards are BLOCKED when section sizes are unequal', () {
      final r = preview(7,
          sections: [4, 3],
          config: const CricketTournamentConfig(sections: 2, qualifiers: 1, wildcards: 1));
      expect(r.canGenerate, isFalse);
      expect(r.blockers.single, contains('same number of teams'));
    });

    test('wildcards allowed with equal sections, and counted', () {
      final r = preview(12,
          sections: [4, 4, 4],
          config: const CricketTournamentConfig(sections: 3, qualifiers: 1, wildcards: 1));
      expect(r.canGenerate, isTrue);
      expect(r.qualifiers, 4);
      expect(r.knockoutMin, 4);
      expect(r.totalMin, 22);
    });

    test('too many wildcards, or wildcards with nobody left to pick, are blocked', () {
      final many = preview(12,
          sections: [4, 4, 4],
          config: const CricketTournamentConfig(sections: 3, qualifiers: 1, wildcards: 3));
      expect(many.blockers.single, contains('At most 2 wildcards'));
      final none = preview(6,
          sections: [2, 2, 2],
          config: const CricketTournamentConfig(sections: 3, qualifiers: 2, wildcards: 1));
      expect(none.blockers.any((b) => b.contains('more teams than it qualifies')), isTrue);
    });

    test('league only: no knockout stages or qualifiers', () {
      final r = preview(5, config: _noKnockout);
      expect(r.qualifiers, 0);
      expect(r.knockoutMin, 0);
      expect(r.overs.keys, [CricketStage.league, CricketStage.tiebreaker]);
    });
  });

  group('overs per stage in the preview', () {
    test('defaults fill every stage; overrides win', () {
      final r = preview(
        4,
        defaultOvers: 6,
        config: const CricketTournamentConfig(stageOvers: {
          CricketStage.finalGame: 10,
          CricketStage.semifinal: 8,
        }),
      );
      expect(r.overs, {
        CricketStage.league: 6,
        CricketStage.semifinal: 8,
        CricketStage.qualifier: 6,
        CricketStage.finalGame: 10,
        CricketStage.tiebreaker: 6,
      });
    });

    test('stages listed follow the knockout shape', () {
      expect(knockoutStagesFor(2), [CricketStage.finalGame]);
      expect(knockoutStagesFor(3), [CricketStage.semifinal, CricketStage.finalGame]);
      expect(knockoutStagesFor(4),
          [CricketStage.semifinal, CricketStage.qualifier, CricketStage.finalGame]);
      expect(knockoutStagesFor(6),
          [CricketStage.quarterfinal, CricketStage.semifinal, CricketStage.finalGame]);
      expect(knockoutStagesFor(1), isEmpty);
    });
  });

  group('auto-balanced sections', () {
    test('snake order spreads strength: 4 teams / 2 sections', () {
      expect(autoBalanceSections(['a', 'b', 'c', 'd'], 2), {'a': 'A', 'b': 'B', 'c': 'B', 'd': 'A'});
    });

    test('8 teams / 3 sections gives sizes 3, 3, 2', () {
      final ids = [for (var i = 0; i < 8; i++) 't$i'];
      final m = autoBalanceSections(ids, 3);
      expect([for (final s in ['A', 'B', 'C']) m.values.where((v) => v == s).length], [3, 3, 2]);
      expect(m['t0'], 'A');
      expect(m['t3'], 'C'); // snake: second row runs back C, B, A
      expect(m['t5'], 'A');
    });

    test('1 section puts everyone together; letters', () {
      expect(autoBalanceSections(['x', 'y'], 1).values.toSet(), {'A'});
      expect([for (var i = 0; i < 4; i++) sectionLetter(i)], ['A', 'B', 'C', 'D']);
    });
  });

  group('stage of a generated match', () {
    test('codes map to stages', () {
      expect(cricketStageForMatch(MatchStage.league, 'L3'), CricketStage.league);
      expect(cricketStageForMatch(MatchStage.league, 'A-L2'), CricketStage.league);
      expect(cricketStageForMatch(MatchStage.tiebreaker, 'TB1_1'), CricketStage.tiebreaker);
      expect(cricketStageForMatch(MatchStage.knockout, 'KO1'), CricketStage.semifinal);
      expect(cricketStageForMatch(MatchStage.knockout, 'KO2'), CricketStage.semifinal);
      expect(cricketStageForMatch(MatchStage.knockout, 'KO3'), CricketStage.qualifier);
      expect(cricketStageForMatch(MatchStage.knockout, 'KOF'), CricketStage.finalGame);
      expect(cricketStageForMatch(MatchStage.knockout, 'KOF1'), CricketStage.finalGame);
      expect(cricketStageForMatch(MatchStage.knockout, 'KOF3'), CricketStage.finalGame);
      expect(cricketStageForMatch(MatchStage.knockout, 'QF2'), CricketStage.quarterfinal);
      expect(cricketStageForMatch(MatchStage.knockout, 'mystery'), isNull);
    });
  });

  group('per-bowler limits', () {
    test('suggested limit by overs, never decreasing', () {
      expect([for (final o in [1, 3, 4, 6, 10, 11, 15, 20, 50]) suggestedMaxOversPerBowler(o)],
          [1, 1, 2, 2, 2, 3, 3, 4, 10]);
      var prev = 0;
      for (var o = 1; o <= 60; o++) {
        final v = suggestedMaxOversPerBowler(o);
        expect(v >= prev, isTrue, reason: 'overs $o');
        prev = v;
      }
    });

    test('presets carry the suggested limit for their overs', () {
      expect(const CricketRules.tapeBall().maxOversPerBowler,
          suggestedMaxOversPerBowler(const CricketRules.tapeBall().overs));
      expect(const CricketRules.t20().maxOversPerBowler,
          suggestedMaxOversPerBowler(const CricketRules.t20().overs));
    });

    test('a suggested default limit follows a stage\'s overs; a custom one is kept', () {
      expect(maxOversPerBowlerFor(const CricketRules.tapeBall(), 20), 4);
      expect(maxOversPerBowlerFor(const CricketRules.t20(), 6), 2);
      const custom = CricketRules(overs: 6, maxOversPerBowler: 3);
      expect(maxOversPerBowlerFor(custom, 10), 3);
      expect(maxOversPerBowlerFor(custom, 2), 2); // never above the overs
      expect(maxOversPerBowlerFor(const CricketRules(maxOversPerBowler: null), 10), isNull);
    });

    test('warning when the squad cannot cover the overs', () {
      const r = CricketRules(overs: 10, maxOversPerBowler: 2);
      expect(bowlerSupplyWarning(squadCount: 4, rules: r),
          '10 overs with at most 2 per bowler needs at least 5 bowlers, but only 4 players are selected.');
      expect(bowlerSupplyWarning(squadCount: 5, rules: r), isNull);
      expect(bowlerSupplyWarning(squadCount: 1, rules: r)!.contains('1 player is'), isTrue);
      expect(bowlerSupplyWarning(squadCount: 1, rules: const CricketRules(maxOversPerBowler: null)), isNull);
    });
  });

  group('config storage and stage rules', () {
    test('map round trip, and bad stage names / values are ignored', () {
      const cfg = CricketTournamentConfig(
        sections: 3,
        qualifiers: 2,
        wildcards: 1,
        bestOfThreeFinal: true,
        stageOvers: {CricketStage.finalGame: 10, CricketStage.league: 6},
      );
      final back = CricketTournamentConfig.fromMap(cfg.toMap());
      expect(back.toMap(), cfg.toMap());
      expect(back.stageOvers[CricketStage.finalGame], 10);

      final messy = CricketTournamentConfig.fromMap({
        'stageOvers': {'finalGame': 12, 'nonsense': 3, 'league': 0, 'semifinal': 'x'},
      });
      expect(messy.stageOvers, {CricketStage.finalGame: 12});
      expect(CricketTournamentConfig.fromMap(null).sections, 1);
    });

    test('rulesForStage applies the stage overs (and its limit) only to that stage', () {
      const defaults = CricketRules.tapeBall(); // 6 overs, limit 2
      const cfg = CricketTournamentConfig(stageOvers: {CricketStage.finalGame: 20});
      final finalRules = rulesForStage(defaults, cfg, CricketStage.finalGame);
      expect(finalRules.overs, 20);
      expect(finalRules.maxOversPerBowler, 4);
      expect(finalRules.squadSize, defaults.squadSize); // everything else unchanged
      expect(rulesForStage(defaults, cfg, CricketStage.league).overs, 6);
      expect(rulesForStage(defaults, cfg, null).overs, 6);
      expect(rulesForStage(defaults, null, CricketStage.finalGame).overs, 6);
    });
  });

  group('stamping with stage overs', () {
    test('league 6 overs, semifinal 8, final 10 — each match is stamped by its own stage', () {
      const defaults = CricketRules.tapeBall();
      const plan = CricketTournamentConfig(
        bestOfThreeFinal: true,
        stageOvers: {CricketStage.semifinal: 8, CricketStage.finalGame: 10},
      );
      final league = generateLeagueMatches(
        teams: [for (var i = 1; i <= 4; i++) _team('t$i')],
        sport: 'cricket',
        category: 'boys',
        season: '2026',
      );
      final knockout = generateKnockoutMatches(
        top4Seeds: _seeds(4),
        sport: 'cricket',
        category: 'boys',
        season: '2026',
        bestOfThreeFinal: true,
      );
      final plans = {cricketPlanKey('boys', '2026'): plan};
      final stamped = stampCricketRules([...league, ...knockout], defaults, plans: plans);
      int overs(String code) => stamped.firstWhere((m) => m.matchCode == code).rules!.overs;
      expect(stamped.where((m) => m.matchCode.startsWith('L')).every((m) => m.rules!.overs == 6), isTrue);
      expect(overs('KO1'), 8);
      expect(overs('KO2'), 8);
      expect(overs('KO3'), 6); // qualifier: no override, uses the default
      expect(overs('KOF1'), 10);
      expect(overs('KOF2'), 10);
    });

    test('a plan for another category or season is not applied', () {
      final league = generateLeagueMatches(
        teams: [_team('a'), _team('b')],
        sport: 'cricket',
        category: 'girls',
        season: '2026',
      );
      final plans = {
        cricketPlanKey('boys', '2026'):
            const CricketTournamentConfig(stageOvers: {CricketStage.league: 12}),
      };
      final out = stampCricketRules(league, const CricketRules.tapeBall(), plans: plans);
      expect(out.single.rules!.overs, 6);
    });

    test('plan doc id is per category and season', () {
      expect(cricketPlanDocId('boys', '2026'), 'cricketPlan_boys_2026');
      expect(cricketPlanDocId('girls', 'abc'), 'cricketPlan_girls_abc');
    });
  });

  group('squad warnings', () {
    test('unequal squads warn, equal squads do not', () {
      expect(unequalSquadsWarning(nameA: 'A', countA: 6, nameB: 'B', countB: 6), isNull);
      final w = unequalSquadsWarning(nameA: 'Strikers', countA: 5, nameB: 'Titans', countB: 8)!;
      expect(w, contains('Strikers has 5 players'));
      expect(w, contains('Titans has 8'));
      expect(w, contains('allowed'));
    });
  });
}
