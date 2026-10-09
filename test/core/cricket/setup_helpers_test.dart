import 'package:flow_sports_app/core/constants.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/cricket_toss.dart';
import 'package:flow_sports_app/core/cricket/player_names.dart';
import 'package:flow_sports_app/core/cricket/rules_summary.dart';
import 'package:flow_sports_app/core/sports.dart';
import 'package:flow_sports_app/models/player.dart';
import 'package:flow_sports_app/models/team.dart';
import 'package:flow_sports_app/state/enabled_sports_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePlayerNames', () {
    test('one per line, trims and collapses spaces', () {
      final p = parsePlayerNames('  Ravi \nSam   Kumar\n\nAnil');
      expect(p.names, ['Ravi', 'Sam Kumar', 'Anil']);
      expect(p.duplicates, isEmpty);
    });

    test('strips numbering and bullets pasted from chat apps', () {
      final p = parsePlayerNames('1. Ravi\n2) Sam\n- Anil\n• Dev\n* Kiran\n3 - Mani');
      expect(p.names, ['Ravi', 'Sam', 'Anil', 'Dev', 'Kiran', 'Mani']);
    });

    test('commas and semicolons also split (a squad pasted on one line)', () {
      expect(parsePlayerNames('Ravi, Sam; Anil').names, ['Ravi', 'Sam', 'Anil']);
    });

    test('keeps names that merely contain digits or hyphens', () {
      expect(parsePlayerNames('Anna-Marie\nRahul 2').names, ['Anna-Marie', 'Rahul 2']);
    });

    test('duplicates within the paste and against existing names are reported', () {
      final p = parsePlayerNames('Ravi\nravi\nSam\nAnil', existing: ['SAM']);
      expect(p.names, ['Ravi', 'Anil']);
      expect(p.duplicates, ['ravi', 'Sam']);
    });

    test('empty input gives nothing', () {
      expect(parsePlayerNames('  \n\n').names, isEmpty);
    });
  });

  group('rulesSummary', () {
    test('tape-ball default', () {
      expect(
        rulesSummary(const CricketRules.tapeBall()),
        '6 overs · 8 a side · No LBW · Free hit on · No leg byes · Last man stands · Max 2 per bowler',
      );
    });

    test('T20', () {
      expect(rulesSummary(const CricketRules.t20()),
          '20 overs · 11 a side · LBW on · Free hit on · Max 4 per bowler');
    });

    test('singular over and switched-off options', () {
      final s = rulesSummary(const CricketRules(
        overs: 1,
        freeHit: false,
        byesAllowed: false,
        lastManStands: false,
        maxOversPerBowler: null,
      ));
      expect(s, '1 over · 8 a side · No LBW · No free hit · No leg byes · No byes');
    });
  });

  group('squadProblems', () {
    const rules = CricketRules(squadSize: 6);

    test('a valid squad has no problems', () {
      expect(squadProblems(selectedCount: 2, rules: rules, teamName: 'A'), isEmpty);
      expect(squadProblems(selectedCount: 6, rules: rules, teamName: 'A'), isEmpty);
    });

    test('too few or too many', () {
      expect(squadProblems(selectedCount: 1, rules: rules, teamName: 'A'),
          ['A: pick at least 2 players.']);
      expect(squadProblems(selectedCount: 7, rules: rules, teamName: 'B'),
          ['B: at most 6 players (you picked 7).']);
    });
  });

  group('CricketToss', () {
    test('who bats first', () {
      expect(const CricketToss(winner: 'A', elected: 'bat').battingFirstSide, 'A');
      expect(const CricketToss(winner: 'A', elected: 'bowl').battingFirstSide, 'B');
      expect(const CricketToss(winner: 'B', elected: 'bat').battingFirstSide, 'B');
      expect(const CricketToss(winner: 'B', elected: 'bowl').battingFirstSide, 'A');
    });

    test('map round trip, and rejects bad data', () {
      const t = CricketToss(winner: 'B', elected: 'bowl');
      expect(CricketToss.fromMap(t.toMap()), t);
      expect(CricketToss.fromMap(null), isNull);
      expect(CricketToss.fromMap({'winner': 'C', 'elected': 'bat'}), isNull);
      expect(CricketToss.fromMap({'winner': 'A', 'elected': 'field'}), isNull);
    });
  });

  group('Player & Team roster', () {
    test('Player map round trip, with and without a role', () {
      const withRole = Player(id: 'p1', name: 'Ravi', role: PlayerRole.bowl);
      expect(Player.fromMap(withRole.toMap()), withRole);
      const plain = Player(id: 'p2', name: 'Sam', active: false);
      expect(Player.fromMap(plain.toMap()), plain);
      expect(Player.fromMap({'id': 'p3', 'name': 'X', 'role': 'nonsense'}).role, isNull);
      expect(Player.fromMap({'id': 'p3', 'name': 'X'}).active, isTrue);
    });

    test('Player.newId is unique across a big bulk add', () {
      final ids = {for (var i = 0; i < 2000; i++) Player.newId()};
      expect(ids.length, 2000);
    });

    test('copyWith can rename, deactivate and clear the role', () {
      const p = Player(id: 'p1', name: 'Ravi', role: PlayerRole.bat);
      expect(p.copyWith(name: 'Ravi K').name, 'Ravi K');
      expect(p.copyWith(name: 'Ravi K').id, 'p1'); // id never changes on rename
      expect(p.copyWith(active: false).active, isFalse);
      expect(p.copyWith(clearRole: true).role, isNull);
    });

    test('Team stores players only when it has some; badminton docs stay unchanged', () {
      final plain = Team(id: 't', sport: 'badminton', category: 'boys', name: 'A & B', season: '2026');
      expect(plain.toFirestore().containsKey('players'), isFalse);

      final cricket = Team(
        id: 't',
        sport: 'cricket',
        category: 'boys',
        name: 'Strikers',
        season: '2026',
        players: const [Player(id: 'p1', name: 'Ravi'), Player(id: 'p2', name: 'Sam', active: false)],
      );
      final map = cricket.toFirestore();
      expect((map['players'] as List).length, 2);
      expect(cricket.activePlayers.map((p) => p.name), ['Ravi']);
    });

    test('Team.copyWith keeps players unless replaced', () {
      final t = Team(
        id: 't',
        sport: 'cricket',
        category: 'boys',
        name: 'S',
        season: '2026',
        players: const [Player(id: 'p1', name: 'Ravi')],
      );
      expect(t.copyWith(seed: 2).players.length, 1);
      expect(t.copyWith(players: const []).players, isEmpty);
    });
  });

  group('cricket in the sport registry', () {
    test('cricket is registered, labelled, and hidden from viewers by default', () {
      expect(Sport.all, contains(Sport.cricket));
      final c = sportConfig(Sport.cricket);
      expect(c.label, 'Cricket');
      expect(c.categoryTitle('boys'), 'Boys Cricket');
      expect(c.categoryTitle('girls'), 'Girls Cricket');
      expect(c.enabledByDefault, isFalse);
      expect(resolveSportEnabled(const {}, Sport.cricket), isFalse);
      expect(resolveSportEnabled(const {'cricket': true}, Sport.cricket), isTrue);
      // Turning cricket on/off never affects badminton.
      expect(resolveSportEnabled(const {'cricket': false}, Sport.badminton), isTrue);
    });

    test('sportFromQuery accepts cricket', () {
      expect(sportFromQuery('cricket'), 'cricket');
    });
  });
}
