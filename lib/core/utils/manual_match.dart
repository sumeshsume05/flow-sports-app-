import '../../models/match.dart';
import '../../models/team.dart';
import 'sections.dart';

/// Why an admin adds a match by hand.
///  * [league] — a real tournament match: it counts in the points table and
///    feeds qualification, exactly like a generated league match.
///  * [friendly] — a practice/exhibition match: shown in the lists but never
///    counted in standings, qualification or the bracket.
enum ManualMatchType { league, friendly }

/// Result of validating a manual match before it is created.
class ManualMatchCheck {
  /// Blocks creation when non-null.
  final String? error;

  /// A league match between the same two teams already exists — the admin
  /// should confirm they really want a second one. Never blocks.
  final Match? duplicateOf;

  /// The section a league match belongs to (null for friendlies and for
  /// unsectioned categories).
  final String? section;

  const ManualMatchCheck({this.error, this.duplicateOf, this.section});

  bool get ok => error == null;
}

ManualMatchCheck checkManualMatch({
  required ManualMatchType type,
  required Team? teamA,
  required Team? teamB,
  required List<Team> teams,
  required List<Match> existing,
}) {
  if (teamA == null || teamB == null || teamA.id == teamB.id) {
    return const ManualMatchCheck(error: 'Choose two different teams.');
  }
  if (type == ManualMatchType.friendly) return const ManualMatchCheck();

  String? section;
  if (isSectionedCategory(teams)) {
    if (teamA.section != teamB.section) {
      return ManualMatchCheck(
        error: '${teamA.name} is in Section ${teamA.section} but ${teamB.name} is in '
            'Section ${teamB.section}. A league match must be between teams in the same '
            'section — pick two from one section, or make it a Friendly.',
      );
    }
    section = teamA.section;
  }

  Match? duplicate;
  for (final m in existing) {
    if (m.stage != MatchStage.league) continue;
    final ids = {m.teamA.teamId, m.teamB.teamId};
    if (ids.contains(teamA.id) && ids.contains(teamB.id)) {
      duplicate = m;
      break;
    }
  }
  return ManualMatchCheck(duplicateOf: duplicate, section: section);
}

/// Builds the match to save. Numbering continues within its own stage, so
/// friendlies (F1, F2, …) never disturb the league's numbering.
Match buildManualMatch({
  required ManualMatchType type,
  required Team teamA,
  required Team teamB,
  required String label,
  required String sport,
  required String category,
  required String season,
  required List<Match> existing,
  String? section,
}) {
  final stage = type == ManualMatchType.league ? MatchStage.league : MatchStage.friendly;
  final numbers = [for (final m in existing) if (m.stage == stage) m.matchNumber];
  final next = numbers.isEmpty ? 1 : numbers.reduce((a, b) => a > b ? a : b) + 1;
  final isLeague = type == ManualMatchType.league;
  final trimmed = label.trim();
  final fallback = isLeague ? 'Extra Match' : 'Friendly';
  return Match(
    id: '',
    sport: sport,
    category: category,
    season: season,
    stage: stage,
    matchNumber: next,
    label: trimmed.isEmpty ? fallback : trimmed,
    matchCode: isLeague ? (section == null ? 'L$next' : '$section-L$next') : 'F$next',
    section: isLeague ? section : null,
    teamA: TeamRef(teamId: teamA.id, name: teamA.name),
    teamB: TeamRef(teamId: teamB.id, name: teamB.name),
    status: MatchStatus.upcoming,
    notifyTopic: '${sport}_$category',
  );
}
