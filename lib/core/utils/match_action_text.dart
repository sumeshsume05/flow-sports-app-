import '../../models/match.dart';

/// Plain-words text for the confirmation windows on the badminton match
/// screen: what Start Match / Reset to Upcoming do, and what saving a result
/// will change. Pure, so the wording is tested.

class ActionText {
  final String title;
  final String message;
  final List<String> bullets;
  final String confirmLabel;

  const ActionText(this.title, this.message, this.bullets, this.confirmLabel);
}

/// Text for moving [match] to [target] (live or upcoming) from its current
/// status. Null when nothing changes.
ActionText? statusChangeText(Match match, MatchStatus target) {
  if (match.status == target || target == MatchStatus.completed) return null;
  final names = '${match.teamA.name ?? 'TBD'} vs ${match.teamB.name ?? 'TBD'}';
  final wasCompleted = match.status == MatchStatus.completed;
  final isKnockout = match.stage == MatchStage.knockout;
  final bullets = <String>[
    if (wasCompleted) 'Its saved result is removed, so it stops counting in the standings and the podium. The '
        'scores stay in the boxes — saving the result again brings it back.',
    if (wasCompleted && isKnockout)
      'The teams this result moved into later rounds are cleared (it is refused if a later round has already started).',
  ];

  if (target == MatchStatus.live) {
    return ActionText(
      wasCompleted ? 'Restart a finished match?' : 'Start this match?',
      wasCompleted
          ? '$names was finished. It goes back to LIVE for every viewer.'
          : '$names shows as LIVE for every viewer, and the live score buttons appear.',
      bullets,
      wasCompleted ? 'Restart match' : 'Start match',
    );
  }
  // target == upcoming
  return ActionText(
    'Reset to Upcoming?',
    match.status == MatchStatus.live
        ? '$names stops being LIVE and goes back to the upcoming list.'
        : '$names goes back to the upcoming list.',
    bullets,
    'Reset to Upcoming',
  );
}

/// What saving [scoreA]–[scoreB] will do, one sentence each. [advances] are
/// the labels of later knockout matches that will receive a team from this
/// result; [previous] is the result already saved (replaced by this one).
List<String> resultSummaryLines({
  required Match match,
  required int scoreA,
  required int scoreB,
  List<String> advances = const [],
}) {
  final a = match.teamA.name ?? 'TBD';
  final b = match.teamB.name ?? 'TBD';
  final result = Match.computeResult(scoreA, scoreB)!;
  final lines = <String>[];

  switch (result) {
    case MatchResult.teamA:
      lines.add('$a beat $b, $scoreA–$scoreB.');
    case MatchResult.teamB:
      lines.add('$b beat $a, $scoreB–$scoreA.');
    case MatchResult.tie:
      lines.add('$a and $b tie, $scoreA–$scoreB.');
  }

  if (match.stage == MatchStage.league || match.stage == MatchStage.tiebreaker) {
    lines.add(switch (result) {
      MatchResult.teamA => '$a gets 2 standings points, $b gets 0.',
      MatchResult.teamB => '$b gets 2 standings points, $a gets 0.',
      MatchResult.tie => 'Each team gets 1 standings point.',
    });
  } else if (match.stage == MatchStage.knockout && advances.isNotEmpty) {
    lines.add('Teams move on to: ${advances.join(', ')}.');
  }

  if (match.hasFinalResult) {
    final old = match.result!;
    final was = '${match.scoreA ?? 0}–${match.scoreB ?? 0}';
    if (old != result) {
      lines.add('This REPLACES the saved result ($was) and changes the winner.');
    } else if (match.scoreA != scoreA || match.scoreB != scoreB) {
      lines.add('This replaces the saved score ($was).');
    }
  }
  lines.add('Viewers see it at once.');
  return lines;
}

/// How many teams qualify out of a flat league table, read from the knockout
/// bracket that exists: the highest seed any knockout slot refers to (2, 3 or
/// 4). [fallback] when there is no bracket yet.
int qualifierCountFromBracket(List<Match> knockout, {int fallback = 4}) {
  var highest = 0;
  for (final m in knockout) {
    for (final src in [m.teamASource, m.teamBSource]) {
      if (src != null && src.type == 'seed' && src.seed != null && src.seed! > highest) {
        highest = src.seed!;
      }
    }
  }
  return highest >= 2 && highest <= 4 ? highest : fallback;
}
