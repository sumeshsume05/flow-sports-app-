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

  // Cricket only (left null/0 for every other sport).
  /// Net run rate, shown next to the points.
  double? nrr;
  int noResult = 0;

  /// Rows with the same key are dead level. Null = use the sport's own
  /// "same points and same points scored" test (badminton). Cricket sets it,
  /// because its tie test is points, wins and NRR (after head-to-head).
  String? tieKey;

  /// Dead level with [other] — the tie that has to be settled by the admin
  /// (a tie-breaker match) rather than guessed.
  bool isLevelWith(StandingRow other) => tieKey != null || other.tieKey != null
      ? tieKey == other.tieKey
      : points == other.points && pointsScored == other.pointsScored;

  StandingRow({required this.teamId, required this.teamName});
}
