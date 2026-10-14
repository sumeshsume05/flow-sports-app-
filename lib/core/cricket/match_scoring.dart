import 'commentary_text.dart';
import 'cricket_event.dart';
import 'cricket_rules.dart';
import 'cricket_toss.dart';
import 'innings_replay.dart';
import 'match_result.dart';

/// A logged event together with the innings it belongs to. Event numbers
/// (`seq`) run across the whole match, so a double tap or two scorers racing
/// for the same number collide on one document id instead of duplicating.
class LoggedEvent {
  final int innings;
  final CricketEvent event;

  const LoggedEvent(this.innings, this.event);

  int get seq => event.seq;

  Map<String, dynamic> toMap() => {...event.toMap(), 'innings': innings};

  factory LoggedEvent.fromMap(Map<String, dynamic> map) =>
      LoggedEvent(map['innings'] as int? ?? 0, CricketEvent.fromMap(map));
}

/// What the scorer picks to begin an innings. Everything else about the
/// innings (who is batting, the target, totals) is derived.
class InningsStart {
  final String strikerId;
  final String nonStrikerId;

  /// Revised overs for this innings (shortened chase); null = the rules' overs.
  final int? maxOvers;

  const InningsStart({required this.strikerId, required this.nonStrikerId, this.maxOvers});
}

/// One innings as stored on the match doc: the openers (an input) plus a
/// cached copy of the replay's totals, so lists and (later) the points table
/// never need the ball log. The cache is rewritten after every ball.
class InningsRecord {
  final String batting; // 'A' | 'B'
  final InningsStart start;
  final int runs;
  final int wickets;
  final int legalBalls;
  final bool ended;
  final bool allOut;

  const InningsRecord({
    required this.batting,
    required this.start,
    this.runs = 0,
    this.wickets = 0,
    this.legalBalls = 0,
    this.ended = false,
    this.allOut = false,
  });

  Map<String, dynamic> toMap() => {
        'batting': batting,
        'strikerId': start.strikerId,
        'nonStrikerId': start.nonStrikerId,
        'maxOvers': start.maxOvers,
        'runs': runs,
        'wickets': wickets,
        'legalBalls': legalBalls,
        'ended': ended,
        'allOut': allOut,
      };

  factory InningsRecord.fromMap(Map<String, dynamic> map) => InningsRecord(
        batting: map['batting'] as String? ?? 'A',
        start: InningsStart(
          strikerId: map['strikerId'] as String? ?? '',
          nonStrikerId: map['nonStrikerId'] as String? ?? '',
          maxOvers: map['maxOvers'] as int?,
        ),
        runs: map['runs'] as int? ?? 0,
        wickets: map['wickets'] as int? ?? 0,
        legalBalls: map['legalBalls'] as int? ?? 0,
        ended: map['ended'] as bool? ?? false,
        allOut: map['allOut'] as bool? ?? false,
      );
}

enum ScoringPhase {
  /// Rules / squads / toss aren't ready, so there is nothing to score yet.
  needsSetup,

  /// The next innings (see [MatchScoringState.nextInningsIndex]) hasn't been
  /// started — openers still to pick.
  awaitingInnings,
  scoring,

  /// Both innings are over — the result can be saved.
  finished,

  /// The saved openers/squads no longer fit together (e.g. a squad was edited
  /// after the innings started).
  broken,
}

class InningsView {
  final int index;
  final String battingSide; // 'A' | 'B'
  final InningsResult result;
  final List<CricketEvent> events;

  const InningsView(this.index, this.battingSide, this.result, this.events);

  String get bowlingSide => battingSide == 'A' ? 'B' : 'A';
}

class MatchScoringState {
  final ScoringPhase phase;
  final String? problem;
  final List<InningsView> innings;
  final int nextInningsIndex;
  final CricketMatchResult? result;

  const MatchScoringState({
    required this.phase,
    this.problem,
    this.innings = const [],
    this.nextInningsIndex = 0,
    this.result,
  });

  InningsView? get current => innings.isEmpty ? null : innings.last;

  /// Unacknowledged review flags across every innings.
  List<ReviewFlag> get blockingFlags => [for (final i in innings) ...i.result.blockingFlags];
  bool get hasBlockingFlags => blockingFlags.isNotEmpty;

  /// Main-innings runs for one side of the match.
  int runsFor(String side) =>
      innings.where((i) => i.battingSide == side).fold(0, (s, i) => s + i.result.runs);
}

String otherSide(String side) => side == 'A' ? 'B' : 'A';

/// Replays every started innings and works out where the match is. Pure: the
/// scoring screen, the Test Lab auto-play and the tests all go through this.
MatchScoringState deriveMatchState({
  required CricketRules rules,
  required List<String> lineupA,
  required List<String> lineupB,
  required CricketToss? toss,
  required List<InningsStart> starts,
  required List<LoggedEvent> events,
  required String nameA,
  required String nameB,
}) {
  if (toss == null) {
    return const MatchScoringState(
        phase: ScoringPhase.needsSetup, problem: 'Save the toss in match setup first.');
  }
  if (lineupA.length < 2 || lineupB.length < 2) {
    return const MatchScoringState(
        phase: ScoringPhase.needsSetup,
        problem: 'Pick at least 2 players for each side in match setup first.');
  }

  final first = toss.battingFirstSide;
  final views = <InningsView>[];
  for (var i = 0; i < starts.length && i < 2; i++) {
    final side = i.isEven ? first : otherSide(first);
    final batting = side == 'A' ? lineupA : lineupB;
    final bowling = side == 'A' ? lineupB : lineupA;
    final evs = [for (final e in events) if (e.innings == i) e.event];
    final InningsResult result;
    try {
      result = replayInnings(
        rules,
        InningsSetup(
          battingLineup: batting,
          bowlingLineup: bowling,
          strikerId: starts[i].strikerId,
          nonStrikerId: starts[i].nonStrikerId,
          target: i == 1 ? views[0].result.runs + 1 : null,
          maxOvers: starts[i].maxOvers,
        ),
        evs,
      );
    } on ArgumentError {
      return MatchScoringState(
        phase: ScoringPhase.broken,
        problem: 'The openers of innings ${i + 1} are no longer in the squad. '
            'Put them back in match setup, or reset the match.',
        innings: views,
      );
    }
    views.add(InningsView(i, side, result, evs));
  }

  if (views.isEmpty) {
    return const MatchScoringState(phase: ScoringPhase.awaitingInnings, nextInningsIndex: 0);
  }
  final last = views.last;
  if (!last.result.isEnded) {
    return MatchScoringState(phase: ScoringPhase.scoring, innings: views);
  }
  if (views.length == 1) {
    return MatchScoringState(phase: ScoringPhase.awaitingInnings, innings: views, nextInningsIndex: 1);
  }
  return MatchScoringState(
    phase: ScoringPhase.finished,
    innings: views,
    result: computeMatchResult(
      first: views[0].result,
      second: views[1].result,
      firstBattingSide: first,
      teamAName: nameA,
      teamBName: nameB,
    ),
  );
}

// ---------------------------------------------------------------------------
// Bowler choice
// ---------------------------------------------------------------------------

/// The next ball needs a bowler to be picked: the innings is just starting or
/// the last over has finished. (A dead ball is re-bowled by the same bowler.)
bool needsNewBowler(InningsResult r) {
  if (r.isEnded) return false;
  if (r.balls.isEmpty) return true;
  if (r.balls.last.delivery == Delivery.deadBall) return false;
  return r.overs.isNotEmpty && r.overs.last.complete;
}

enum BowlerIssue { none, justBowled, overLimit }

class BowlerChoice {
  final String id;
  final String oversText;
  final int oversStarted;
  final BowlerIssue issue;

  const BowlerChoice(this.id, this.oversText, this.oversStarted, this.issue);
}

/// Everyone in the bowling lineup, with a warning for the two common slips:
/// the same bowler twice in a row and a bowler past their over limit. These
/// are warnings — the scorer can still pick them (the replay flags it).
List<BowlerChoice> bowlerChoices(InningsResult r) {
  final lastOverBowler = r.overs.isEmpty
      ? null
      : (r.overs.last.complete ? r.overs.last.bowlerId : (r.overs.length > 1 ? r.overs[r.overs.length - 2].bowlerId : null));
  final limit = r.rules.maxOversPerBowler;
  return [
    for (final id in r.setup.bowlingLineup)
      () {
        final started = r.overs.where((o) => o.bowlerId == id).length;
        final stats = r.bowlers[id];
        final issue = id == lastOverBowler
            ? BowlerIssue.justBowled
            : (limit != null && started >= limit ? BowlerIssue.overLimit : BowlerIssue.none);
        return BowlerChoice(id, stats?.oversText ?? '0.0', started, issue);
      }(),
  ];
}

/// Players who can still come in (not out, not at the crease).
List<String> availableBatters(InningsResult r) => [
      for (final id in r.setup.battingLineup)
        if ((r.batters[id]?.status == BatterStatus.yetToBat || r.batters[id]?.status == BatterStatus.retired) &&
            id != r.strikerId &&
            id != r.nonStrikerId)
          id,
    ];

// ---------------------------------------------------------------------------
// Turning the scoring buttons into an event
// ---------------------------------------------------------------------------

/// Builds a delivery from what the scorer tapped.
///  * [delivery] — legal / wide / no-ball
///  * [extra] — bye / leg bye (not for wides, whose runs are always extras)
///  * [runsTapped] — the number button: 0, 1, 2, 3, 4, 5, 6. A 4 or 6 is a
///    boundary (it doesn't rotate the strike); the odd cases — overthrows,
///    all-run fours — go through the ball editor.
CricketEvent scoredBall({
  required int seq,
  required String bowlerId,
  required CricketRules rules,
  Delivery delivery = Delivery.legal,
  RunType extra = RunType.none,
  int runsTapped = 0,
  Wicket? wicket,
}) {
  var boundary = Boundary.none;
  var runs = runsTapped;
  if (runsTapped == 4) {
    boundary = Boundary.four;
    runs = rules.boundaryFour;
  } else if (runsTapped == 6) {
    boundary = Boundary.six;
    runs = rules.boundarySix;
  }
  final RunType runType;
  if (delivery == Delivery.wide || runs == 0) {
    runType = RunType.none;
  } else if (extra != RunType.none) {
    runType = extra;
  } else {
    runType = RunType.bat;
  }
  return CricketEvent(
    seq: seq,
    bowlerId: bowlerId,
    delivery: delivery,
    runType: runType,
    runs: runs,
    boundary: runs == 0 ? Boundary.none : boundary,
    wicket: wicket,
  );
}

int nextSeq(List<LoggedEvent> events) =>
    events.isEmpty ? 1 : events.map((e) => e.seq).reduce((a, b) => a > b ? a : b) + 1;

// ---------------------------------------------------------------------------
// What gets written to the match doc after every change
// ---------------------------------------------------------------------------

InningsRecord inningsRecordOf(InningsView v, InningsStart start) => InningsRecord(
      batting: v.battingSide,
      start: start,
      runs: v.result.runs,
      wickets: v.result.wickets,
      legalBalls: v.result.legalBalls,
      ended: v.result.isEnded,
      allOut: v.result.endReason == InningsEnd.allOut,
    );

String _overs(InningsResult r) => r.oversText;

/// Who is at the crease and who is bowling, for the match card:
/// "Arun 12* (8), Gopi 3 (2) · Bowling: Dinesh 1-0-8-1". The * marks the
/// batter on strike.
String? liveLine(InningsResult r, String Function(String id) nameOf) {
  String batter(String? id, {required bool strike}) {
    if (id == null) return '';
    final b = r.batters[id];
    return '${nameOf(id)} ${b?.runs ?? 0}${strike ? '*' : ''} (${b?.balls ?? 0})';
  }

  final batters = [
    batter(r.strikerId, strike: true),
    batter(r.nonStrikerId, strike: false),
  ].where((t) => t.isNotEmpty).join(', ');
  if (batters.isEmpty) return null;
  final id = r.currentBowlerId;
  final bowler = id == null ? null : r.bowlers[id];
  if (id == null || bowler == null) return batters;
  return '$batters · Bowling: ${nameOf(id)} ${bowler.oversText}-${bowler.maidens}-${bowler.runsConceded}-${bowler.wickets}';
}

/// The cached summary of the match, written in the same batch as the ball so
/// the doc never disagrees with the log. Keys are the match doc's fields.
Map<String, dynamic> summaryFields({
  required MatchScoringState state,
  required List<InningsStart> starts,
  required String Function(String id) nameOf,
  required String nameA,
  required String nameB,
  required CricketRules rules,
}) {
  final teamName = {'A': nameA, 'B': nameB};
  final innings = [
    for (final v in state.innings) inningsRecordOf(v, starts[v.index]).toMap(),
  ];

  String? summary;
  String? liveText;
  Map<String, dynamic>? live;
  final cur = state.current;
  if (cur != null) {
    final r = cur.result;
    final batName = teamName[cur.battingSide]!;
    switch (state.phase) {
      case ScoringPhase.scoring:
        final chase = chaseText(r, batName);
        summary = '$batName ${r.scoreText} (${_overs(r)} ov)${chase == null ? '' : ' · $chase'}';
        live = {
          'inningsIndex': cur.index,
          'strikerId': r.strikerId,
          'nonStrikerId': r.nonStrikerId,
          'bowlerId': r.currentBowlerId,
          'freeHit': r.freeHitNext,
        };
        liveText = liveLine(r, nameOf);
      case ScoringPhase.awaitingInnings:
        final other = teamName[otherSide(cur.battingSide)]!;
        summary = '$batName ${r.scoreText} (${_overs(r)} ov) · $other to bat';
      case ScoringPhase.finished:
        summary = state.result?.text;
      default:
        break;
    }
  }

  String? commentary;
  if (cur != null && cur.result.balls.isNotEmpty) {
    commentary = ballCommentary(cur.result.balls.last, nameOf, freeHitRule: rules.freeHit);
  }

  return {
    'innings': innings,
    'live': live,
    'summaryText': summary,
    'liveText': liveText,
    'scoreA': state.runsFor('A'),
    'scoreB': state.runsFor('B'),
    'lastCommentaryText': commentary,
  };
}

/// The fields that finish the match (admin taps Save result).
Map<String, dynamic> resultFields(MatchScoringState state) {
  final r = state.result!;
  return {
    'scoreA': state.runsFor('A'),
    'scoreB': state.runsFor('B'),
    'result': switch (r.winner) {
      CricketWinner.teamA => 'teamA',
      CricketWinner.teamB => 'teamB',
      _ => 'tie',
    },
    'resultText': r.text,
    'status': 'completed',
  };
}
