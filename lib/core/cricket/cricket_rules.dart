/// How a batter can be dismissed. Which of these a match allows is a rule
/// (e.g. tape-ball matches usually drop LBW and stumping) — see
/// [CricketRules.allowedWickets].
enum WicketKind {
  bowled,
  caught,
  lbw,
  runOut,
  stumped,
  hitWicket,
  obstructingField,
  hitBallTwice,
  handledBall,
}

extension WicketKindInfo on WicketKind {
  /// The bowler gets the wicket for these; run-outs and the "obstructing /
  /// handled / hit twice" family are not credited to the bowler.
  bool get creditsBowler => switch (this) {
        WicketKind.bowled ||
        WicketKind.caught ||
        WicketKind.lbw ||
        WicketKind.stumped ||
        WicketKind.hitWicket =>
          true,
        _ => false,
      };

  /// Only the batter facing the ball can be out this way, so a recorded
  /// `outBatterId` that isn't the striker is a scoring mistake.
  bool get strikerOnly => switch (this) {
        WicketKind.bowled ||
        WicketKind.caught ||
        WicketKind.lbw ||
        WicketKind.stumped ||
        WicketKind.hitWicket =>
          true,
        _ => false,
      };

  String get label => switch (this) {
        WicketKind.bowled => 'Bowled',
        WicketKind.caught => 'Caught',
        WicketKind.lbw => 'LBW',
        WicketKind.runOut => 'Run out',
        WicketKind.stumped => 'Stumped',
        WicketKind.hitWicket => 'Hit wicket',
        WicketKind.obstructingField => 'Obstructing the field',
        WicketKind.hitBallTwice => 'Hit the ball twice',
        WicketKind.handledBall => 'Handled the ball',
      };
}

/// On a wide only these dismissals are possible (the ball is not a legal
/// delivery to hit, so no bowled/caught/lbw).
const wicketKindsAllowedOnWide = {
  WicketKind.stumped,
  WicketKind.runOut,
  WicketKind.hitWicket,
  WicketKind.obstructingField,
  WicketKind.handledBall,
};

/// On a no-ball — and on the free hit after one — only these are possible.
const wicketKindsAllowedOnNoBall = {
  WicketKind.runOut,
  WicketKind.hitBallTwice,
  WicketKind.obstructingField,
  WicketKind.handledBall,
};

/// Every cricket rule that is "sometimes needed, sometimes not". A match
/// carries its own snapshot of these (taken from the tournament default
/// when the schedule is generated), so changing the default later never
/// rewrites a match that already has a log.
class CricketRules {
  final int overs;
  final int ballsPerOver;

  /// Players per team batting side. The scorer picks this many from the
  /// team's player list for each match.
  final int squadSize;

  /// Last batter keeps batting alone once only one partner is left, instead
  /// of the innings ending one wicket earlier (common in office cricket).
  final bool lastManStands;

  /// Null = no limit.
  final int? maxOversPerBowler;

  final int widePenalty;

  /// A wide is bowled again (doesn't use up one of the over's balls).
  final bool wideReBowl;
  final int noBallPenalty;
  final bool noBallReBowl;

  /// The ball after a no-ball is a free hit.
  final bool freeHit;
  final bool byesAllowed;
  final bool legByesAllowed;
  final Set<WicketKind> allowedWickets;

  /// What a boundary is worth — used by the scoring buttons; the replay
  /// itself only sees the `runs` the scorer entered.
  final int boundaryFour;
  final int boundarySix;

  final int pointsWin;
  final int pointsTie;
  final int pointsNoResult;

  /// A tied knockout match is settled by a super over.
  final bool superOverOnKnockoutTie;

  const CricketRules({
    this.overs = 6,
    this.ballsPerOver = 6,
    this.squadSize = 8,
    this.lastManStands = true,
    this.maxOversPerBowler = 2,
    this.widePenalty = 1,
    this.wideReBowl = true,
    this.noBallPenalty = 1,
    this.noBallReBowl = true,
    this.freeHit = true,
    this.byesAllowed = true,
    this.legByesAllowed = false,
    this.allowedWickets = tapeBallWickets,
    this.boundaryFour = 4,
    this.boundarySix = 6,
    this.pointsWin = 2,
    this.pointsTie = 1,
    this.pointsNoResult = 1,
    this.superOverOnKnockoutTie = true,
  });

  /// Office / tape-ball default: short innings, no LBW, no stumping, leg
  /// byes off, free hit on, last-man-stands on.
  const CricketRules.tapeBall() : this();

  /// Full hard-ball T20 rules.
  const CricketRules.t20()
      : this(
          overs: 20,
          squadSize: 11,
          lastManStands: false,
          maxOversPerBowler: 4,
          legByesAllowed: true,
          allowedWickets: allWickets,
        );

  static const allWickets = {
    WicketKind.bowled,
    WicketKind.caught,
    WicketKind.lbw,
    WicketKind.runOut,
    WicketKind.stumped,
    WicketKind.hitWicket,
    WicketKind.obstructingField,
    WicketKind.hitBallTwice,
    WicketKind.handledBall,
  };

  static const tapeBallWickets = {
    WicketKind.bowled,
    WicketKind.caught,
    WicketKind.runOut,
    WicketKind.hitWicket,
    WicketKind.obstructingField,
    WicketKind.hitBallTwice,
    WicketKind.handledBall,
  };

  int get maxBalls => overs * ballsPerOver;

  /// Wickets that end an innings for a batting side of [lineupSize]: one
  /// fewer than the side normally (the last batter has no partner), or the
  /// full side when last-man-stands lets the final batter bat alone.
  int maxWickets(int lineupSize) => lastManStands ? lineupSize : lineupSize - 1;

  CricketRules copyWith({
    int? overs,
    int? ballsPerOver,
    int? squadSize,
    bool? lastManStands,
    int? maxOversPerBowler,
    bool clearMaxOversPerBowler = false,
    int? widePenalty,
    bool? wideReBowl,
    int? noBallPenalty,
    bool? noBallReBowl,
    bool? freeHit,
    bool? byesAllowed,
    bool? legByesAllowed,
    Set<WicketKind>? allowedWickets,
    int? boundaryFour,
    int? boundarySix,
    int? pointsWin,
    int? pointsTie,
    int? pointsNoResult,
    bool? superOverOnKnockoutTie,
  }) =>
      CricketRules(
        overs: overs ?? this.overs,
        ballsPerOver: ballsPerOver ?? this.ballsPerOver,
        squadSize: squadSize ?? this.squadSize,
        lastManStands: lastManStands ?? this.lastManStands,
        maxOversPerBowler:
            clearMaxOversPerBowler ? null : (maxOversPerBowler ?? this.maxOversPerBowler),
        widePenalty: widePenalty ?? this.widePenalty,
        wideReBowl: wideReBowl ?? this.wideReBowl,
        noBallPenalty: noBallPenalty ?? this.noBallPenalty,
        noBallReBowl: noBallReBowl ?? this.noBallReBowl,
        freeHit: freeHit ?? this.freeHit,
        byesAllowed: byesAllowed ?? this.byesAllowed,
        legByesAllowed: legByesAllowed ?? this.legByesAllowed,
        allowedWickets: allowedWickets ?? this.allowedWickets,
        boundaryFour: boundaryFour ?? this.boundaryFour,
        boundarySix: boundarySix ?? this.boundarySix,
        pointsWin: pointsWin ?? this.pointsWin,
        pointsTie: pointsTie ?? this.pointsTie,
        pointsNoResult: pointsNoResult ?? this.pointsNoResult,
        superOverOnKnockoutTie: superOverOnKnockoutTie ?? this.superOverOnKnockoutTie,
      );

  Map<String, dynamic> toMap() => {
        'overs': overs,
        'ballsPerOver': ballsPerOver,
        'squadSize': squadSize,
        'lastManStands': lastManStands,
        'maxOversPerBowler': maxOversPerBowler,
        'widePenalty': widePenalty,
        'wideReBowl': wideReBowl,
        'noBallPenalty': noBallPenalty,
        'noBallReBowl': noBallReBowl,
        'freeHit': freeHit,
        'byesAllowed': byesAllowed,
        'legByesAllowed': legByesAllowed,
        'allowedWickets': allowedWickets.map((k) => k.name).toList()..sort(),
        'boundaryFour': boundaryFour,
        'boundarySix': boundarySix,
        'pointsWin': pointsWin,
        'pointsTie': pointsTie,
        'pointsNoResult': pointsNoResult,
        'superOverOnKnockoutTie': superOverOnKnockoutTie,
      };

  /// Missing keys fall back to the tape-ball default, so a rules map written
  /// by an older app version still loads.
  factory CricketRules.fromMap(Map<String, dynamic>? map) {
    const d = CricketRules();
    if (map == null) return d;
    final wickets = map['allowedWickets'];
    return CricketRules(
      overs: map['overs'] as int? ?? d.overs,
      ballsPerOver: map['ballsPerOver'] as int? ?? d.ballsPerOver,
      squadSize: map['squadSize'] as int? ?? d.squadSize,
      lastManStands: map['lastManStands'] as bool? ?? d.lastManStands,
      maxOversPerBowler:
          map.containsKey('maxOversPerBowler') ? map['maxOversPerBowler'] as int? : d.maxOversPerBowler,
      widePenalty: map['widePenalty'] as int? ?? d.widePenalty,
      wideReBowl: map['wideReBowl'] as bool? ?? d.wideReBowl,
      noBallPenalty: map['noBallPenalty'] as int? ?? d.noBallPenalty,
      noBallReBowl: map['noBallReBowl'] as bool? ?? d.noBallReBowl,
      freeHit: map['freeHit'] as bool? ?? d.freeHit,
      byesAllowed: map['byesAllowed'] as bool? ?? d.byesAllowed,
      legByesAllowed: map['legByesAllowed'] as bool? ?? d.legByesAllowed,
      allowedWickets: wickets is List
          ? {
              for (final n in wickets)
                for (final k in WicketKind.values)
                  if (k.name == n) k,
            }
          : d.allowedWickets,
      boundaryFour: map['boundaryFour'] as int? ?? d.boundaryFour,
      boundarySix: map['boundarySix'] as int? ?? d.boundarySix,
      pointsWin: map['pointsWin'] as int? ?? d.pointsWin,
      pointsTie: map['pointsTie'] as int? ?? d.pointsTie,
      pointsNoResult: map['pointsNoResult'] as int? ?? d.pointsNoResult,
      superOverOnKnockoutTie: map['superOverOnKnockoutTie'] as bool? ?? d.superOverOnKnockoutTie,
    );
  }
}
