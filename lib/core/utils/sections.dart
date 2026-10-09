import '../../models/match.dart';
import '../../models/team.dart';

/// A category runs a sectioned league only when *every* team has a section —
/// a half-sectioned category is treated as one flat league (the schedule
/// screen blocks generating in that mixed state). Same rule the schedule,
/// standings and bracket screens already used inline.
bool isSectionedCategory(List<Team> teams) =>
    teams.isNotEmpty && teams.every((t) => t.section != null);

/// The league section a match counts toward. Normally that's the match's own
/// `section`; a league match saved without one (e.g. a manually added match
/// from before sections were enforced) is attributed to the section both of
/// its teams belong to, so it is no longer silently ignored. Null when the
/// match can't be placed in any single section (teams in different sections,
/// or an unsectioned category).
String? effectiveLeagueSection(Match m, Map<String, Team> teamsById) {
  if (m.section != null) return m.section;
  final a = teamsById[m.teamA.teamId];
  final b = teamsById[m.teamB.teamId];
  if (a == null || b == null || a.section == null) return null;
  return a.section == b.section ? a.section : null;
}

/// The league matches that belong in [section]'s table.
List<Match> leagueMatchesForSection(List<Match> league, List<Team> teams, String section) {
  final byId = {for (final t in teams) t.id: t};
  return [for (final m in league) if (effectiveLeagueSection(m, byId) == section) m];
}
