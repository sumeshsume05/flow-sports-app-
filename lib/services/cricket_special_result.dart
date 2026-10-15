import '../core/cricket/special_result.dart';
import '../core/utils/bracket_resolver.dart';
import '../models/match.dart';
import 'cricket_knockout.dart';
import 'firestore_service.dart';

/// Finishing a cricket match without playing it to a result. Each returns a
/// message when it can't, or null once saved.

Future<String?> recordNoResult(
  FirestoreService service,
  Match m, {
  String? reason,
}) async {
  final problem = noResultProblem(m);
  if (problem != null) return problem;
  await service.finishCricketMatch(
    m.id,
    resultFields: noResultFields(reason),
    slotWrites: const [],
  );
  return null;
}

/// [winner] is 'A' or 'B'. In a knockout the winner moves into the next round.
Future<String?> recordWalkover(
  FirestoreService service,
  Match m,
  String winner, {
  String? reason,
}) async {
  final problem = walkoverProblem(m);
  if (problem != null) return problem;
  final winnerName =
      (winner == 'A' ? m.teamA.name : m.teamB.name) ?? 'Team $winner';
  var slotWrites = <SlotWrite>[];
  if (m.stage == MatchStage.knockout) {
    final plan = await planKnockoutAdvance(
      service,
      m,
      scoreA: null,
      scoreB: null,
      result: winner == 'A' ? MatchResult.teamA : MatchResult.teamB,
    );
    if (plan.problem != null) return plan.problem;
    slotWrites = plan.writes;
  }
  await service.finishCricketMatch(
    m.id,
    resultFields: walkoverFields(winner, winnerName, reason),
    slotWrites: slotWrites,
  );
  return null;
}

/// Takes a walkover / no result back. The match returns to upcoming (never
/// played) or live (had balls), and a knockout's later slots are cleared.
Future<String?> undoSpecialResult(FirestoreService service, Match m) async {
  if (m.resultType == null) return 'This match was played to a normal result.';
  var clears = <SlotWrite>[];
  if (m.stage == MatchStage.knockout) {
    final plan = await planKnockoutReopen(service, m);
    if (plan.problem != null) return plan.problem;
    clears = plan.clears;
  }
  await service.reopenCricketMatch(
    m.id,
    clears: clears,
    status: m.innings.isEmpty ? MatchStatus.upcoming : MatchStatus.live,
  );
  return null;
}
