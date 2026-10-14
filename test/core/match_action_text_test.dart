import 'package:flow_sports_app/core/utils/live_score.dart';
import 'package:flow_sports_app/core/utils/match_action_text.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flutter_test/flutter_test.dart';

Match match({
  MatchStage stage = MatchStage.league,
  MatchStatus status = MatchStatus.upcoming,
  int? a,
  int? b,
  MatchResult? result,
  MatchSource? srcA,
  MatchSource? srcB,
}) =>
    Match(
      id: 'm',
      sport: 'badminton',
      category: 'boys',
      season: '2026',
      stage: stage,
      matchNumber: 1,
      label: 'Match 1',
      matchCode: 'L1',
      teamA: const TeamRef(teamId: 'a', name: 'Reds'),
      teamB: const TeamRef(teamId: 'b', name: 'Blues'),
      teamASource: srcA,
      teamBSource: srcB,
      notifyTopic: '',
      status: status,
      scoreA: a,
      scoreB: b,
      result: result,
    );

void main() {
  group('Start / Reset text', () {
    test('starting an upcoming match', () {
      final t = statusChangeText(match(), MatchStatus.live)!;
      expect(t.title, 'Start this match?');
      expect(t.message, contains('LIVE for every viewer'));
      expect(t.bullets, isEmpty);
    });

    test('resetting a live match', () {
      final t = statusChangeText(match(status: MatchStatus.live), MatchStatus.upcoming)!;
      expect(t.title, 'Reset to Upcoming?');
      expect(t.message, contains('stops being LIVE'));
    });

    test('resetting a finished league match says the result stops counting', () {
      final t = statusChangeText(
          match(status: MatchStatus.completed, a: 21, b: 15, result: MatchResult.teamA), MatchStatus.upcoming)!;
      expect(t.bullets.single, contains('stops counting in the standings'));
    });

    test('a finished knockout match also warns about later rounds', () {
      final t = statusChangeText(
          match(stage: MatchStage.knockout, status: MatchStatus.completed, a: 21, b: 15, result: MatchResult.teamA),
          MatchStatus.live)!;
      expect(t.title, 'Restart a finished match?');
      expect(t.bullets.length, 2);
      expect(t.bullets.last, contains('later rounds'));
    });

    test('no change, or moving to completed here, has no text', () {
      expect(statusChangeText(match(), MatchStatus.upcoming), isNull);
      expect(statusChangeText(match(status: MatchStatus.live), MatchStatus.completed), isNull);
    });
  });

  group('result summary', () {
    test('league win: points for the winner', () {
      final l = resultSummaryLines(match: match(), scoreA: 21, scoreB: 15);
      expect(l, [
        'Reds beat Blues, 21–15.',
        'Reds gets 2 standings points, Blues gets 0.',
        'Viewers see it at once.',
      ]);
    });

    test('league tie', () {
      final l = resultSummaryLines(match: match(), scoreA: 10, scoreB: 10);
      expect(l, contains('Each team gets 1 standings point.'));
    });

    test('knockout names where teams move on to', () {
      final l = resultSummaryLines(
        match: match(stage: MatchStage.knockout),
        scoreA: 15,
        scoreB: 21,
        advances: const ['Final', 'KO3'],
      );
      expect(l, contains('Blues beat Reds, 21–15.'));
      expect(l, contains('Teams move on to: Final, KO3.'));
      expect(l.any((t) => t.contains('standings points')), isFalse);
    });

    test('correcting a saved result says it replaces it, and when the winner changes', () {
      final saved = match(status: MatchStatus.completed, a: 21, b: 15, result: MatchResult.teamA);
      final sameWinner = resultSummaryLines(match: saved, scoreA: 21, scoreB: 17);
      expect(sameWinner, contains('This replaces the saved score (21–15).'));
      final flipped = resultSummaryLines(match: saved, scoreA: 15, scoreB: 21);
      expect(flipped, contains('This REPLACES the saved result (21–15) and changes the winner.'));
      final unchanged = resultSummaryLines(match: saved, scoreA: 21, scoreB: 15);
      expect(unchanged.any((t) => t.contains('replaces') || t.contains('REPLACES')), isFalse);
    });
  });

  group('qualifier count from the bracket', () {
    Match ko(int? seedA, int? seedB) => match(
          stage: MatchStage.knockout,
          srcA: seedA == null ? null : MatchSource.seed(seedA),
          srcB: seedB == null ? const MatchSource.winnerOf('KO1') : MatchSource.seed(seedB),
        );

    test('no bracket yet: 4', () {
      expect(qualifierCountFromBracket(const []), 4);
    });
    test('2, 3 and 4 team brackets', () {
      expect(qualifierCountFromBracket([ko(1, 2)]), 2);
      expect(qualifierCountFromBracket([ko(1, 2), ko(null, 3)]), 3);
      expect(qualifierCountFromBracket([ko(1, 2), ko(3, 4)]), 4);
    });
    test('a source with no seeds falls back', () {
      expect(qualifierCountFromBracket([ko(null, null)]), 4);
    });
  });

  group('live score maths', () {
    test('plus and minus for each team, never below 0 or above 999', () {
      expect(nextLiveScore(5, 7, team: 'A', delta: 1), (6, 7));
      expect(nextLiveScore(5, 7, team: 'B', delta: -1), (5, 6));
      expect(nextLiveScore(0, 7, team: 'A', delta: -1), (0, 7));
      expect(nextLiveScore(999, 0, team: 'A', delta: 1), (999, 0));
    });
  });
}
