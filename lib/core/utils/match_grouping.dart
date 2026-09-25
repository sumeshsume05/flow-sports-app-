import '../../models/match.dart';

/// One labeled group of matches for display — e.g. "League", "Tie-Breaker —
/// Round 2", "Knockout" — so a long match list reads as distinct rounds
/// instead of one flat, ambiguous list.
class MatchSection {
  final String title;
  final List<Match> matches;

  MatchSection({required this.title, required this.matches});

  bool get isCompleted =>
      matches.isNotEmpty && matches.every((m) => m.status == MatchStatus.completed);
}

/// Groups [matches] into sections, most-advanced stage first — Knockout,
/// then any Tie-Breaker rounds (latest round first, since that's the one
/// currently in play), then League last. Within a section, matches keep
/// their natural match-number order.
List<MatchSection> groupMatchesForDisplay(List<Match> matches) {
  final sections = <MatchSection>[];

  final knockout = matches.where((m) => m.stage == MatchStage.knockout).toList()
    ..sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
  if (knockout.isNotEmpty) {
    sections.add(MatchSection(title: 'Knockout (Round 2)', matches: knockout));
  }

  final tiebreakers = matches.where((m) => m.stage == MatchStage.tiebreaker).toList();
  final rounds = tiebreakers.map((m) => m.tiebreakerRound ?? 1).toSet().toList()
    ..sort((a, b) => b.compareTo(a));
  for (final round in rounds) {
    final roundMatches = tiebreakers.where((m) => (m.tiebreakerRound ?? 1) == round).toList()
      ..sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
    sections.add(MatchSection(
      title: round > 1 ? 'Tie-Breaker — Round $round' : 'Tie-Breaker',
      matches: roundMatches,
    ));
  }

  final league = matches.where((m) => m.stage == MatchStage.league).toList()
    ..sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
  if (league.isNotEmpty) {
    sections.add(MatchSection(title: 'League (Round 1)', matches: league));
  }

  return sections;
}
