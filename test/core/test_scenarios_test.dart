import 'package:flow_sports_app/core/constants.dart';
import 'package:flow_sports_app/core/test_lab/test_scenarios.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('test category is invisible to viewers by construction', () {
    test('Category.test is not in Category.all (Home and CSV loop over all)', () {
      expect(Category.all, isNot(contains(Category.test)));
      expect(Category.test, 'test');
      expect(categoryLabel(Category.test), 'Test');
    });
  });

  for (final sport in Sport.all) {
    group('scenarios for $sport', () {
      final scenarios = testScenariosFor(sport);

      test('ids are unique and there is a useful range of sizes', () {
        expect(scenarios.map((s) => s.id).toSet().length, scenarios.length);
        final teamCounts = scenarios.map((s) => s.teams).toSet();
        expect(teamCounts, containsAll([2, 3, 4, 6, 8]));
        expect(scenarios.any((s) => s.sectionSizes.isNotEmpty), isTrue);
        expect(scenarios.any((s) => s.sectionSizes.toSet().length > 1), isTrue, reason: 'an unequal-sections scenario');
      });

      for (final s in scenarios) {
        test('${s.id}: ${s.title}', () {
          final teams = buildScenarioTeams(sport, s);
          expect(teams.length, s.teams);
          expect(s.teams <= maxTestTeams, isTrue);
          // Team names are unique within the scenario.
          expect(teams.map((t) => t.name).toSet().length, teams.length);
          expect(teams.every((t) => t.name.trim().isNotEmpty), isTrue);

          // Sections match the declared sizes, in order.
          if (s.sectionSizes.isEmpty) {
            expect(teams.every((t) => t.section == null), isTrue);
          } else {
            expect(s.sectionSizes.fold<int>(0, (a, b) => a + b), s.teams);
            for (var i = 0; i < s.sectionSizes.length; i++) {
              final letter = String.fromCharCode(0x41 + i);
              expect(teams.where((t) => t.section == letter).length, s.sectionSizes[i]);
            }
            expect(teams.every((t) => t.section != null), isTrue);
          }

          if (sport == Sport.cricket) {
            for (var i = 0; i < teams.length; i++) {
              final expected = s.squadSizes.isEmpty ? defaultSquad : s.squadSizes[i];
              final players = teams[i].players;
              expect(players.length, expected, reason: 'team $i squad size');
              expect(players.map((p) => p.name).toSet().length, players.length,
                  reason: 'names unique within a team');
              expect(players.map((p) => p.id).toSet().length, players.length);
              expect(players.every((p) => p.active && p.role != null), isTrue);
            }
          } else {
            // Badminton teams are "First & Second" pairs with no roster.
            expect(teams.every((t) => t.players.isEmpty && t.name.contains(' & ')), isTrue);
          }
        });
      }
    });
  }

  test('player ids are unique across the whole scenario', () {
    final s = testScenariosFor(Sport.cricket).firstWhere((s) => s.id == 't12s3');
    final ids = [for (final t in buildScenarioTeams(Sport.cricket, s)) ...t.players.map((p) => p.id)];
    expect(ids.length, 12 * defaultSquad);
    expect(ids.toSet().length, ids.length);
  });

  test('badminton offers no 3-section scenario (its bracket supports 2 sections)', () {
    expect(testScenariosFor(Sport.badminton).every((s) => s.sectionSizes.length <= 2), isTrue);
    expect(testScenariosFor(Sport.cricket).any((s) => s.sectionSizes.length == 3), isTrue);
  });

  test('cricket-only scenarios cover unequal and full squads', () {
    final cricket = testScenariosFor(Sport.cricket);
    expect(cricket.any((s) => s.squadSizes.toSet().length > 1), isTrue);
    expect(cricket.any((s) => s.squadSizes.isNotEmpty && s.squadSizes.every((n) => n == 11)), isTrue);
    expect(testScenariosFor(Sport.badminton).every((s) => s.squadSizes.isEmpty), isTrue);
  });

  group('testScores', () {
    test('winner gets 21, loser is clamped to 0-19', () {
      expect(testScores(tie: false, aWins: true, loserScore: 7), (a: 21, b: 7));
      expect(testScores(tie: false, aWins: false, loserScore: 7), (a: 7, b: 21));
      expect(testScores(tie: false, aWins: true, loserScore: 40), (a: 21, b: 19));
      expect(testScores(tie: false, aWins: true, loserScore: -3), (a: 21, b: 0));
    });

    test('a tie is 21-21 regardless of the other inputs', () {
      expect(testScores(tie: true, aWins: true, loserScore: 3), (a: 21, b: 21));
    });
  });

  group('unplayedMatches', () {
    Match m(String id, {String? a = 'a', String? b = 'b', MatchResult? result}) => Match(
          id: id,
          sport: 'badminton',
          category: 'test',
          season: '2026',
          stage: MatchStage.tiebreaker,
          matchNumber: 1,
          label: id,
          matchCode: 'TB1_1',
          teamA: TeamRef(teamId: a, name: a),
          teamB: TeamRef(teamId: b, name: b),
          result: result,
          notifyTopic: 'x',
        );

    test('plays only matches with no result and both teams known', () {
      final all = [
        m('played', result: MatchResult.teamA),
        m('open'),
        m('waiting', a: null),
        m('open2', b: 'c'),
      ];
      expect(unplayedMatches(all).map((x) => x.id), ['open', 'open2']);
    });

    test('nothing to play when everything already has a result', () {
      expect(unplayedMatches([m('x', result: MatchResult.tie)]), isEmpty);
      expect(unplayedMatches(const []), isEmpty);
    });
  });
}
