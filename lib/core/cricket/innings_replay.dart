import 'cricket_event.dart';
import 'cricket_rules.dart';

/// Why a stored input no longer makes sense after the log changed. The
/// replay never rewrites or drops the offending event — it keeps it, applies
/// no state change for the invalid piece, and reports a [ReviewFlag] so the
/// admin can fix the ball or explicitly accept it.
enum FlagCode {
  /// Recorded dismissed batter isn't one of the two at the crease.
  outBatterNotAtCrease,

  /// e.g. a bowled/caught/lbw/stumped/hit-wicket recorded against the
  /// non-striker.
  outBatterInvalidForKind,

  /// Incoming batter isn't in the lineup, is already out, or is already
  /// batting.
  newBatterInvalid,

  /// A wicket fell, batters are still available, but none was chosen.
  missingNewBatter,

  /// Dismissal kind disabled in the rules, impossible on this delivery
  /// (e.g. bowled on a wide) or on a free hit, or recorded on a dead ball.
  wicketKindNotAllowed,
  bowlerChangedMidOver,
  bowlerConsecutiveOvers,
  bowlerOverLimit,
  bowlerNotInLineup,

  /// The innings already ended (all out / overs done / target reached /
  /// declared) before this event.
  ballAfterInningsEnd,

  /// Byes / leg byes recorded while the rules disallow them.
  runTypeNotAllowed,

  /// Negative runs, or bat/bye runs that make no sense for the delivery.
  invalidRuns,

  /// There is no batter at the crease to attribute this ball to (an earlier
  /// invalid input left the slot empty).
  noBatterAtCrease,
  retireBatterNotAtCrease,
}

class ReviewFlag {
  final int seq;
  final FlagCode code;
  final String message;

  /// The admin chose "accept as is" for this exact flag.
  final bool acknowledged;

  const ReviewFlag(this.seq, this.code, this.message, {this.acknowledged = false});

  @override
  String toString() => 'ReviewFlag(#$seq ${code.name}${acknowledged ? ' ack' : ''}: $message)';
}

enum InningsEnd { oversDone, allOut, targetReached, declared }

enum BatterStatus { yetToBat, batting, out, retired }

class Dismissal {
  final WicketKind kind;
  final String? bowlerId; // only when the bowler is credited
  final String? fielderId;

  const Dismissal(this.kind, {this.bowlerId, this.fielderId});
}

class BatterStats {
  final String id;
  BatterStatus status;
  int runs = 0;
  int balls = 0;
  int fours = 0;
  int sixes = 0;
  Dismissal? dismissal;

  BatterStats(this.id, this.status);

  double get strikeRate => balls == 0 ? 0 : runs * 100 / balls;
}

class BowlerStats {
  final String id;
  int legalBalls = 0;
  int runsConceded = 0;
  int wickets = 0;
  int wides = 0;
  int noBalls = 0;
  int maidens = 0;
  final int ballsPerOver;

  BowlerStats(this.id, this.ballsPerOver);

  String get oversText => '${legalBalls ~/ ballsPerOver}.${legalBalls % ballsPerOver}';

  double get economy => legalBalls == 0 ? 0 : runsConceded * ballsPerOver / legalBalls;
}

class Extras {
  int wides = 0;
  int noBalls = 0;
  int byes = 0;
  int legByes = 0;

  int get total => wides + noBalls + byes + legByes;
}

class FallOfWicket {
  final int wicketNumber;
  final int teamRuns;
  final String batterId;

  /// Overs.balls at the time, e.g. "3.2".
  final String oversText;

  const FallOfWicket(this.wicketNumber, this.teamRuns, this.batterId, this.oversText);
}

class Partnership {
  final String batterA;
  final String? batterB;
  int runs = 0;
  int balls = 0;

  Partnership(this.batterA, this.batterB);
}

/// Everything derived about one logged delivery.
class BallRecord {
  final int seq;

  /// 0-based over number the delivery belongs to.
  final int over;

  /// For a counted ball: its 1-based place in the over. For a wide/no-ball
  /// that doesn't count: how many balls of the over were already bowled.
  final int ballInOver;
  final String? strikerId;
  final String? nonStrikerId;
  final String? bowlerId;
  final Delivery delivery;

  /// Uses up one of the over's balls.
  final bool countsAsBall;
  final bool freeHit;
  final int teamRuns;
  final int batRuns;
  final int completedRuns;
  final WicketKind? wicketKind;
  final String? outBatterId;
  final String? fielderId;

  /// Short chip text for "this over": `.` `1` `4` `W` `Wd` `Wd+4` `Nb+1` `2b`.
  final String token;

  const BallRecord({
    required this.seq,
    required this.over,
    required this.ballInOver,
    required this.strikerId,
    required this.nonStrikerId,
    required this.bowlerId,
    required this.delivery,
    required this.countsAsBall,
    required this.freeHit,
    required this.teamRuns,
    required this.batRuns,
    required this.completedRuns,
    required this.wicketKind,
    required this.outBatterId,
    required this.fielderId,
    required this.token,
  });

  bool get isWicket => wicketKind != null;
}

class OverSummary {
  final int over;
  final String? bowlerId;
  int runs = 0; // charged to the bowler
  int wickets = 0;
  bool complete = false;
  bool maiden = false;
  final List<BallRecord> balls = [];

  OverSummary(this.over, this.bowlerId);
}

/// Who is playing and the state at the start of an innings.
class InningsSetup {
  final List<String> battingLineup;
  final List<String> bowlingLineup;
  final String strikerId;
  final String nonStrikerId;

  /// Runs needed to win (chasing side only): first innings total + 1.
  final int? target;

  /// Revised overs (e.g. a shortened chase); defaults to `rules.overs`.
  final int? maxOvers;

  const InningsSetup({
    required this.battingLineup,
    required this.bowlingLineup,
    required this.strikerId,
    required this.nonStrikerId,
    this.target,
    this.maxOvers,
  });
}

class InningsResult {
  final CricketRules rules;
  final InningsSetup setup;
  final int runs;
  final int wickets;
  final int legalBalls;
  final Extras extras;
  final InningsEnd? endReason;
  final String? strikerId;
  final String? nonStrikerId;
  final String? currentBowlerId;

  /// The *next* delivery is a free hit.
  final bool freeHitNext;
  final Map<String, BatterStats> batters;
  final Map<String, BowlerStats> bowlers;
  final List<FallOfWicket> fallOfWickets;
  final List<Partnership> partnerships;
  final List<BallRecord> balls;
  final List<OverSummary> overs;
  final List<ReviewFlag> flags;
  final int maxWickets;
  final int maxBalls;

  InningsResult({
    required this.rules,
    required this.setup,
    required this.runs,
    required this.wickets,
    required this.legalBalls,
    required this.extras,
    required this.endReason,
    required this.strikerId,
    required this.nonStrikerId,
    required this.currentBowlerId,
    required this.freeHitNext,
    required this.batters,
    required this.bowlers,
    required this.fallOfWickets,
    required this.partnerships,
    required this.balls,
    required this.overs,
    required this.flags,
    required this.maxWickets,
    required this.maxBalls,
  });

  bool get isEnded => endReason != null;
  int get ballsLeft => (maxBalls - legalBalls).clamp(0, maxBalls);

  String get oversText => '${legalBalls ~/ rules.ballsPerOver}.${legalBalls % rules.ballsPerOver}';

  /// "45/2"
  String get scoreText => '$runs/$wickets';

  double get runRate => legalBalls == 0 ? 0 : runs * rules.ballsPerOver / legalBalls;

  /// Chase helpers — null when this innings has no target.
  int? get runsNeeded => setup.target == null ? null : (setup.target! - runs).clamp(0, 1 << 30);

  double? get requiredRunRate {
    final needed = runsNeeded;
    if (needed == null || ballsLeft == 0) return null;
    return needed * rules.ballsPerOver / ballsLeft;
  }

  List<ReviewFlag> get blockingFlags => flags.where((f) => !f.acknowledged).toList();
  bool get needsReview => blockingFlags.isNotEmpty;

  /// Flags for one event, for the ⚠ chip on a ball in the over list.
  List<ReviewFlag> flagsFor(int seq) => flags.where((f) => f.seq == seq).toList();
}

/// Replays an innings' event log from ball 1 and derives *all* state:
/// striker/non-striker, legal-ball count, over/ball numbers, free-hit state,
/// totals, wickets and per-player statistics. Order of operations for one ball:
///  1. apply runs/extras to team, batter, bowler
///  2. swap ends if the batters physically completed an odd number of runs
///  3. on a dismissal, place the incoming batter ([Wicket.newBatterEnd])
///  4. last counted ball of an over → swap ends again
///  5. update free-hit state for the next ball
///  6. check for the end of the innings
InningsResult replayInnings(
  CricketRules rules,
  InningsSetup setup,
  List<CricketEvent> events,
) {
  final replayer = _Replayer(rules, setup);
  final ordered = [...events]..sort((a, b) => a.seq.compareTo(b.seq));
  for (final e in ordered) {
    replayer.apply(e);
  }
  return replayer.finish();
}

class _OverInProgress {
  final OverSummary summary;
  final String? bowlerId;
  int countedBalls = 0;
  bool hadWideOrNoBall = false;
  bool bowlerChanged = false;

  _OverInProgress(this.summary, this.bowlerId);
}

class _Replayer {
  final CricketRules rules;
  final InningsSetup setup;
  late final int maxWickets;
  late final int maxBalls;

  final batters = <String, BatterStats>{};
  final bowlers = <String, BowlerStats>{};
  final extras = Extras();
  final fow = <FallOfWicket>[];
  final partnerships = <Partnership>[];
  final records = <BallRecord>[];
  final overs = <OverSummary>[];
  final flags = <ReviewFlag>[];
  final bowlerOversStarted = <String, int>{};

  String? striker;
  String? nonStriker;
  int runs = 0;
  int wickets = 0;
  int legalBalls = 0;
  bool freeHit = false;
  InningsEnd? ended;
  String? lastBowler;
  String? lastOverBowler;
  _OverInProgress? over;
  Partnership? partnership;
  CricketEvent? current;

  _Replayer(this.rules, this.setup) {
    if (!setup.battingLineup.contains(setup.strikerId) ||
        !setup.battingLineup.contains(setup.nonStrikerId) ||
        setup.strikerId == setup.nonStrikerId) {
      throw ArgumentError('Openers must be two different players from the batting lineup');
    }
    maxWickets = rules.maxWickets(setup.battingLineup.length);
    maxBalls = (setup.maxOvers ?? rules.overs) * rules.ballsPerOver;
    for (final id in setup.battingLineup) {
      batters[id] = BatterStats(id, BatterStatus.yetToBat);
    }
    striker = setup.strikerId;
    nonStriker = setup.nonStrikerId;
    batters[striker!]!.status = BatterStatus.batting;
    batters[nonStriker!]!.status = BatterStatus.batting;
    _startPartnership();
  }

  // ---- helpers ----------------------------------------------------------

  void _flag(FlagCode code, String message) {
    final e = current!;
    flags.add(ReviewFlag(e.seq, code, message,
        acknowledged: e.acknowledgedFlags.contains(code.name)));
  }

  void _swapEnds() {
    if (striker != null && nonStriker != null) {
      final t = striker;
      striker = nonStriker;
      nonStriker = t;
    }
  }

  void _startPartnership() {
    if (striker == null) {
      partnership = null;
      return;
    }
    partnership = Partnership(striker!, nonStriker);
    partnerships.add(partnership!);
  }

  BowlerStats _bowler(String id) => bowlers.putIfAbsent(id, () => BowlerStats(id, rules.ballsPerOver));

  bool _batterAvailable(String id) {
    final b = batters[id];
    if (b == null) return false;
    if (b.status != BatterStatus.yetToBat && b.status != BatterStatus.retired) return false;
    return id != striker && id != nonStriker;
  }

  bool get _anyBatterAvailable => batters.keys.any(_batterAvailable);

  /// Validates an incoming batter id; returns it if usable, else null (and
  /// flags it when one was given).
  String? _validNewBatter(String? id) {
    if (id == null) return null;
    if (!_batterAvailable(id)) {
      _flag(FlagCode.newBatterInvalid,
          '$id can\'t come in: not in the lineup, already out, or already batting.');
      return null;
    }
    return id;
  }

  // ---- event dispatch ---------------------------------------------------

  void apply(CricketEvent e) {
    current = e;
    if (ended != null) {
      if (e.kind != EventKind.endInnings) {
        _flag(FlagCode.ballAfterInningsEnd,
            'The innings had already ended (${ended!.name}) before this entry.');
      }
      return;
    }
    switch (e.kind) {
      case EventKind.swapStrike:
        // Same pair, so same partnership — only who faces changes.
        _swapEnds();
      case EventKind.endInnings:
        ended = InningsEnd.declared;
      case EventKind.retire:
        _retire(e);
      case EventKind.ball:
        _ball(e);
    }
  }

  void _retire(CricketEvent e) {
    final id = e.retiredBatterId;
    if (id == null || (id != striker && id != nonStriker)) {
      _flag(FlagCode.retireBatterNotAtCrease, 'The retiring batter isn\'t at the crease.');
      return;
    }
    final wasStriker = id == striker;
    batters[id]!.status = BatterStatus.retired;
    final survivor = wasStriker ? nonStriker : striker;
    final nb = _validNewBatter(e.newBatterId);
    if (nb == null && e.newBatterId == null && _anyBatterAvailable) {
      _flag(FlagCode.missingNewBatter, 'No incoming batter was chosen.');
    }
    if (nb != null) batters[nb]!.status = BatterStatus.batting;
    if (wasStriker) {
      striker = nb ?? survivor;
      nonStriker = nb == null ? null : survivor;
    } else {
      striker = survivor;
      nonStriker = nb;
    }
    _startPartnership();
  }

  // ---- one delivery -----------------------------------------------------

  void _ball(CricketEvent e) {
    final bowlerId = e.bowlerId;
    if (bowlerId == null || !setup.bowlingLineup.contains(bowlerId)) {
      _flag(FlagCode.bowlerNotInLineup, 'Bowler ${bowlerId ?? '(none)'} isn\'t in the bowling lineup.');
    }
    final bowlerKey = bowlerId ?? '';

    final delivery = e.delivery;
    final isDead = delivery == Delivery.deadBall;
    final isFreeHit = freeHit;
    final countsAsBall = switch (delivery) {
      Delivery.legal => true,
      Delivery.wide => !rules.wideReBowl,
      Delivery.noBall => !rules.noBallReBowl,
      Delivery.deadBall => false,
    };

    // --- input validation (rule violations are flagged but still applied) ---
    var runsIn = e.runs;
    if (runsIn < 0) {
      _flag(FlagCode.invalidRuns, 'Runs can\'t be negative.');
      runsIn = 0;
    }
    var runType = e.runType;
    if (isDead) {
      runsIn = 0;
      runType = RunType.none;
    } else if (delivery == Delivery.wide) {
      if (runType != RunType.none) {
        _flag(FlagCode.invalidRuns, 'Wide runs are always extras; runs-off-bat/bye type ignored.');
      }
      runType = RunType.none;
    } else if (runType == RunType.none && runsIn > 0) {
      _flag(FlagCode.invalidRuns, 'Runs were entered without saying whose (bat/bye/leg bye).');
      runsIn = 0;
    }
    if (runType == RunType.bye && !rules.byesAllowed) {
      _flag(FlagCode.runTypeNotAllowed, 'Byes are switched off in this match\'s rules.');
    }
    if (runType == RunType.legBye && !rules.legByesAllowed) {
      _flag(FlagCode.runTypeNotAllowed, 'Leg byes are switched off in this match\'s rules.');
    }

    final penalty = switch (delivery) {
      Delivery.wide => rules.widePenalty,
      Delivery.noBall => rules.noBallPenalty,
      _ => 0,
    };
    final teamRuns = penalty + runsIn;
    final completed = isDead ? 0 : (e.completedRunsOverride ?? (e.boundary != Boundary.none ? 0 : runsIn));
    final batRuns = runType == RunType.bat ? runsIn : 0;

    // --- over bookkeeping (dead balls sit outside any over) ---
    final ballsBefore = legalBalls;
    final overIndex = ballsBefore ~/ rules.ballsPerOver;
    final startStriker = striker;
    final startNonStriker = nonStriker;
    if (!isDead) _trackOver(e, bowlerKey, overIndex);

    // 1. runs / extras / stats
    if (!isDead) {
      runs += teamRuns;
      partnership?.runs += teamRuns;
      switch (delivery) {
        case Delivery.wide:
          extras.wides += penalty + runsIn;
        case Delivery.noBall:
          extras.noBalls += penalty;
        default:
          break;
      }
      if (runType == RunType.bye) extras.byes += runsIn;
      if (runType == RunType.legBye) extras.legByes += runsIn;

      final facesBall = delivery == Delivery.legal || delivery == Delivery.noBall;
      if (striker == null) {
        _flag(FlagCode.noBatterAtCrease, 'No batter at the crease to face this ball.');
      } else {
        final b = batters[striker!]!;
        if (facesBall) b.balls++;
        if (batRuns > 0 || (runType == RunType.bat && e.boundary != Boundary.none)) {
          b.runs += batRuns;
          if (e.boundary == Boundary.four) b.fours++;
          if (e.boundary == Boundary.six) b.sixes++;
        }
      }
      if (facesBall && partnership != null) partnership!.balls++;

      final bowler = _bowler(bowlerKey);
      var charged = batRuns;
      if (delivery == Delivery.wide) {
        bowler.wides += penalty + runsIn;
        charged = penalty + runsIn;
      } else if (delivery == Delivery.noBall) {
        bowler.noBalls += penalty;
        charged = penalty + batRuns;
      }
      bowler.runsConceded += charged;
      over!.summary.runs += charged;
      if (delivery == Delivery.wide || delivery == Delivery.noBall) over!.hadWideOrNoBall = true;
      if (countsAsBall) {
        bowler.legalBalls++;
        legalBalls++;
        over!.countedBalls++;
      }
    }

    // 2. strike rotation from physically completed runs
    if (!isDead && completed.isOdd) _swapEnds();

    // 3. dismissal
    WicketKind? wicketKind;
    String? outBatterId;
    String? fielderId;
    if (e.wicket != null) {
      final applied = _applyWicket(e, e.wicket!, delivery, isFreeHit, isDead, startStriker, bowlerKey);
      if (applied) {
        wicketKind = e.wicket!.kind;
        outBatterId = e.wicket!.outBatterId;
        fielderId = e.wicket!.fielderId;
        over?.summary.wickets++;
      }
    }

    // 4. end of over
    var overCompleted = false;
    if (!isDead && countsAsBall && legalBalls % rules.ballsPerOver == 0) {
      overCompleted = true;
      _swapEnds();
    }

    final record = BallRecord(
      seq: e.seq,
      over: overIndex,
      ballInOver: countsAsBall ? (ballsBefore % rules.ballsPerOver) + 1 : ballsBefore % rules.ballsPerOver,
      strikerId: startStriker,
      nonStrikerId: startNonStriker,
      bowlerId: bowlerId,
      delivery: delivery,
      countsAsBall: countsAsBall,
      freeHit: isFreeHit,
      teamRuns: isDead ? 0 : teamRuns,
      batRuns: isDead ? 0 : batRuns,
      completedRuns: completed,
      wicketKind: wicketKind,
      outBatterId: outBatterId,
      fielderId: fielderId,
      token: _token(delivery, runType, runsIn, wicketKind != null),
    );
    records.add(record);
    if (!isDead) over!.summary.balls.add(record);
    lastBowler = bowlerId ?? lastBowler;

    if (overCompleted) _closeOver();

    // 5. free-hit state for the next ball (a dead ball neither starts nor ends it)
    if (!isDead) {
      freeHit = (delivery == Delivery.noBall && rules.freeHit) || (isFreeHit && !countsAsBall);
    }

    // 6. innings end (reaching the target wins even if it also ends the side)
    if (setup.target != null && runs >= setup.target!) {
      ended = InningsEnd.targetReached;
    } else if (wickets >= maxWickets) {
      ended = InningsEnd.allOut;
    } else if (legalBalls >= maxBalls) {
      ended = InningsEnd.oversDone;
    }
  }

  void _trackOver(CricketEvent e, String bowlerKey, int overIndex) {
    if (over == null) {
      final summary = OverSummary(overIndex, e.bowlerId);
      overs.add(summary);
      over = _OverInProgress(summary, e.bowlerId);
      final b = e.bowlerId;
      if (b != null) {
        final started = (bowlerOversStarted[b] ?? 0) + 1;
        bowlerOversStarted[b] = started;
        if (lastOverBowler == b) {
          _flag(FlagCode.bowlerConsecutiveOvers, '$b would bowl two overs in a row.');
        }
        final limit = rules.maxOversPerBowler;
        if (limit != null && started > limit) {
          _flag(FlagCode.bowlerOverLimit, '$b is past the $limit-over limit.');
        }
      }
    } else if (over!.bowlerId != e.bowlerId) {
      over!.bowlerChanged = true;
      _flag(FlagCode.bowlerChangedMidOver, 'The bowler changed part-way through the over.');
    }
  }

  void _closeOver() {
    final o = over!;
    o.summary.complete = true;
    o.summary.maiden = !o.bowlerChanged && !o.hadWideOrNoBall && o.summary.runs == 0;
    if (o.summary.maiden && o.bowlerId != null) _bowler(o.bowlerId!).maidens++;
    lastOverBowler = o.bowlerId;
    over = null;
  }

  /// Returns whether the dismissal was applied (an invalid one is flagged and
  /// changes nothing).
  bool _applyWicket(
    CricketEvent e,
    Wicket w,
    Delivery delivery,
    bool isFreeHit,
    bool isDead,
    String? startStriker,
    String bowlerKey,
  ) {
    String? reject;
    if (isDead) {
      reject = 'A dead ball can\'t take a wicket.';
    } else if (!rules.allowedWickets.contains(w.kind)) {
      reject = '${w.kind.label} is switched off in this match\'s rules.';
    } else if (delivery == Delivery.wide && !wicketKindsAllowedOnWide.contains(w.kind)) {
      reject = '${w.kind.label} isn\'t possible on a wide.';
    } else if ((delivery == Delivery.noBall || isFreeHit) &&
        !wicketKindsAllowedOnNoBall.contains(w.kind)) {
      reject = '${w.kind.label} isn\'t possible on a no-ball / free hit.';
    }
    if (reject != null) {
      _flag(FlagCode.wicketKindNotAllowed, reject);
      return false;
    }
    final out = w.outBatterId;
    if (out != striker && out != nonStriker) {
      _flag(FlagCode.outBatterNotAtCrease, '$out isn\'t at the crease, so can\'t be out here.');
      return false;
    }
    if (w.kind.strikerOnly && out != startStriker) {
      _flag(FlagCode.outBatterInvalidForKind,
          '${w.kind.label} can only dismiss the batter on strike.');
      return false;
    }

    // Apply.
    wickets++;
    final dismissedStats = batters[out]!;
    dismissedStats.status = BatterStatus.out;
    dismissedStats.dismissal = Dismissal(
      w.kind,
      bowlerId: w.kind.creditsBowler ? e.bowlerId : null,
      fielderId: w.fielderId,
    );
    if (w.kind.creditsBowler) _bowler(bowlerKey).wickets++;
    fow.add(FallOfWicket(wickets, runs, out,
        '${legalBalls ~/ rules.ballsPerOver}.${legalBalls % rules.ballsPerOver}'));

    final survivor = out == striker ? nonStriker : striker;
    final nb = _validNewBatter(w.newBatterId);
    final moreBatters = wickets < maxWickets;
    if (nb == null && w.newBatterId == null && moreBatters && _anyBatterAvailable) {
      _flag(FlagCode.missingNewBatter, 'No incoming batter was chosen.');
    }
    if (nb != null) {
      batters[nb]!.status = BatterStatus.batting;
      if (w.newBatterEnd == NewBatterEnd.onStrike) {
        striker = nb;
        nonStriker = survivor;
      } else {
        striker = survivor;
        nonStriker = nb;
      }
    } else {
      // No (valid) incoming batter: the survivor carries on alone.
      striker = survivor;
      nonStriker = null;
    }
    _startPartnership();
    return true;
  }

  static String _token(Delivery d, RunType rt, int runs, bool wicket) {
    final String base;
    switch (d) {
      case Delivery.deadBall:
        return 'DB';
      case Delivery.wide:
        base = runs > 0 ? 'Wd+$runs' : 'Wd';
      case Delivery.noBall:
        final tail = switch (rt) {
          RunType.none => '',
          RunType.bat => '+$runs',
          RunType.bye => '+${runs}b',
          RunType.legBye => '+${runs}lb',
        };
        base = 'Nb$tail';
      case Delivery.legal:
        base = switch (rt) {
          RunType.none => '.',
          RunType.bat => '$runs',
          RunType.bye => '${runs}b',
          RunType.legBye => '${runs}lb',
        };
    }
    if (!wicket) return base;
    return base == '.' ? 'W' : '${base}W';
  }

  InningsResult finish() {
    return InningsResult(
      rules: rules,
      setup: setup,
      runs: runs,
      wickets: wickets,
      legalBalls: legalBalls,
      extras: extras,
      endReason: ended,
      strikerId: striker,
      nonStrikerId: nonStriker,
      currentBowlerId: lastBowler,
      freeHitNext: freeHit,
      batters: batters,
      bowlers: bowlers,
      fallOfWickets: fow,
      partnerships: partnerships,
      balls: records,
      overs: overs,
      flags: flags,
      maxWickets: maxWickets,
      maxBalls: maxBalls,
    );
  }
}
