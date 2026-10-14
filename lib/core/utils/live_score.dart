/// The score after one live-score tap: [team]'s score changes by [delta],
/// never below 0 or above 999 (the other team's score is untouched).
(int, int) nextLiveScore(int scoreA, int scoreB, {required String team, required int delta}) {
  if (team == 'A') return ((scoreA + delta).clamp(0, 999), scoreB);
  return (scoreA, (scoreB + delta).clamp(0, 999));
}
