import '../../models/match.dart';

/// "No result" and "Walkover": the two ways a cricket match is finished
/// without being played to a normal result. Pure functions: they say what to
/// write on the match doc, and whether the admin is allowed to.

/// Why a no result can't be recorded, or null when it can. A knockout needs a
/// winner, so it can't end with no result — give it a walkover, or pick the
/// winner by hand on the scoring screen.
String? noResultProblem(Match m) {
  if (m.status == MatchStatus.completed) {
    return 'This match already has a result.';
  }
  if (m.stage == MatchStage.knockout) {
    return 'A knockout match needs a winner, so it can\'t end with no result. '
        'Use a walkover, or pick the winner by hand on the scoring screen.';
  }
  return null;
}

/// Why a walkover can't be recorded, or null when it can. Once balls have
/// been scored the match has a real scorecard, so finish it there instead.
String? walkoverProblem(Match m) {
  if (m.status == MatchStatus.completed) {
    return 'This match already has a result.';
  }
  if (m.teamA.teamId == null || m.teamB.teamId == null) {
    return 'Both teams must be decided before you can give a walkover.';
  }
  if (m.innings.isNotEmpty) {
    return 'Scoring has already started. Finish the match on the scoring screen, '
        'or reset it first.';
  }
  return null;
}

/// The result text for a no-result match: "No result" or "No result — rain".
String noResultText(String? reason) {
  final r = reason?.trim() ?? '';
  return r.isEmpty ? 'No result' : 'No result — $r';
}

/// "Reds won by walkover" or "Reds won by walkover (Blues did not turn up)".
String walkoverText(String winnerName, String? reason) {
  final r = reason?.trim() ?? '';
  return r.isEmpty
      ? '$winnerName won by walkover'
      : '$winnerName won by walkover ($r)';
}

/// Fields to write for a no-result match. `result: tie` only marks it as
/// finished — the points table reads `resultType` first. Anything scored so
/// far stays on the doc as it was.
Map<String, dynamic> noResultFields(String? reason) => {
  'result': MatchResult.tie.name,
  'resultType': ResultType.noResult,
  'resultText': noResultText(reason),
  'status': MatchStatus.completed.name,
};

/// Fields to write for a walkover won by [winner] ('A' | 'B').
Map<String, dynamic> walkoverFields(
  String winner,
  String winnerName,
  String? reason,
) => {
  'result': winner == 'A' ? MatchResult.teamA.name : MatchResult.teamB.name,
  'resultType': ResultType.walkover,
  'resultText': walkoverText(winnerName, reason),
  'status': MatchStatus.completed.name,
};
