/// Computed standings row. Never persisted — always derived from league matches.
class StandingRow {
  final String teamId;
  final String teamName;
  int played = 0;
  int won = 0;
  int tied = 0;
  int lost = 0;
  int points = 0;
  // Sum of this team's own game score across all their matches (e.g. 21+18+15...).
  // Used as the tiebreaker when two teams are level on points, before falling
  // back to a manual admin decision.
  int pointsScored = 0;
  int? rank;
  bool tiedWithAnother = false;

  StandingRow({required this.teamId, required this.teamName});
}
