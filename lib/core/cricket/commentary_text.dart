import 'cricket_event.dart';
import 'cricket_rules.dart';
import 'innings_replay.dart';

/// One plain-English line for a delivery, generated from the ball log so the
/// admin doesn't have to type commentary while scoring. [nameOf] resolves a
/// player id to a display name *at read time* (names are never stored on
/// ball events).
///
/// The batter comes first and the verb says who did what, so nobody has to
/// guess which name is the bowler: "FOUR! Arun hits Dinesh for 4",
/// "OUT! Arun is bowled by Dinesh".
String ballCommentary(
  BallRecord r,
  String Function(String id) nameOf, {
  bool freeHitRule = true,
}) {
  String name(String? id) => id == null ? 'someone' : nameOf(id);
  final bowler = name(r.bowlerId);
  final batter = name(r.strikerId);
  String runs(int n) => '$n ${n == 1 ? 'run' : 'runs'}';

  final kind = r.wicketKind;
  if (kind != null) {
    final out = name(r.outBatterId);
    final how = switch (kind) {
      WicketKind.bowled => '$out is bowled by $bowler',
      WicketKind.caught => r.fielderId == null
          ? '$out is caught (bowler $bowler)'
          : '$out is caught by ${name(r.fielderId)} (bowler $bowler)',
      WicketKind.lbw => '$out is out LBW (bowler $bowler)',
      WicketKind.runOut =>
        r.fielderId == null ? '$out is run out' : '$out is run out by ${name(r.fielderId)}',
      WicketKind.stumped => '$out is stumped (bowler $bowler)',
      WicketKind.hitWicket => '$out is out, hit wicket (bowler $bowler)',
      _ => '$out is out (${kind.label.toLowerCase()})',
    };
    return 'OUT! $how';
  }

  switch (r.delivery) {
    case Delivery.deadBall:
      return 'Dead ball — bowled again.';
    case Delivery.wide:
      return 'Wide ball by $bowler (+${r.teamRuns})';
    case Delivery.noBall:
      final bat = r.batRuns > 0 ? ' — $batter scores ${r.batRuns}' : '';
      return 'No ball by $bowler (+${r.teamRuns})$bat${freeHitRule ? ' — free hit next' : ''}';
    case Delivery.legal:
      if (r.batRuns == 0 && r.teamRuns == 0) return 'Dot ball: $batter defends $bowler\'s ball';
      if (r.batRuns == 0) {
        return '${r.teamRuns} ${r.teamRuns == 1 ? 'bye/leg bye' : 'byes/leg byes'} off $bowler\'s ball';
      }
      if (r.completedRuns == 0 && r.batRuns >= 6) return 'SIX! $batter hits $bowler for ${r.batRuns}';
      if (r.completedRuns == 0 && r.batRuns >= 4) return 'FOUR! $batter hits $bowler for ${r.batRuns}';
      return '$batter takes ${runs(r.batRuns)} off $bowler';
  }
}
