import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flow_sports_app/core/utils/delete_warning.dart';
import 'package:flow_sports_app/core/utils/reset_summary.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/services/firestore_service.dart';
import 'package:flutter_test/flutter_test.dart';

Match match({
  String sport = 'badminton',
  String category = 'boys',
  MatchStage stage = MatchStage.league,
  MatchStatus status = MatchStatus.upcoming,
  int? a,
  int? b,
  MatchResult? result,
  String? resultText,
}) =>
    Match(
      id: 'm',
      sport: sport,
      category: category,
      season: '2026',
      stage: stage,
      matchNumber: 1,
      label: 'Match 1',
      matchCode: 'L1',
      teamA: const TeamRef(teamId: 'a', name: 'Reds'),
      teamB: const TeamRef(teamId: 'b', name: 'Blues'),
      notifyTopic: '',
      status: status,
      scoreA: a,
      scoreB: b,
      result: result,
      resultText: resultText,
    );

void main() {
  group('reset summary', () {
    test('counts per category, Boys then Girls then others', () {
      final s = summarizeReset([
        match(category: 'girls'),
        match(category: 'test', status: MatchStatus.completed, result: MatchResult.teamA),
        match(category: 'boys', status: MatchStatus.completed, result: MatchResult.teamA),
        match(category: 'boys', status: MatchStatus.live),
        match(category: 'boys'),
      ]);
      expect(s.lines.map((l) => l.text), [
        'Boys: 3 matches — 1 with results, 1 live now',
        'Girls: 1 match',
        'Test: 1 match — 1 with results',
      ]);
      expect(s.total, 5);
      expect(s.played, 2);
    });

    test('empty', () {
      expect(summarizeReset(const []).isEmpty, isTrue);
    });
  });

  group('the reset really deletes what the summary listed', () {
    test('every category of the sport, none of another sport', () async {
      final db = FakeFirebaseFirestore();
      final fs = FirestoreService(firestore: db);
      Future<void> add(String sport, String category) => db.collection('matches').add({
            'sport': sport, 'category': category, 'season': '2026', 'stage': 'league', 'matchNumber': 1,
            'label': 'M', 'matchCode': 'L1', 'status': 'upcoming', 'notifyTopic': '',
            'teamA': {'teamId': 'a', 'name': 'A'}, 'teamB': {'teamId': 'b', 'name': 'B'},
          });
      await add('cricket', 'boys');
      await add('cricket', 'girls');
      await add('cricket', 'test');
      await add('badminton', 'boys');
      final listed = await fs.fetchSportMatches(sport: 'cricket', season: '2026');
      expect(listed.length, 3);
      await fs.resetSportMatches(sport: 'cricket', season: '2026');
      expect((await fs.fetchSportMatches(sport: 'cricket', season: '2026')), isEmpty);
      expect((await fs.fetchSportMatches(sport: 'badminton', season: '2026')).length, 1);
    });
  });

  group('delete consequences', () {
    test('an untouched upcoming league match has nothing to warn about', () {
      expect(deleteMatchConsequences(match()), isEmpty);
    });

    test('a live match', () {
      final l = deleteMatchConsequences(match(status: MatchStatus.live));
      expect(l.first, contains('live right now'));
      expect(l.any((t) => t.contains('point-by-point')), isTrue);
    });

    test('a played league match: result lost and standings change', () {
      final l = deleteMatchConsequences(
          match(status: MatchStatus.completed, a: 21, b: 15, result: MatchResult.teamA));
      expect(l, contains('Its saved result is lost: Reds 21 – 15 Blues.'));
      expect(l.any((t) => t.contains('standings change')), isTrue);
    });

    test('a knockout match leaves the bracket incomplete', () {
      final l = deleteMatchConsequences(match(stage: MatchStage.knockout));
      expect(l.single, contains('knockout bracket'));
    });

    test('cricket: names the result text and the ball-by-ball record', () {
      final l = deleteMatchConsequences(match(
        sport: 'cricket',
        status: MatchStatus.completed,
        a: 40,
        b: 38,
        result: MatchResult.teamA,
        resultText: 'Reds won by 2 runs',
      ));
      expect(l, contains('Its saved result is lost: Reds won by 2 runs.'));
      expect(l.any((t) => t.contains('ball-by-ball scoring')), isTrue);
    });
  });
}
