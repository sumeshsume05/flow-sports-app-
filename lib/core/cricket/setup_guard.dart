import 'dart:convert';

import 'cricket_rules.dart';
import 'cricket_toss.dart';
import 'match_scoring.dart';

/// What changing a match's setup (rules, squads, toss) would do once scoring
/// has started. [blockers] stop the save; [warnings] need a "yes, I'm sure".
class SetupChange {
  final List<String> blockers;
  final List<String> warnings;

  const SetupChange(this.blockers, this.warnings);

  bool get isClean => blockers.isEmpty && warnings.isEmpty;
}

/// Everyone the ball log mentions: openers, bowlers, batters out or coming
/// in, fielders, retirements. Removing one of them from the squad would
/// break the scorecard.
Set<String> playersInLog({
  required List<InningsStart> starts,
  required List<LoggedEvent> events,
}) {
  final ids = <String>{};
  for (final s in starts) {
    ids
      ..add(s.strikerId)
      ..add(s.nonStrikerId);
  }
  for (final l in events) {
    final e = l.event;
    for (final id in [
      e.bowlerId,
      e.retiredBatterId,
      e.newBatterId,
      e.wicket?.outBatterId,
      e.wicket?.newBatterId,
      e.wicket?.fielderId,
    ]) {
      if (id != null) ids.add(id);
    }
  }
  return ids;
}

/// Checks a setup change against a match that is already being scored (or is
/// finished). For an upcoming match everything is allowed.
SetupChange checkSetupChange({
  required bool started,
  required bool finished,
  required CricketRules? oldRules,
  required CricketRules newRules,
  required CricketToss? oldToss,
  required CricketToss? newToss,
  required List<String> oldLineupA,
  required List<String> oldLineupB,
  required List<String> newLineupA,
  required List<String> newLineupB,
  required List<InningsStart> starts,
  required List<LoggedEvent> events,
  required String Function(String id) nameOf,
}) {
  if (!started && !finished) return const SetupChange([], []);
  final blockers = <String>[];
  final warnings = <String>[];

  if (finished) {
    blockers.add('This match is finished. Open the scoring screen and tap "Reopen to edit" before '
        'changing its setup.');
  }

  if (oldToss != newToss) {
    blockers.add('The toss can\'t change once scoring has started — it decides who batted first.');
  }

  final used = playersInLog(starts: starts, events: events);
  final removed = <String>{
    for (final id in [...oldLineupA, ...oldLineupB])
      if (!newLineupA.contains(id) && !newLineupB.contains(id)) id,
  }..retainAll(used);
  if (removed.isNotEmpty) {
    final names = removed.map(nameOf).join(', ');
    blockers.add('${removed.length == 1 ? '$names has' : '$names have'} already batted, bowled or fielded in '
        'this match, so they can\'t be taken out of the squad.');
  }

  if (oldRules != null && jsonEncode(oldRules.toMap()) != jsonEncode(newRules.toMap())) {
    warnings.add('The rules changed. Balls already scored are counted again under the new rules, so the '
        'score or the overs may change.');
  }
  final added = [...newLineupA, ...newLineupB].where((id) => ![...oldLineupA, ...oldLineupB].contains(id));
  if (added.isNotEmpty) {
    warnings.add('${added.length} player${added.length == 1 ? '' : 's'} added to a squad after the match started.');
  }
  return SetupChange(blockers, warnings);
}
