import '../core/utils/bracket_resolver.dart';
import '../models/match.dart';
import 'firestore_service.dart';

/// Knockout bookkeeping shared by every way a cricket match can finish
/// (scored to a result, walkover): who advances into the next round, and what
/// has to be cleared again when a finished match is reopened.

/// What finishing [m] with a winner would write to the later rounds, or why it
/// can't ([problem] set): a later round already started from the old result.
Future<({String? problem, List<SlotWrite> writes})> planKnockoutAdvance(
  FirestoreService service,
  Match m, {
  required int? scoreA,
  required int? scoreB,
  required MatchResult result,
}) async {
  final all = await service.fetchMatches(
    sport: m.sport,
    category: m.category,
    season: m.season,
    stage: 'knockout',
  );
  final completed = Match(
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
    scoreA: scoreA,
    scoreB: scoreB,
    result: result,
    status: MatchStatus.completed,
    notifyTopic: m.notifyTopic,
  );
  final others = all.where((x) => x.id != m.id).toList();
  final stale = staleDependentUpdates(
    resolveDependentSlots(completed: completed, otherKnockoutMatches: others),
    all,
  );
  if (stale.isNotEmpty) {
    return (
      problem:
          'This changes who advances, but ${stale.map((x) => x.label).join(', ')} already started or was '
          'played. Reset the later round first, then save this result.',
      writes: const <SlotWrite>[],
    );
  }
  return (
    problem: null,
    writes: dependentSlotWrites(
      completed: completed,
      otherKnockoutMatches: others,
    ),
  );
}

/// What reopening the finished knockout match [m] has to clear in later
/// rounds, or why it can't ([problem] set): a later round was already started.
Future<({String? problem, List<SlotWrite> clears})> planKnockoutReopen(
  FirestoreService service,
  Match m,
) async {
  final all = await service.fetchMatches(
    sport: m.sport,
    category: m.category,
    season: m.season,
    stage: 'knockout',
  );
  final dependents = dependentsOf(
    m.matchCode,
    all.where((x) => x.id != m.id).toList(),
  );
  final started = dependents.where(isStarted).toList();
  if (started.isNotEmpty) {
    return (
      problem:
          "Can't reopen ${m.label}: ${started.map((x) => x.label).join(', ')} "
          '${started.length == 1 ? 'has' : 'have'} already been started or played from its result. '
          'Reset the later round first, then come back to this match.',
      clears: const <SlotWrite>[],
    );
  }
  return (problem: null, clears: unresolveSlotWrites(m.matchCode, dependents));
}
