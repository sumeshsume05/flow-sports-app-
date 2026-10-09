import 'cricket_rules.dart';

/// What kind of entry this is in the match's ordered event log. Control
/// events (swap, retire, end innings) live in the same log as deliveries so
/// that a replay reproduces exactly what the scorer did, in order.
enum EventKind { ball, swapStrike, retire, endInnings }

enum Delivery { legal, wide, noBall, deadBall }

/// Who the runs on a delivery belong to. A wide's runs are always extras,
/// so a wide carries [none].
enum RunType { none, bat, bye, legBye }

/// The runs were awarded as a boundary allowance (the ball reached the
/// rope) rather than run — a boundary doesn't rotate the strike.
enum Boundary { none, four, six }

/// Where the incoming batter stands after a dismissal/retirement, measured
/// *after* the ball's runs have been run and *before* any end-of-over swap.
enum NewBatterEnd { onStrike, offStrike }

class Wicket {
  final WicketKind kind;
  final String outBatterId;
  final String? fielderId;

  /// Caught only: the batters had crossed before the catch.
  final bool crossed;
  final String? newBatterId;
  final NewBatterEnd newBatterEnd;

  const Wicket({
    required this.kind,
    required this.outBatterId,
    this.fielderId,
    this.crossed = false,
    this.newBatterId,
    this.newBatterEnd = NewBatterEnd.onStrike,
  });

  /// The end the incoming batter should take by default — what the scoring
  /// screen pre-selects (the scorer can override it):
  ///  * bowled / lbw / stumped / hit wicket / caught-not-crossed → on strike
  ///  * caught after the batters crossed → off strike
  ///  * run out → the incoming batter takes the end the dismissed batter was
  ///    running to. With `c` completed runs, the dismissed batter was heading
  ///    to the striker's end iff (they were the striker at the start and `c`
  ///    is odd) or (they were the non-striker at the start and `c` is even).
  static NewBatterEnd defaultNewBatterEnd({
    required WicketKind kind,
    required bool outBatterWasStriker,
    required int completedRuns,
    bool crossed = false,
  }) {
    if (kind == WicketKind.runOut) {
      final headingToStrikersEnd = (outBatterWasStriker && completedRuns.isOdd) ||
          (!outBatterWasStriker && completedRuns.isEven);
      return headingToStrikersEnd ? NewBatterEnd.onStrike : NewBatterEnd.offStrike;
    }
    if (kind == WicketKind.caught && crossed) return NewBatterEnd.offStrike;
    return NewBatterEnd.onStrike;
  }

  Wicket copyWith({
    WicketKind? kind,
    String? outBatterId,
    String? fielderId,
    bool? crossed,
    String? newBatterId,
    bool clearNewBatterId = false,
    NewBatterEnd? newBatterEnd,
  }) =>
      Wicket(
        kind: kind ?? this.kind,
        outBatterId: outBatterId ?? this.outBatterId,
        fielderId: fielderId ?? this.fielderId,
        crossed: crossed ?? this.crossed,
        newBatterId: clearNewBatterId ? null : (newBatterId ?? this.newBatterId),
        newBatterEnd: newBatterEnd ?? this.newBatterEnd,
      );

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        'outBatterId': outBatterId,
        'fielderId': fielderId,
        'crossed': crossed,
        'newBatterId': newBatterId,
        'newBatterEnd': newBatterEnd.name,
      };

  factory Wicket.fromMap(Map<String, dynamic> map) => Wicket(
        kind: WicketKind.values.firstWhere((k) => k.name == map['kind']),
        outBatterId: map['outBatterId'] as String,
        fielderId: map['fielderId'] as String?,
        crossed: map['crossed'] as bool? ?? false,
        newBatterId: map['newBatterId'] as String?,
        newBatterEnd: NewBatterEnd.values.firstWhere(
          (e) => e.name == map['newBatterEnd'],
          orElse: () => NewBatterEnd.onStrike,
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is Wicket &&
      other.kind == kind &&
      other.outBatterId == outBatterId &&
      other.fielderId == fielderId &&
      other.crossed == crossed &&
      other.newBatterId == newBatterId &&
      other.newBatterEnd == newBatterEnd;

  @override
  int get hashCode => Object.hash(kind, outBatterId, fielderId, crossed, newBatterId, newBatterEnd);
}

const _unset = Object();

/// One entry of the event log — **inputs only**: exactly what the scorer
/// entered. Striker, non-striker, over/ball numbers, legality, free-hit and
/// every total are re-derived by `replayInnings`, never stored here, so
/// editing one event and replaying always produces consistent state while
/// every later event keeps the inputs the scorer originally entered.
class CricketEvent {
  final int seq;
  final EventKind kind;

  /// Bowler for this delivery (the scoring UI carries the current bowler
  /// forward; the replay checks it is consistent within an over).
  final String? bowlerId;

  // kind == ball
  final Delivery delivery;
  final RunType runType;

  /// legal/no-ball: runs awarded via [runType]. wide: runs on top of the
  /// wide's penalty run.
  final int runs;
  final Boundary boundary;

  /// Only for overthrows / short runs — normally absent. Otherwise the runs
  /// the batters physically ran are `boundary != none ? 0 : runs`.
  final int? completedRunsOverride;
  final Wicket? wicket;

  // kind == retire
  final String? retiredBatterId;
  final String? newBatterId;

  /// Review-flag codes (`FlagCode.name`) the admin accepted for this event.
  final Set<String> acknowledgedFlags;

  const CricketEvent({
    required this.seq,
    this.kind = EventKind.ball,
    this.bowlerId,
    this.delivery = Delivery.legal,
    this.runType = RunType.none,
    this.runs = 0,
    this.boundary = Boundary.none,
    this.completedRunsOverride,
    this.wicket,
    this.retiredBatterId,
    this.newBatterId,
    this.acknowledgedFlags = const {},
  });

  const CricketEvent.swapStrike(int seq) : this(seq: seq, kind: EventKind.swapStrike);

  const CricketEvent.endInnings(int seq) : this(seq: seq, kind: EventKind.endInnings);

  const CricketEvent.retire({
    required int seq,
    required String retiredBatterId,
    String? newBatterId,
  }) : this(
          seq: seq,
          kind: EventKind.retire,
          retiredBatterId: retiredBatterId,
          newBatterId: newBatterId,
        );

  /// Convenience for the common deliveries (also used heavily by tests).
  const CricketEvent.dot(int seq, String bowlerId)
      : this(seq: seq, bowlerId: bowlerId);

  const CricketEvent.bat(int seq, String bowlerId, int runs, {Boundary boundary = Boundary.none})
      : this(
          seq: seq,
          bowlerId: bowlerId,
          runType: RunType.bat,
          runs: runs,
          boundary: boundary,
        );

  /// A wide: [extraRuns] are on top of the wide's own penalty run.
  const CricketEvent.wide(int seq, String bowlerId, {int extraRuns = 0, Boundary boundary = Boundary.none})
      : this(
          seq: seq,
          bowlerId: bowlerId,
          delivery: Delivery.wide,
          runs: extraRuns,
          boundary: boundary,
        );

  const CricketEvent.noBall(
    int seq,
    String bowlerId, {
    RunType runType = RunType.none,
    int runs = 0,
    Boundary boundary = Boundary.none,
    Wicket? wicket,
  }) : this(
          seq: seq,
          bowlerId: bowlerId,
          delivery: Delivery.noBall,
          runType: runType,
          runs: runs,
          boundary: boundary,
          wicket: wicket,
        );

  const CricketEvent.bye(int seq, String bowlerId, int runs, {Boundary boundary = Boundary.none})
      : this(
          seq: seq,
          bowlerId: bowlerId,
          runType: RunType.bye,
          runs: runs,
          boundary: boundary,
        );

  const CricketEvent.legBye(int seq, String bowlerId, int runs, {Boundary boundary = Boundary.none})
      : this(
          seq: seq,
          bowlerId: bowlerId,
          runType: RunType.legBye,
          runs: runs,
          boundary: boundary,
        );

  /// A legal delivery with a dismissal ([runs] are bat runs completed before
  /// it, e.g. a run out going for a second run).
  const CricketEvent.wicketBall(int seq, String bowlerId, Wicket wicket, {int runs = 0})
      : this(
          seq: seq,
          bowlerId: bowlerId,
          runType: runs > 0 ? RunType.bat : RunType.none,
          runs: runs,
          wicket: wicket,
        );

  CricketEvent copyWith({
    int? seq,
    String? bowlerId,
    Delivery? delivery,
    RunType? runType,
    int? runs,
    Boundary? boundary,
    Object? completedRunsOverride = _unset,
    Object? wicket = _unset,
    Set<String>? acknowledgedFlags,
  }) =>
      CricketEvent(
        seq: seq ?? this.seq,
        kind: kind,
        bowlerId: bowlerId ?? this.bowlerId,
        delivery: delivery ?? this.delivery,
        runType: runType ?? this.runType,
        runs: runs ?? this.runs,
        boundary: boundary ?? this.boundary,
        completedRunsOverride: identical(completedRunsOverride, _unset)
            ? this.completedRunsOverride
            : completedRunsOverride as int?,
        wicket: identical(wicket, _unset) ? this.wicket : wicket as Wicket?,
        retiredBatterId: retiredBatterId,
        newBatterId: newBatterId,
        acknowledgedFlags: acknowledgedFlags ?? this.acknowledgedFlags,
      );

  Map<String, dynamic> toMap() => {
        'seq': seq,
        'kind': kind.name,
        'bowlerId': bowlerId,
        'delivery': delivery.name,
        'runType': runType.name,
        'runs': runs,
        'boundary': boundary.name,
        'completedRunsOverride': completedRunsOverride,
        'wicket': wicket?.toMap(),
        'retiredBatterId': retiredBatterId,
        'newBatterId': newBatterId,
        'acknowledgedFlags': acknowledgedFlags.toList()..sort(),
      };

  factory CricketEvent.fromMap(Map<String, dynamic> map) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    final w = map['wicket'];
    return CricketEvent(
      seq: map['seq'] as int,
      kind: pick(EventKind.values, map['kind'], EventKind.ball),
      bowlerId: map['bowlerId'] as String?,
      delivery: pick(Delivery.values, map['delivery'], Delivery.legal),
      runType: pick(RunType.values, map['runType'], RunType.none),
      runs: map['runs'] as int? ?? 0,
      boundary: pick(Boundary.values, map['boundary'], Boundary.none),
      completedRunsOverride: map['completedRunsOverride'] as int?,
      wicket: w is Map ? Wicket.fromMap(Map<String, dynamic>.from(w)) : null,
      retiredBatterId: map['retiredBatterId'] as String?,
      newBatterId: map['newBatterId'] as String?,
      acknowledgedFlags: {
        ...((map['acknowledgedFlags'] as List?)?.cast<String>() ?? const <String>[]),
      },
    );
  }

  /// Input equality — used by tests to prove a later event's stored inputs
  /// were not touched by an edit to an earlier one.
  @override
  bool operator ==(Object other) =>
      other is CricketEvent &&
      other.seq == seq &&
      other.kind == kind &&
      other.bowlerId == bowlerId &&
      other.delivery == delivery &&
      other.runType == runType &&
      other.runs == runs &&
      other.boundary == boundary &&
      other.completedRunsOverride == completedRunsOverride &&
      other.wicket == wicket &&
      other.retiredBatterId == retiredBatterId &&
      other.newBatterId == newBatterId &&
      other.acknowledgedFlags.length == acknowledgedFlags.length &&
      other.acknowledgedFlags.containsAll(acknowledgedFlags);

  @override
  int get hashCode => Object.hash(seq, kind, bowlerId, delivery, runType, runs, boundary,
      completedRunsOverride, wicket, retiredBatterId, newBatterId);
}

/// Replaces the event with [seq] by [edited] (keeping that seq). Every other
/// event is returned untouched — same inputs, same order. Throws if [seq]
/// isn't in the log.
List<CricketEvent> editEvent(List<CricketEvent> log, int seq, CricketEvent edited) {
  if (!log.any((e) => e.seq == seq)) {
    throw ArgumentError('No event with seq $seq in the log');
  }
  return [
    for (final e in log)
      if (e.seq == seq) edited.copyWith(seq: seq) else e,
  ];
}

/// Removes the event with [seq]. Later events keep their own seq (gaps are
/// fine — replay orders by seq).
List<CricketEvent> deleteEvent(List<CricketEvent> log, int seq) =>
    [for (final e in log) if (e.seq != seq) e];

/// Undo = drop the last event in the log.
List<CricketEvent> undoLast(List<CricketEvent> log) {
  if (log.isEmpty) return log;
  final last = log.reduce((a, b) => a.seq >= b.seq ? a : b);
  return deleteEvent(log, last.seq);
}
