import 'dart:math';

import 'cricket_event.dart';
import 'cricket_rules.dart';
import 'innings_replay.dart';
import 'match_scoring.dart';

/// Made-up but rule-abiding scoring, for the admin Test Lab: it drives the
/// real replay engine ball by ball, so the logs it produces are exactly what
/// a scorer could have entered (no review flags, correct overs, bowler
/// rotation, free hits, new batters).

CricketEvent _nextEvent({
  required InningsResult r,
  required CricketRules rules,
  required int seq,
  required Random rnd,
}) {
  final String bowler;
  if (needsNewBowler(r)) {
    final choices = bowlerChoices(r);
    final clean = choices.where((c) => c.issue == BowlerIssue.none).toList();
    final fallback = choices.where((c) => c.issue != BowlerIssue.justBowled).toList();
    final pool = clean.isNotEmpty ? clean : (fallback.isNotEmpty ? fallback : choices);
    bowler = pool[rnd.nextInt(pool.length)].id;
  } else {
    bowler = r.currentBowlerId ?? r.setup.bowlingLineup.first;
  }

  final roll = rnd.nextDouble();

  // Wicket (~7% of balls).
  if (roll < 0.07) {
    final striker = r.strikerId;
    if (striker != null) {
      final kinds = <WicketKind>[
        if (r.freeHitNext)
          ...[if (rules.allowedWickets.contains(WicketKind.runOut)) WicketKind.runOut]
        else
          for (final k in const [
            WicketKind.bowled,
            WicketKind.caught,
            WicketKind.lbw,
            WicketKind.stumped,
            WicketKind.hitWicket,
            WicketKind.runOut,
          ])
            if (rules.allowedWickets.contains(k)) k,
      ];
      if (kinds.isNotEmpty) {
        final kind = kinds[rnd.nextInt(kinds.length)];
        final out = kind == WicketKind.runOut && r.nonStrikerId != null && rnd.nextBool()
            ? r.nonStrikerId!
            : striker;
        final available = availableBatters(r);
        final inningsEndsHere = r.wickets + 1 >= r.maxWickets;
        return CricketEvent.wicketBall(
          seq,
          bowler,
          Wicket(
            kind: kind,
            outBatterId: out,
            newBatterId: inningsEndsHere || available.isEmpty ? null : available[rnd.nextInt(available.length)],
            newBatterEnd: Wicket.defaultNewBatterEnd(
              kind: kind,
              outBatterWasStriker: out == striker,
              completedRuns: 0,
            ),
          ),
        );
      }
    }
  }

  Delivery delivery = Delivery.legal;
  RunType extra = RunType.none;
  var runs = const [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 3, 4, 4, 6][rnd.nextInt(17)];
  final kind = rnd.nextDouble();
  if (kind < 0.06) {
    delivery = Delivery.wide;
    runs = const [0, 0, 0, 0, 1, 4][rnd.nextInt(6)];
  } else if (kind < 0.09) {
    delivery = Delivery.noBall;
  } else if (kind < 0.11 && rules.byesAllowed) {
    extra = RunType.bye;
    runs = 1;
  } else if (kind < 0.13 && rules.legByesAllowed) {
    extra = RunType.legBye;
    runs = 1;
  }
  return scoredBall(
    seq: seq,
    bowlerId: bowler,
    rules: rules,
    delivery: delivery,
    extra: extra,
    runsTapped: runs,
  );
}

/// One innings of random cricket, played until it ends (overs done, all out
/// or the target reached).
List<CricketEvent> simulateInnings({
  required CricketRules rules,
  required List<String> batting,
  required List<String> bowling,
  required InningsStart start,
  int? target,
  int? maxWickets,
  int firstSeq = 1,
  Random? random,
}) {
  final rnd = random ?? Random();
  final setup = InningsSetup(
    battingLineup: batting,
    bowlingLineup: bowling,
    strikerId: start.strikerId,
    nonStrikerId: start.nonStrikerId,
    target: target,
    maxOvers: start.maxOvers,
    maxWickets: maxWickets,
  );
  final events = <CricketEvent>[];
  for (var guard = 0; guard < 2000; guard++) {
    final r = replayInnings(rules, setup, events);
    if (r.isEnded) break;
    events.add(_nextEvent(r: r, rules: rules, seq: firstSeq + events.length, rnd: rnd));
  }
  return events;
}

class SimulatedMatch {
  final List<InningsStart> starts;
  final List<LoggedEvent> events;

  const SimulatedMatch(this.starts, this.events);
}

/// A full two-innings match. [battingFirst] is 'A' or 'B'. With [superOver],
/// a tied match carries on with super overs until one side wins (at most
/// [maxSuperOvers], so a pathological run can't loop for ever).
SimulatedMatch simulateMatch({
  required CricketRules rules,
  required List<String> lineupA,
  required List<String> lineupB,
  required String battingFirst,
  bool superOver = false,
  int maxSuperOvers = 5,
  Random? random,
}) {
  final rnd = random ?? Random();
  final firstBatting = battingFirst == 'A' ? lineupA : lineupB;
  final secondBatting = battingFirst == 'A' ? lineupB : lineupA;
  final start1 = InningsStart(strikerId: firstBatting[0], nonStrikerId: firstBatting[1]);
  final start2 = InningsStart(strikerId: secondBatting[0], nonStrikerId: secondBatting[1]);

  final first = simulateInnings(
      rules: rules, batting: firstBatting, bowling: secondBatting, start: start1, random: rnd);
  final firstRuns = replayInnings(
    rules,
    InningsSetup(
      battingLineup: firstBatting,
      bowlingLineup: secondBatting,
      strikerId: start1.strikerId,
      nonStrikerId: start1.nonStrikerId,
    ),
    first,
  ).runs;
  final second = simulateInnings(
    rules: rules,
    batting: secondBatting,
    bowling: firstBatting,
    start: start2,
    target: firstRuns + 1,
    firstSeq: first.length + 1,
    random: rnd,
  );
  final starts = [start1, start2];
  final events = [
    for (final e in first) LoggedEvent(0, e),
    for (final e in second) LoggedEvent(1, e),
  ];

  final secondRuns = replayInnings(
    rules,
    InningsSetup(
      battingLineup: secondBatting,
      bowlingLineup: firstBatting,
      strikerId: start2.strikerId,
      nonStrikerId: start2.nonStrikerId,
      target: firstRuns + 1,
    ),
    second,
  ).runs;
  if (superOver && secondRuns == firstRuns) {
    var seq = first.length + second.length + 1;
    for (var n = 0; n < maxSuperOvers; n++) {
      final opener = n.isEven ? secondBatting : firstBatting;
      final chaser = n.isEven ? firstBatting : secondBatting;
      final s1 = InningsStart(strikerId: opener[0], nonStrikerId: opener[1]);
      final s2 = InningsStart(strikerId: chaser[0], nonStrikerId: chaser[1]);
      final a = simulateInnings(
        rules: rules,
        batting: opener,
        bowling: chaser,
        start: InningsStart(strikerId: s1.strikerId, nonStrikerId: s1.nonStrikerId, maxOvers: superOverOvers),
        maxWickets: superOverWickets,
        firstSeq: seq,
        random: rnd,
      );
      seq += a.length;
      final aRuns = replayInnings(
        rules,
        InningsSetup(
          battingLineup: opener,
          bowlingLineup: chaser,
          strikerId: s1.strikerId,
          nonStrikerId: s1.nonStrikerId,
          maxOvers: superOverOvers,
          maxWickets: superOverWickets,
        ),
        a,
      ).runs;
      final b = simulateInnings(
        rules: rules,
        batting: chaser,
        bowling: opener,
        start: InningsStart(strikerId: s2.strikerId, nonStrikerId: s2.nonStrikerId, maxOvers: superOverOvers),
        target: aRuns + 1,
        maxWickets: superOverWickets,
        firstSeq: seq,
        random: rnd,
      );
      seq += b.length;
      final bRuns = replayInnings(
        rules,
        InningsSetup(
          battingLineup: chaser,
          bowlingLineup: opener,
          strikerId: s2.strikerId,
          nonStrikerId: s2.nonStrikerId,
          target: aRuns + 1,
          maxOvers: superOverOvers,
          maxWickets: superOverWickets,
        ),
        b,
      ).runs;
      starts..add(s1)..add(s2);
      final idx = starts.length - 2;
      events
        ..addAll([for (final e in a) LoggedEvent(idx, e)])
        ..addAll([for (final e in b) LoggedEvent(idx + 1, e)]);
      if (aRuns != bRuns) break;
    }
  }
  return SimulatedMatch(starts, events);
}
