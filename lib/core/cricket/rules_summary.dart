import 'cricket_rules.dart';

/// One-line, plain-English summary of a rule set for the schedule screen,
/// match setup and the viewer's "Info" tab — e.g.
/// "6 overs · 8 a side · No LBW · Free hit on".
String rulesSummary(CricketRules r) {
  final parts = <String>[
    '${r.overs} ${r.overs == 1 ? 'over' : 'overs'}',
    '${r.squadSize} a side',
    r.allowedWickets.contains(WicketKind.lbw) ? 'LBW on' : 'No LBW',
    r.freeHit ? 'Free hit on' : 'No free hit',
    if (!r.legByesAllowed) 'No leg byes',
    if (!r.byesAllowed) 'No byes',
    if (r.lastManStands) 'Last man stands',
    if (r.maxOversPerBowler != null) 'Max ${r.maxOversPerBowler} per bowler',
  ];
  return parts.join(' · ');
}

/// Why a chosen squad can't be used, or an empty list when it is fine.
List<String> squadProblems({
  required int selectedCount,
  required CricketRules rules,
  required String teamName,
}) {
  return [
    if (selectedCount < 2) '$teamName: pick at least 2 players.',
    if (selectedCount > rules.squadSize)
      '$teamName: at most ${rules.squadSize} players (you picked $selectedCount).',
  ];
}
