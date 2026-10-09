import 'cricket_event.dart';
import 'cricket_rules.dart';
import 'innings_replay.dart';

/// One plain-English line for a delivery, generated from the ball log so the
/// admin doesn't have to type commentary while scoring. [nameOf] resolves a
/// player id to a display name *at read time* (names are never stored on
/// ball events).
String ballCommentary(
  BallRecord r,
  String Function(String id) nameOf, {
  bool freeHitRule = true,
}) {
  String name(String? id) => id == null ? 'someone' : nameOf(id);
  final lead = '${name(r.bowlerId)} to ${name(r.strikerId)}';

  final String what;
  switch (r.delivery) {
    case Delivery.deadBall:
      return 'Dead ball — bowled again.';
    case Delivery.wide:
      what = r.teamRuns > 1 ? 'Wide, ${r.teamRuns} runs' : 'Wide';
    case Delivery.noBall:
      final extra = r.teamRuns > 1 ? ' and ${r.teamRuns - 1} more' : '';
      what = 'No ball$extra${freeHitRule ? ' — free hit next' : ''}';
    case Delivery.legal:
      if (r.batRuns == 0 && r.teamRuns == 0) {
        what = 'no run';
      } else if (r.batRuns == 0) {
        what = '${r.teamRuns} ${r.teamRuns == 1 ? 'bye/leg bye' : 'byes/leg byes'}';
      } else if (r.completedRuns == 0 && r.batRuns >= 6) {
        what = 'SIX!';
      } else if (r.completedRuns == 0 && r.batRuns >= 4) {
        what = 'FOUR!';
      } else {
        what = '${r.batRuns} ${r.batRuns == 1 ? 'run' : 'runs'}';
      }
  }

  final kind = r.wicketKind;
  if (kind == null) return '$lead, $what';
  final out = name(r.outBatterId);
  final how = switch (kind) {
    WicketKind.bowled => '$out is bowled!',
    WicketKind.caught =>
      r.fielderId == null ? '$out is caught!' : '$out is caught by ${name(r.fielderId)}!',
    WicketKind.lbw => '$out is out LBW!',
    WicketKind.runOut =>
      r.fielderId == null ? '$out is run out!' : '$out is run out by ${name(r.fielderId)}!',
    WicketKind.stumped => '$out is stumped!',
    WicketKind.hitWicket => '$out is out, hit wicket!',
    _ => '$out is out (${kind.label.toLowerCase()})!',
  };
  return '$lead, OUT! $how';
}
