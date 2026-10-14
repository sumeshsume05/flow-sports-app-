import 'package:flow_sports_app/core/cricket/cricket_event.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/cricket_toss.dart';
import 'package:flow_sports_app/core/cricket/match_scoring.dart';
import 'package:flow_sports_app/core/cricket/setup_guard.dart';
import 'package:flutter_test/flutter_test.dart';

String nameOf(String id) => 'N-$id';

const _rules = CricketRules(overs: 2);
const _toss = CricketToss(winner: 'A', elected: 'bat');
const _a = ['a1', 'a2', 'a3', 'a4'];
const _b = ['b1', 'b2', 'b3', 'b4'];
const _starts = [InningsStart(strikerId: 'a1', nonStrikerId: 'a2')];

SetupChange check({
  bool started = true,
  bool finished = false,
  CricketRules rules = _rules,
  CricketToss? toss = _toss,
  List<String> lineupA = _a,
  List<String> lineupB = _b,
  List<LoggedEvent> events = const [],
}) =>
    checkSetupChange(
      started: started,
      finished: finished,
      oldRules: _rules,
      newRules: rules,
      oldToss: _toss,
      newToss: toss,
      oldLineupA: _a,
      oldLineupB: _b,
      newLineupA: lineupA,
      newLineupB: lineupB,
      starts: _starts,
      events: events,
      nameOf: nameOf,
    );

void main() {
  test('an upcoming match can be changed freely', () {
    final c = check(started: false, toss: const CricketToss(winner: 'B', elected: 'bowl'), lineupA: const ['a1', 'a2']);
    expect(c.isClean, isTrue);
  });

  test('no change on a started match is clean', () {
    expect(check().isClean, isTrue);
  });

  test('a finished match must be reopened first', () {
    final c = check(finished: true);
    expect(c.blockers.single, contains('Reopen to edit'));
  });

  test('the toss cannot change after the start', () {
    final c = check(toss: const CricketToss(winner: 'A', elected: 'bowl'));
    expect(c.blockers.single, contains('toss'));
  });

  test('removing someone who batted, bowled or fielded is blocked, by name', () {
    final events = [
      LoggedEvent(0, CricketEvent.bat(1, 'b1', 1)),
      LoggedEvent(
        0,
        CricketEvent.wicketBall(
          2,
          'b2',
          const Wicket(kind: WicketKind.caught, outBatterId: 'a1', fielderId: 'b3', newBatterId: 'a3'),
        ),
      ),
    ];
    // a3 came in, b3 fielded, b4 did nothing, a4 did nothing.
    final c = check(
      events: events,
      lineupA: const ['a1', 'a2', 'a4'],
      lineupB: const ['b1', 'b2', 'b4'],
    );
    expect(c.blockers.single, contains('N-a3'));
    expect(c.blockers.single, contains('N-b3'));
    expect(c.blockers.single, isNot(contains('N-a4')));

    // Removing only players who did nothing is fine.
    final ok = check(events: events, lineupA: const ['a1', 'a2', 'a3'], lineupB: const ['b1', 'b2', 'b3']);
    expect(ok.blockers, isEmpty);
  });

  test('openers count as used even before any ball', () {
    final c = check(lineupA: const ['a2', 'a3', 'a4']); // a1 opens
    expect(c.blockers.single, contains('N-a1'));
  });

  test('changed rules and added players need a "yes"', () {
    final c = check(rules: const CricketRules(overs: 3), lineupA: const [..._a, 'a5']);
    expect(c.blockers, isEmpty);
    expect(c.warnings.length, 2);
    expect(c.warnings.first, contains('rules changed'));
    expect(c.warnings.last, contains('added'));
  });
}
