import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/match_rules_stamp.dart';
import 'package:flow_sports_app/core/utils/bracket_resolver.dart';
import 'package:flow_sports_app/core/utils/round_robin.dart';
import 'package:flow_sports_app/models/standing_row.dart';
import 'package:flow_sports_app/models/team.dart';
import 'package:flutter_test/flutter_test.dart';

Team _team(String id, String sport) =>
    Team(id: id, sport: sport, category: 'boys', name: 'Team $id', season: '2026');

void main() {
  const tenOvers = CricketRules(overs: 10);

  group('stampCricketRules', () {
    test('every generated cricket match gets a copy of the rules', () {
      final matches = generateLeagueMatches(
        teams: [for (var i = 0; i < 4; i++) _team('t$i', 'cricket')],
        sport: 'cricket',
        category: 'boys',
        season: '2026',
      );
      expect(matches.every((m) => m.rules == null), isTrue);
      final stamped = stampCricketRules(matches, tenOvers);
      expect(stamped.length, 6);
      expect(stamped.every((m) => m.rules?.overs == 10), isTrue);
      // Everything else about the match is preserved.
      for (var i = 0; i < matches.length; i++) {
        expect(stamped[i].matchCode, matches[i].matchCode);
        expect(stamped[i].teamA.teamId, matches[i].teamA.teamId);
        expect(stamped[i].teamB.name, matches[i].teamB.name);
        expect(stamped[i].label, matches[i].label);
        expect(stamped[i].section, matches[i].section);
      }
    });

    test('knockout, tie-breaker and decider matches are stamped too', () {
      final seeds = [
        for (var i = 1; i <= 4; i++) StandingRow(teamId: 't$i', teamName: 'T$i'),
      ];
      final knockout = generateKnockoutMatches(
        top4Seeds: seeds,
        sport: 'cricket',
        category: 'boys',
        season: '2026',
        bestOfThreeFinal: true,
      );
      final tieBreakers = generateTiebreakerMatches(
        tiedTeams: seeds.take(3).toList(),
        sport: 'cricket',
        category: 'boys',
        season: '2026',
        round: 1,
      );
      final decider = generateFinalGame3(
        teamA: knockout.last.teamA,
        teamB: knockout.last.teamB,
        sport: 'cricket',
        category: 'boys',
        season: '2026',
        matchNumber: 9,
      );
      final all = stampCricketRules([...knockout, ...tieBreakers, decider], tenOvers);
      expect(all.length, knockout.length + tieBreakers.length + 1);
      expect(all.every((m) => m.rules?.overs == 10), isTrue);
    });

    test('a match that already has rules keeps them', () {
      final base = generateLeagueMatches(
        teams: [_team('a', 'cricket'), _team('b', 'cricket')],
        sport: 'cricket',
        category: 'boys',
        season: '2026',
      ).single;
      final own = base.withRules(const CricketRules(overs: 3));
      final result = stampCricketRules([own], tenOvers).single;
      expect(result.rules!.overs, 3);
      expect(needsCricketRules(own), isFalse);
    });

    test('badminton matches are never stamped', () {
      final matches = generateLeagueMatches(
        teams: [for (var i = 0; i < 4; i++) _team('t$i', 'badminton')],
        sport: 'badminton',
        category: 'boys',
        season: '2026',
      );
      expect(matches.any(needsCricketRules), isFalse);
      final out = stampCricketRules(matches, tenOvers);
      expect(out.every((m) => m.rules == null), isTrue);
      for (final m in out) {
        expect(m.toFirestore().containsKey('rules'), isFalse);
      }
    });
  });

  group('Match.toFirestore with rules', () {
    test('writes the rules snapshot only when the match has one', () {
      final base = generateLeagueMatches(
        teams: [_team('a', 'cricket'), _team('b', 'cricket')],
        sport: 'cricket',
        category: 'girls',
        season: '2026',
      ).single;
      expect(base.toFirestore().containsKey('rules'), isFalse);

      final stamped = base.withRules(tenOvers);
      final map = stamped.toFirestore();
      expect(CricketRules.fromMap(map['rules'] as Map<String, dynamic>).overs, 10);
    });

    test('later change to the default does not touch an already stamped match', () {
      final base = generateLeagueMatches(
        teams: [_team('a', 'cricket'), _team('b', 'cricket')],
        sport: 'cricket',
        category: 'boys',
        season: '2026',
      ).single;
      final stamped = stampCricketRules([base], const CricketRules(overs: 6)).single;
      // Default changes to 20 overs afterwards: matches already carrying rules are skipped.
      final again = stampCricketRules([stamped], const CricketRules(overs: 20)).single;
      expect(again.rules!.overs, 6);
    });
  });
}
