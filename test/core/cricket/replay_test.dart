import 'package:flow_sports_app/core/cricket/cricket_event.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/innings_replay.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cricket_test_utils.dart';

void main() {
  group('strike rotation & runs — one test per delivery type', () {
    test('dot ball: counts as a ball, nothing else changes', () {
      final r = replay([const CricketEvent.dot(1, 'b1')]);
      expect(r.runs, 0);
      expect(r.legalBalls, 1);
      expect(r.strikerId, 'a1');
      expect(r.nonStrikerId, 'a2');
      expect(r.batters['a1']!.balls, 1);
      expect(r.balls.single.token, '.');
      expectInvariants(r);
    });

    test('bat 1 swaps the strike; credited to batter and bowler', () {
      final r = replay([const CricketEvent.bat(1, 'b1', 1)]);
      expect(r.runs, 1);
      expect(r.strikerId, 'a2');
      expect(r.nonStrikerId, 'a1');
      expect(r.batters['a1']!.runs, 1);
      expect(r.bowlers['b1']!.runsConceded, 1);
      expectInvariants(r);
    });

    test('bat 2 keeps the strike, bat 3 swaps it', () {
      expect(replay([const CricketEvent.bat(1, 'b1', 2)]).strikerId, 'a1');
      expect(replay([const CricketEvent.bat(1, 'b1', 3)]).strikerId, 'a2');
    });

    test('boundary 4 / 6: runs counted, no swap, fours/sixes tallied', () {
      final r = replay([
        const CricketEvent.bat(1, 'b1', 4, boundary: Boundary.four),
        const CricketEvent.bat(2, 'b1', 6, boundary: Boundary.six),
      ]);
      expect(r.runs, 10);
      expect(r.strikerId, 'a1');
      expect(r.batters['a1']!.fours, 1);
      expect(r.batters['a1']!.sixes, 1);
      expect(r.balls.first.completedRuns, 0);
    });

    test('4 all run (no boundary) is even, so no swap and not a "four"', () {
      final r = replay([const CricketEvent.bat(1, 'b1', 4)]);
      expect(r.strikerId, 'a1');
      expect(r.batters['a1']!.fours, 0);
      expect(r.balls.single.completedRuns, 4);
    });

    test('5 all run is odd, so it swaps', () {
      expect(replay([const CricketEvent.bat(1, 'b1', 5)]).strikerId, 'a2');
    });

    test('boundary with completedRunsOverride=1 (overthrow) swaps the strike', () {
      final r = replay([
        const CricketEvent(
          seq: 1,
          bowlerId: 'b1',
          runType: RunType.bat,
          runs: 5,
          boundary: Boundary.four,
          completedRunsOverride: 1,
        ),
      ]);
      expect(r.runs, 5);
      expect(r.batters['a1']!.runs, 5);
      expect(r.strikerId, 'a2');
    });

    test('bye 1 swaps; credited to nobody, not charged to the bowler, ball faced', () {
      final r = replay([const CricketEvent.bye(1, 'b1', 1)]);
      expect(r.runs, 1);
      expect(r.extras.byes, 1);
      expect(r.strikerId, 'a2');
      expect(r.batters['a1']!.runs, 0);
      expect(r.batters['a1']!.balls, 1);
      expect(r.bowlers['b1']!.runsConceded, 0);
      expect(r.legalBalls, 1);
      expectInvariants(r);
    });

    test('leg bye 1 swaps (when allowed)', () {
      final r = replay([const CricketEvent.legBye(1, 'b1', 1)]);
      expect(r.extras.legByes, 1);
      expect(r.strikerId, 'a2');
      expect(r.flags, isEmpty);
    });

    test('bye boundary 4: four extras, no swap', () {
      final r = replay([const CricketEvent.bye(1, 'b1', 4, boundary: Boundary.four)]);
      expect(r.runs, 4);
      expect(r.extras.byes, 4);
      expect(r.strikerId, 'a1');
    });

    test('wide, nothing run: +1 wide, NOT a legal ball, not faced, no swap', () {
      final r = replay([const CricketEvent.wide(1, 'b1')]);
      expect(r.runs, 1);
      expect(r.extras.wides, 1);
      expect(r.legalBalls, 0);
      expect(r.batters['a1']!.balls, 0);
      expect(r.strikerId, 'a1');
      expect(r.bowlers['b1']!.runsConceded, 1);
      expect(r.bowlers['b1']!.wides, 1);
      expect(r.bowlers['b1']!.legalBalls, 0);
      expect(r.balls.single.token, 'Wd');
      expectInvariants(r);
    });

    test('wide + 1 run run: 2 wides, swap', () {
      final r = replay([const CricketEvent.wide(1, 'b1', extraRuns: 1)]);
      expect(r.runs, 2);
      expect(r.extras.wides, 2);
      expect(r.strikerId, 'a2');
      expect(r.balls.single.token, 'Wd+1');
    });

    test('wide that reaches the rope: 5 wides (1 + 4), no swap', () {
      final r = replay([
        const CricketEvent.wide(1, 'b1', extraRuns: 4, boundary: Boundary.four),
      ]);
      expect(r.runs, 5);
      expect(r.extras.wides, 5);
      expect(r.strikerId, 'a1');
      expect(r.bowlers['b1']!.runsConceded, 5);
    });

    test('no-ball dot: +1, not a legal ball, batter faced it, free hit next, no swap', () {
      final r = replay([const CricketEvent.noBall(1, 'b1')]);
      expect(r.runs, 1);
      expect(r.extras.noBalls, 1);
      expect(r.legalBalls, 0);
      expect(r.batters['a1']!.balls, 1);
      expect(r.freeHitNext, isTrue);
      expect(r.strikerId, 'a1');
    });

    test('no-ball + bat 1: total 2, batter 1, bowler 2, swap', () {
      final r = replay([const CricketEvent.noBall(1, 'b1', runType: RunType.bat, runs: 1)]);
      expect(r.runs, 2);
      expect(r.batters['a1']!.runs, 1);
      expect(r.bowlers['b1']!.runsConceded, 2);
      expect(r.strikerId, 'a2');
      expect(r.balls.single.token, 'Nb+1');
      expectInvariants(r);
    });

    test('no-ball + six: 7 total, batter 6, no swap', () {
      final r = replay([
        const CricketEvent.noBall(1, 'b1',
            runType: RunType.bat, runs: 6, boundary: Boundary.six),
      ]);
      expect(r.runs, 7);
      expect(r.batters['a1']!.runs, 6);
      expect(r.batters['a1']!.sixes, 1);
      expect(r.bowlers['b1']!.runsConceded, 7);
      expect(r.strikerId, 'a1');
    });

    test('no-ball + bye 1: total 2, bowler charged only the no-ball, swap', () {
      final r = replay([const CricketEvent.noBall(1, 'b1', runType: RunType.bye, runs: 1)]);
      expect(r.runs, 2);
      expect(r.extras.noBalls, 1);
      expect(r.extras.byes, 1);
      expect(r.extras.total, 2);
      expect(r.bowlers['b1']!.runsConceded, 1);
      expect(r.strikerId, 'a2');
      expectInvariants(r);
    });

    test('dead ball changes nothing and does not use up a ball', () {
      final r = replay([const CricketEvent(seq: 1, bowlerId: 'b1', delivery: Delivery.deadBall)]);
      expect(r.runs, 0);
      expect(r.legalBalls, 0);
      expect(r.batters['a1']!.balls, 0);
      expect(r.balls.single.token, 'DB');
      expect(r.overs, isEmpty);
    });

    test('wide that counts as a ball when the rules say no re-bowl', () {
      final noReBowl = openRules.copyWith(wideReBowl: false);
      final r = replay([const CricketEvent.wide(1, 'b1')], rules: noReBowl);
      expect(r.legalBalls, 1);
      expect(r.runs, 1);
    });

    test('penalty runs come from the rules, not the event', () {
      final r = replay(
        [const CricketEvent.wide(1, 'b1'), const CricketEvent.noBall(2, 'b1')],
        rules: openRules.copyWith(widePenalty: 2, noBallPenalty: 3),
      );
      expect(r.extras.wides, 2);
      expect(r.extras.noBalls, 3);
      expect(r.runs, 5);
    });
  });

  group('overs', () {
    test('a single on the 6th legal ball: SAME batter faces the next over', () {
      final r = replay([...dots(1, 'b1', 5), const CricketEvent.bat(6, 'b1', 1)]);
      expect(r.legalBalls, 6);
      expect(r.strikerId, 'a1'); // run swap + over-end swap cancel out
      expect(r.nonStrikerId, 'a2');
    });

    test('a dot on the 6th ball swaps the ends', () {
      final r = replay(dots(1, 'b1', 6));
      expect(r.strikerId, 'a2');
      expect(r.nonStrikerId, 'a1');
      expect(r.overs.single.complete, isTrue);
    });

    test('a wide/no-ball does not complete or advance the over', () {
      final r = replay([
        ...dots(1, 'b1', 5),
        const CricketEvent.wide(6, 'b1'),
        const CricketEvent.noBall(7, 'b1'),
      ]);
      expect(r.legalBalls, 5);
      expect(r.strikerId, 'a1');
      expect(r.overs.single.complete, isFalse);
    });

    test('over/ball numbering: counted balls are 1-based, re-bowls repeat the position', () {
      final r = replay([
        const CricketEvent.dot(1, 'b1'),
        const CricketEvent.wide(2, 'b1'),
        const CricketEvent.dot(3, 'b1'),
      ]);
      expect([for (final b in r.balls) b.over], [0, 0, 0]);
      expect([for (final b in r.balls) b.ballInOver], [1, 1, 2]);
      expect(r.oversText, '0.2');
    });

    test('second over starts at over index 1, ball 1', () {
      final r = replay([...dots(1, 'b1', 6), const CricketEvent.dot(7, 'b2')]);
      expect(r.balls.last.over, 1);
      expect(r.balls.last.ballInOver, 1);
      expect(r.oversText, '1.1');
    });

    test('maiden: six dots; byes still maiden; a wide spoils it', () {
      final maiden = replay(dots(1, 'b1', 6));
      expect(maiden.bowlers['b1']!.maidens, 1);

      final withBye = replay([...dots(1, 'b1', 5), const CricketEvent.bye(6, 'b1', 1)]);
      expect(withBye.bowlers['b1']!.maidens, 1);

      final withWide = replay([
        const CricketEvent.wide(1, 'b1'),
        ...dots(2, 'b1', 6),
      ]);
      expect(withWide.bowlers['b1']!.maidens, 0);
    });

    test('bowler economy and overs text', () {
      final r = replay([
        const CricketEvent.bat(1, 'b1', 4, boundary: Boundary.four),
        const CricketEvent.bat(2, 'b1', 2),
        ...dots(3, 'b1', 4),
      ]);
      final b = r.bowlers['b1']!;
      expect(b.oversText, '1.0');
      expect(b.runsConceded, 6);
      expect(b.economy, 6.0);
    });

    test('overs done ends the innings; later balls are flagged, not applied', () {
      final r = replay(
        [...dots(1, 'b1', 6), const CricketEvent.bat(7, 'b2', 4, boundary: Boundary.four)],
        rules: openRules.copyWith(overs: 1),
      );
      expect(r.endReason, InningsEnd.oversDone);
      expect(r.runs, 0);
      expect(r.flagsFor(7).single.code, FlagCode.ballAfterInningsEnd);
    });

    test('a revised maxOvers in the setup shortens the innings', () {
      final r = replay(dots(1, 'b1', 6), setup: setupFor(maxOvers: 1));
      expect(r.endReason, InningsEnd.oversDone);
    });
  });

  group('free hit', () {
    test('ball after a no-ball is a free hit and the free hit then ends', () {
      final r = replay([
        const CricketEvent.noBall(1, 'b1'),
        const CricketEvent.dot(2, 'b1'),
        const CricketEvent.dot(3, 'b1'),
      ]);
      expect(r.balls.map((b) => b.freeHit), [false, true, false]);
      expect(r.freeHitNext, isFalse);
    });

    test('free hit carries over a wide', () {
      final r = replay([
        const CricketEvent.noBall(1, 'b1'),
        const CricketEvent.wide(2, 'b1'),
        const CricketEvent.dot(3, 'b1'),
        const CricketEvent.dot(4, 'b1'),
      ]);
      expect(r.balls.map((b) => b.freeHit), [false, true, true, false]);
    });

    test('free hit carries over another no-ball', () {
      final r = replay([
        const CricketEvent.noBall(1, 'b1'),
        const CricketEvent.noBall(2, 'b1'),
        const CricketEvent.dot(3, 'b1'),
        const CricketEvent.dot(4, 'b1'),
      ]);
      expect(r.balls.map((b) => b.freeHit), [false, true, true, false]);
    });

    test('a dead ball neither starts nor ends a free hit', () {
      final r = replay([
        const CricketEvent.noBall(1, 'b1'),
        const CricketEvent(seq: 2, bowlerId: 'b1', delivery: Delivery.deadBall),
        const CricketEvent.dot(3, 'b1'),
      ]);
      expect(r.balls.last.freeHit, isTrue);
    });

    test('no free hit when the rule is off', () {
      final r = replay([
        const CricketEvent.noBall(1, 'b1'),
        const CricketEvent.dot(2, 'b1'),
      ], rules: openRules.copyWith(freeHit: false));
      expect(r.balls.last.freeHit, isFalse);
      expect(r.freeHitNext, isFalse);
    });

    test('bowled on a free hit is flagged and NOT applied; run out is fine', () {
      final bowled = replay([
        const CricketEvent.noBall(1, 'b1'),
        CricketEvent.wicketBall(2, 'b1', bowledA1()),
      ]);
      expect(bowled.wickets, 0);
      expect(bowled.flagsFor(2).single.code, FlagCode.wicketKindNotAllowed);

      final runOut = replay([
        const CricketEvent.noBall(1, 'b1'),
        const CricketEvent.wicketBall(
          2,
          'b1',
          Wicket(kind: WicketKind.runOut, outBatterId: 'a2', newBatterId: 'a3'),
        ),
      ]);
      expect(runOut.wickets, 1);
      expect(runOut.flags, isEmpty);
    });
  });

  group('wickets & new-batter placement', () {
    test('bowled: striker out, new batter on strike, bowler credited, FoW recorded', () {
      final r = replay([
        const CricketEvent.bat(1, 'b1', 2),
        CricketEvent.wicketBall(2, 'b1', bowledA1()),
      ]);
      expect(r.wickets, 1);
      expect(r.strikerId, 'a3');
      expect(r.nonStrikerId, 'a2');
      expect(r.batters['a1']!.status, BatterStatus.out);
      expect(r.batters['a1']!.dismissal!.kind, WicketKind.bowled);
      expect(r.batters['a1']!.dismissal!.bowlerId, 'b1');
      expect(r.batters['a3']!.status, BatterStatus.batting);
      expect(r.bowlers['b1']!.wickets, 1);
      expect(r.fallOfWickets.single.wicketNumber, 1);
      expect(r.fallOfWickets.single.teamRuns, 2);
      expect(r.fallOfWickets.single.batterId, 'a1');
      expect(r.fallOfWickets.single.oversText, '0.2');
      expect(r.balls.last.token, 'W');
      expectInvariants(r);
    });

    test('caught after the batters crossed: new batter at the non-striker end', () {
      expect(
        Wicket.defaultNewBatterEnd(
            kind: WicketKind.caught, outBatterWasStriker: true, completedRuns: 0, crossed: true),
        NewBatterEnd.offStrike,
      );
      final r = replay([
        const CricketEvent.wicketBall(
          1,
          'b1',
          Wicket(
            kind: WicketKind.caught,
            outBatterId: 'a1',
            fielderId: 'b2',
            crossed: true,
            newBatterId: 'a3',
            newBatterEnd: NewBatterEnd.offStrike,
          ),
        ),
      ]);
      expect(r.strikerId, 'a2');
      expect(r.nonStrikerId, 'a3');
      expect(r.batters['a1']!.dismissal!.fielderId, 'b2');
    });

    test('default new-batter end for run outs follows the "running to" rule', () {
      NewBatterEnd d(bool wasStriker, int c) => Wicket.defaultNewBatterEnd(
            kind: WicketKind.runOut,
            outBatterWasStriker: wasStriker,
            completedRuns: c,
          );
      expect(d(true, 0), NewBatterEnd.offStrike); // striker out at far end
      expect(d(false, 0), NewBatterEnd.onStrike); // non-striker out at striker's end
      expect(d(true, 1), NewBatterEnd.onStrike); // after one run the roles flip
      expect(d(false, 1), NewBatterEnd.offStrike);
      expect(d(true, 2), NewBatterEnd.offStrike);
      expect(
        Wicket.defaultNewBatterEnd(
            kind: WicketKind.bowled, outBatterWasStriker: true, completedRuns: 0),
        NewBatterEnd.onStrike,
      );
    });

    test('run out of the striker at the far end (no run): new batter off strike', () {
      final r = replay([
        const CricketEvent.wicketBall(
          1,
          'b1',
          Wicket(
            kind: WicketKind.runOut,
            outBatterId: 'a1',
            newBatterId: 'a3',
            newBatterEnd: NewBatterEnd.offStrike,
          ),
        ),
      ]);
      expect(r.strikerId, 'a2');
      expect(r.nonStrikerId, 'a3');
      expect(r.bowlers['b1']!.wickets, 0); // run out isn't the bowler's wicket
      expect(r.batters['a1']!.dismissal!.bowlerId, isNull);
    });

    test('run out of the non-striker at the striker end (no run): new batter on strike', () {
      final r = replay([
        const CricketEvent.wicketBall(
          1,
          'b1',
          Wicket(
            kind: WicketKind.runOut,
            outBatterId: 'a2',
            newBatterId: 'a3',
            newBatterEnd: NewBatterEnd.onStrike,
          ),
        ),
      ]);
      expect(r.strikerId, 'a3');
      expect(r.nonStrikerId, 'a1');
    });

    test('run out going for a second run after completing one', () {
      final r = replay([
        const CricketEvent.wicketBall(
          1,
          'b1',
          Wicket(
            kind: WicketKind.runOut,
            outBatterId: 'a1',
            newBatterId: 'a3',
            newBatterEnd: NewBatterEnd.onStrike,
          ),
          runs: 1,
        ),
      ]);
      expect(r.runs, 1);
      expect(r.batters['a1']!.runs, 1); // the completed run counts to the batter
      expect(r.strikerId, 'a3');
      expect(r.nonStrikerId, 'a2');
    });

    test('wicket on the 6th ball: new batter placed first, then the over-end swap', () {
      final r = replay([
        ...dots(1, 'b1', 5),
        CricketEvent.wicketBall(6, 'b1', bowledA1()),
      ]);
      expect(r.strikerId, 'a2');
      expect(r.nonStrikerId, 'a3');
      expect(r.legalBalls, 6);
    });

    test('stumped is allowed on a wide (ball still not legal)', () {
      final r = replay([
        const CricketEvent(
          seq: 1,
          bowlerId: 'b1',
          delivery: Delivery.wide,
          wicket: Wicket(kind: WicketKind.stumped, outBatterId: 'a1', newBatterId: 'a3'),
        ),
      ]);
      expect(r.wickets, 1);
      expect(r.legalBalls, 0);
      expect(r.runs, 1);
      expect(r.bowlers['b1']!.wickets, 1);
      expect(r.flags, isEmpty);
    });

    test('bowled on a wide / caught on a no-ball are flagged and not applied', () {
      final wide = replay([
        CricketEvent(seq: 1, bowlerId: 'b1', delivery: Delivery.wide, wicket: bowledA1()),
      ]);
      expect(wide.wickets, 0);
      expect(wide.flagsFor(1).single.code, FlagCode.wicketKindNotAllowed);

      final nb = replay([
        const CricketEvent.noBall(
          1,
          'b1',
          wicket: Wicket(kind: WicketKind.caught, outBatterId: 'a1', newBatterId: 'a3'),
        ),
      ]);
      expect(nb.wickets, 0);
      expect(nb.flagsFor(1).single.code, FlagCode.wicketKindNotAllowed);
    });

    test('LBW switched off by the rules is flagged and not applied', () {
      final r = replay(
        [
          const CricketEvent.wicketBall(
            1,
            'b1',
            Wicket(kind: WicketKind.lbw, outBatterId: 'a1', newBatterId: 'a3'),
          ),
        ],
        rules: const CricketRules.tapeBall().copyWith(overs: 6, maxOversPerBowler: null),
      );
      expect(r.wickets, 0);
      expect(r.flagsFor(1).single.code, FlagCode.wicketKindNotAllowed);
    });

    test('bowled recorded against the non-striker is flagged', () {
      final r = replay([
        const CricketEvent.wicketBall(
          1,
          'b1',
          Wicket(kind: WicketKind.bowled, outBatterId: 'a2', newBatterId: 'a3'),
        ),
      ]);
      expect(r.wickets, 0);
      expect(r.flagsFor(1).single.code, FlagCode.outBatterInvalidForKind);
    });

    test('dismissed batter not at the crease is flagged and not applied', () {
      final r = replay([
        const CricketEvent.wicketBall(
          1,
          'b1',
          Wicket(kind: WicketKind.runOut, outBatterId: 'a5', newBatterId: 'a3'),
        ),
      ]);
      expect(r.wickets, 0);
      expect(r.flagsFor(1).single.code, FlagCode.outBatterNotAtCrease);
    });

    test('invalid incoming batter: flagged, survivor carries on alone', () {
      final r = replay([
        CricketEvent.wicketBall(1, 'b1', bowledA1(newBatter: 'a2')), // a2 is already batting
      ]);
      expect(r.wickets, 1);
      expect(r.flagsFor(1).single.code, FlagCode.newBatterInvalid);
      expect(r.strikerId, 'a2');
      expect(r.nonStrikerId, isNull);
    });

    test('no incoming batter chosen while others are available is flagged', () {
      final r = replay([CricketEvent.wicketBall(1, 'b1', bowledA1(newBatter: null))]);
      expect(r.flagsFor(1).single.code, FlagCode.missingNewBatter);
    });

    test('after an invalid incoming batter the survivor faces the next ball alone', () {
      final r = replay([
        const CricketEvent.wicketBall(
          1,
          'b1',
          Wicket(kind: WicketKind.runOut, outBatterId: 'a1', newBatterId: 'a2'), // a2 already in
        ),
        const CricketEvent.dot(2, 'b1'),
      ]);
      // a1 out, incoming a2 invalid (already batting) -> a2 alone, so ball 2 is faced by a2.
      expect(r.strikerId, 'a2');
      expect(r.flagsFor(2), isEmpty);
    });
  });

  group('end of innings', () {
    final threeBatters = ['a1', 'a2', 'a3'];

    test('all out: wickets == lineup-1 (no last-man-stands)', () {
      final r = replay(
        [
          CricketEvent.wicketBall(1, 'b1', bowledA1(newBatter: 'a3')),
          const CricketEvent.wicketBall(
            2,
            'b1',
            Wicket(kind: WicketKind.bowled, outBatterId: 'a3', newBatterId: null),
          ),
        ],
        setup: setupFor(batting: threeBatters),
      );
      expect(r.maxWickets, 2);
      expect(r.endReason, InningsEnd.allOut);
      expect(r.wickets, 2);
    });

    test('last-man-stands: the last batter bats on alone until the final wicket', () {
      final rules = openRules.copyWith(lastManStands: true);
      final r = replay(
        [
          CricketEvent.wicketBall(1, 'b1', bowledA1(newBatter: 'a3')),
          const CricketEvent.wicketBall(
            2,
            'b1',
            Wicket(kind: WicketKind.bowled, outBatterId: 'a3', newBatterId: null),
          ),
          const CricketEvent.bat(3, 'b1', 1), // solo batter runs: still on strike
        ],
        rules: rules,
        setup: setupFor(batting: threeBatters),
      );
      expect(r.maxWickets, 3);
      expect(r.endReason, isNull);
      expect(r.strikerId, 'a2');
      expect(r.nonStrikerId, isNull);
      expect(r.batters['a2']!.runs, 1);

      final out = replay(
        [
          CricketEvent.wicketBall(1, 'b1', bowledA1(newBatter: 'a3')),
          const CricketEvent.wicketBall(
            2,
            'b1',
            Wicket(kind: WicketKind.bowled, outBatterId: 'a3', newBatterId: null),
          ),
          const CricketEvent.wicketBall(
            3,
            'b1',
            Wicket(kind: WicketKind.bowled, outBatterId: 'a2'),
          ),
        ],
        rules: rules,
        setup: setupFor(batting: threeBatters),
      );
      expect(out.endReason, InningsEnd.allOut);
      expect(out.wickets, 3);
    });

    test('chase ends the moment the target is reached; later balls are flagged', () {
      final r = replay(
        [
          const CricketEvent.bat(1, 'b1', 4, boundary: Boundary.four),
          const CricketEvent.bat(2, 'b1', 1),
          const CricketEvent.dot(3, 'b1'),
        ],
        setup: setupFor(target: 5),
      );
      expect(r.endReason, InningsEnd.targetReached);
      expect(r.runs, 5);
      expect(r.legalBalls, 2);
      expect(r.flagsFor(3).single.code, FlagCode.ballAfterInningsEnd);
      expect(r.runsNeeded, 0);
    });

    test('reaching the target beats all-out when both happen on the same ball', () {
      final r = replay(
        [
          const CricketEvent.wicketBall(
            1,
            'b1',
            Wicket(kind: WicketKind.runOut, outBatterId: 'a1', newBatterId: null),
            runs: 2,
          ),
        ],
        setup: setupFor(batting: ['a1', 'a2'], target: 2),
      );
      expect(r.endReason, InningsEnd.targetReached);
    });

    test('admin "end innings" declares it over; later entries are flagged', () {
      final r = replay([
        const CricketEvent.dot(1, 'b1'),
        const CricketEvent.endInnings(2),
        const CricketEvent.dot(3, 'b1'),
      ]);
      expect(r.endReason, InningsEnd.declared);
      expect(r.legalBalls, 1);
      expect(r.flagsFor(3).single.code, FlagCode.ballAfterInningsEnd);
    });

    test('chase helpers: runs needed, balls left, required run rate', () {
      final r = replay(
        [const CricketEvent.bat(1, 'b1', 1), ...dots(2, 'b1', 5)],
        rules: openRules.copyWith(overs: 2),
        setup: setupFor(target: 13),
      );
      expect(r.runsNeeded, 12);
      expect(r.ballsLeft, 6);
      expect(r.requiredRunRate, 12.0);
    });
  });

  group('stats, partnerships and control events', () {
    test('balls faced: counted on a no-ball, not on a wide', () {
      final r = replay([
        const CricketEvent.wide(1, 'b1'),
        const CricketEvent.noBall(2, 'b1'),
        const CricketEvent.dot(3, 'b1'),
      ]);
      expect(r.batters['a1']!.balls, 2);
    });

    test('strike rate', () {
      final r = replay([
        const CricketEvent.bat(1, 'b1', 4, boundary: Boundary.four),
        const CricketEvent.dot(2, 'b1'),
      ]);
      expect(r.batters['a1']!.strikeRate, 200.0);
    });

    test('partnership accumulates team runs (extras included) and resets on a wicket', () {
      final r = replay([
        const CricketEvent.bat(1, 'b1', 2),
        const CricketEvent.wide(2, 'b1'),
        CricketEvent.wicketBall(3, 'b1', bowledA1()),
        const CricketEvent.bat(4, 'b1', 1),
      ]);
      expect(r.partnerships.length, 2);
      expect(r.partnerships[0].runs, 3);
      expect(r.partnerships[0].balls, 2);
      expect(r.partnerships[1].batterA, 'a3');
      expect(r.partnerships[1].runs, 1);
    });

    test('swapStrike event swaps who is on strike', () {
      final r = replay([const CricketEvent.dot(1, 'b1'), const CricketEvent.swapStrike(2)]);
      expect(r.strikerId, 'a2');
    });

    test('retire: batter is retired (not out), replacement takes the same end', () {
      final r = replay([
        const CricketEvent.dot(1, 'b1'),
        const CricketEvent.retire(seq: 2, retiredBatterId: 'a1', newBatterId: 'a3'),
      ]);
      expect(r.batters['a1']!.status, BatterStatus.retired);
      expect(r.wickets, 0);
      expect(r.strikerId, 'a3');
      expect(r.nonStrikerId, 'a2');

      final nonStriker = replay([
        const CricketEvent.retire(seq: 1, retiredBatterId: 'a2', newBatterId: 'a3'),
      ]);
      expect(nonStriker.strikerId, 'a1');
      expect(nonStriker.nonStrikerId, 'a3');
    });

    test('a retired batter can come back in for a later wicket', () {
      final r = replay([
        const CricketEvent.retire(seq: 1, retiredBatterId: 'a1', newBatterId: 'a3'),
        const CricketEvent.wicketBall(
          2,
          'b1',
          Wicket(kind: WicketKind.bowled, outBatterId: 'a3', newBatterId: 'a1'),
        ),
      ]);
      expect(r.flags, isEmpty);
      expect(r.batters['a1']!.status, BatterStatus.batting);
      expect(r.strikerId, 'a1');
    });

    test('retiring someone who isn\'t at the crease is flagged', () {
      final r = replay([const CricketEvent.retire(seq: 1, retiredBatterId: 'a6')]);
      expect(r.flagsFor(1).single.code, FlagCode.retireBatterNotAtCrease);
    });

    test('events are replayed in seq order regardless of list order', () {
      final r = replay([
        const CricketEvent.bat(2, 'b1', 1),
        const CricketEvent.bat(1, 'b1', 4, boundary: Boundary.four),
      ]);
      expect(r.balls.map((b) => b.seq), [1, 2]);
      expect(r.strikerId, 'a2');
    });

    test('openers must be two different lineup players', () {
      expect(
        () => replayInnings(
          openRules,
          const InningsSetup(
            battingLineup: ['a1', 'a2'],
            bowlingLineup: ['b1'],
            strikerId: 'a1',
            nonStrikerId: 'a1',
          ),
          const [],
        ),
        throwsArgumentError,
      );
    });
  });

  group('review flags for rule-style problems', () {
    test('bowler change mid-over is flagged on the ball with the different bowler', () {
      final r = replay([
        ...dots(1, 'b1', 3),
        const CricketEvent.dot(4, 'b2'),
      ]);
      expect(r.flagsFor(4).single.code, FlagCode.bowlerChangedMidOver);
      expect(r.flagsFor(1), isEmpty);
    });

    test('same bowler two overs running is flagged; different bowlers are fine', () {
      final bad = replay([...dots(1, 'b1', 6), ...dots(7, 'b1', 1)]);
      expect(bad.flagsFor(7).single.code, FlagCode.bowlerConsecutiveOvers);

      final ok = replay([...dots(1, 'b1', 6), ...dots(7, 'b2', 1)]);
      expect(ok.flags, isEmpty);
    });

    test('over limit: a third over for a 2-over bowler is flagged', () {
      final tape = const CricketRules.tapeBall().copyWith(overs: 6);
      final r = replay(
        [
          ...dots(1, 'b1', 6),
          ...dots(7, 'b2', 6),
          ...dots(13, 'b1', 6),
          ...dots(19, 'b2', 6),
          ...dots(25, 'b1', 1), // b1's third over
        ],
        rules: tape,
      );
      expect(r.flagsFor(25).map((f) => f.code), contains(FlagCode.bowlerOverLimit));
      expect(r.flagsFor(13), isEmpty); // second over is within the limit
    });

    test('bowler not in the bowling lineup is flagged', () {
      final r = replay([const CricketEvent.dot(1, 'zz')]);
      expect(r.flagsFor(1).single.code, FlagCode.bowlerNotInLineup);
    });

    test('byes/leg byes disabled by the rules are flagged but still applied', () {
      final r = replay(
        [const CricketEvent.legBye(1, 'b1', 1)],
        rules: openRules.copyWith(legByesAllowed: false),
      );
      expect(r.flagsFor(1).single.code, FlagCode.runTypeNotAllowed);
      expect(r.runs, 1);
    });

    test('runs without a type / negative runs are flagged and treated as 0', () {
      final r = replay([
        const CricketEvent(seq: 1, bowlerId: 'b1', runs: 3),
        const CricketEvent(seq: 2, bowlerId: 'b1', runType: RunType.bat, runs: -1),
      ]);
      expect(r.runs, 0);
      expect(r.flagsFor(1).single.code, FlagCode.invalidRuns);
      expect(r.flagsFor(2).single.code, FlagCode.invalidRuns);
    });

    test('accepting a flag clears the block but keeps the flag visible', () {
      final r = replay([
        ...dots(1, 'b1', 3),
        const CricketEvent(
          seq: 4,
          bowlerId: 'b2',
          acknowledgedFlags: {'bowlerChangedMidOver'},
        ),
      ]);
      expect(r.flagsFor(4).single.acknowledged, isTrue);
      expect(r.blockingFlags, isEmpty);
      expect(r.needsReview, isFalse);
    });
  });

  group('tokens', () {
    test('chip text for each kind of delivery', () {
      final r = replay([
        const CricketEvent.dot(1, 'b1'),
        const CricketEvent.bat(2, 'b1', 4, boundary: Boundary.four),
        const CricketEvent.bye(3, 'b1', 2),
        const CricketEvent.legBye(4, 'b1', 1),
        const CricketEvent.wide(5, 'b1', extraRuns: 4, boundary: Boundary.four),
        const CricketEvent.noBall(6, 'b1', runType: RunType.bye, runs: 1),
        const CricketEvent.noBall(7, 'b1', runType: RunType.legBye, runs: 2),
        const CricketEvent.dot(8, 'b1'),
      ]);
      expect(r.balls.map((b) => b.token),
          ['.', '4', '2b', '1lb', 'Wd+4', 'Nb+1b', 'Nb+2lb', '.']);
    });
  });
}
