import 'package:flow_sports_app/core/cricket/cricket_event.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/innings_replay.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rules with everything switched on and no per-bowler limit, so a test only
/// sees the behaviour it is about (rule-specific tests override this).
const openRules = CricketRules(
  overs: 6,
  lastManStands: false,
  maxOversPerBowler: null,
  legByesAllowed: true,
  allowedWickets: CricketRules.allWickets,
);

const battingLineup = ['a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8'];
const bowlingLineup = ['b1', 'b2', 'b3', 'b4'];

InningsSetup setupFor({
  List<String> batting = battingLineup,
  int? target,
  int? maxOvers,
}) =>
    InningsSetup(
      battingLineup: batting,
      bowlingLineup: bowlingLineup,
      strikerId: batting[0],
      nonStrikerId: batting[1],
      target: target,
      maxOvers: maxOvers,
    );

InningsResult replay(
  List<CricketEvent> events, {
  CricketRules rules = openRules,
  InningsSetup? setup,
}) =>
    replayInnings(rules, setup ?? setupFor(), events);

/// [n] dot balls by [bowler], numbered from [startSeq].
List<CricketEvent> dots(int startSeq, String bowler, int n) =>
    [for (var i = 0; i < n; i++) CricketEvent.dot(startSeq + i, bowler)];

Wicket bowledA1({String? newBatter = 'a3', NewBatterEnd end = NewBatterEnd.onStrike}) => Wicket(
      kind: WicketKind.bowled,
      outBatterId: 'a1',
      newBatterId: newBatter,
      newBatterEnd: end,
    );

/// Cross-checks that must hold for *any* log without invalid inputs: the
/// team total is the sum of its parts however it is cut.
void expectInvariants(InningsResult r) {
  final fromBalls = r.balls.fold<int>(0, (s, b) => s + b.teamRuns);
  expect(r.runs, fromBalls, reason: 'team runs == sum of per-ball runs');

  final batterRuns = r.batters.values.fold<int>(0, (s, b) => s + b.runs);
  expect(r.runs, batterRuns + r.extras.total, reason: 'team runs == bat runs + extras');

  final bowlerRuns = r.bowlers.values.fold<int>(0, (s, b) => s + b.runsConceded);
  expect(r.runs, bowlerRuns + r.extras.byes + r.extras.legByes,
      reason: 'team runs == runs charged to bowlers + byes + leg byes');

  final bowlerBalls = r.bowlers.values.fold<int>(0, (s, b) => s + b.legalBalls);
  expect(r.legalBalls, bowlerBalls);
  expect(r.legalBalls, r.balls.where((b) => b.countsAsBall).length);

  final out = r.batters.values.where((b) => b.status == BatterStatus.out).length;
  expect(r.wickets, out);
  expect(r.fallOfWickets.length, r.wickets);
}
