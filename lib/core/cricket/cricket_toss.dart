/// Who won the toss and what they chose. [winner] and the sides it names are
/// the match's 'A' / 'B' (matching `Match.teamA` / `teamB`).
class CricketToss {
  final String winner; // 'A' | 'B'
  final String elected; // 'bat' | 'bowl'

  const CricketToss({required this.winner, required this.elected});

  String get battingFirstSide => elected == 'bat' ? winner : (winner == 'A' ? 'B' : 'A');

  Map<String, dynamic> toMap() => {'winner': winner, 'elected': elected};

  static CricketToss? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final w = map['winner'];
    final e = map['elected'];
    if ((w != 'A' && w != 'B') || (e != 'bat' && e != 'bowl')) return null;
    return CricketToss(winner: w as String, elected: e as String);
  }

  @override
  bool operator ==(Object other) =>
      other is CricketToss && other.winner == winner && other.elected == elected;

  @override
  int get hashCode => Object.hash(winner, elected);
}
