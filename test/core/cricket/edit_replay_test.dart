import 'dart:math';

import 'package:flow_sports_app/core/cricket/cricket_event.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/innings_replay.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cricket_test_utils.dart';

/// Ball 1: 0, Ball 2: 4 (boundary), Ball 3: 2, Ball 4: 1, Ball 5: 0, Ball 6: 4.
List<CricketEvent> sixBallOver() => const [
      CricketEvent.dot(1, 'b1'),
      CricketEvent.bat(2, 'b1', 4, boundary: Boundary.four),
      CricketEvent.bat(3, 'b1', 2),
      CricketEvent.bat(4, 'b1', 1),
      CricketEvent.dot(5, 'b1'),
      CricketEvent.bat(6, 'b1', 4, boundary: Boundary.four),
    ];

List<String?> strikers(InningsResult r) => r.balls.map((b) => b.strikerId).toList();

void main() {
  group('editing a recorded ball (the 0,4,2,1,0,4 scenario)', () {
    test('before the edit: total 11', () {
      final r = replay(sixBallOver());
      expect(r.runs, 11);
      expect(strikers(r), ['a1', 'a1', 'a1', 'a1', 'a2', 'a2']);
      expect(r.batters['a1']!.runs, 7);
      expect(r.batters['a1']!.balls, 4);
      expect(r.batters['a2']!.runs, 4);
      expect(r.batters['a2']!.balls, 2);
      expectInvariants(r);
    });

    test('edit ball 2 from 4 to 1: total 8, later inputs untouched, strikers re-derived', () {
      final original = sixBallOver();
      final edited = editEvent(original, 2, const CricketEvent.bat(2, 'b1', 1));

      // Balls 3-6 keep their original recorded inputs, exactly.
      for (final seq in [3, 4, 5, 6]) {
        expect(edited.firstWhere((e) => e.seq == seq), original.firstWhere((e) => e.seq == seq));
      }
      expect(edited.firstWhere((e) => e.seq == 1), original.first);

      final r = replay(edited);
      expect(r.runs, 8);
      // The single on ball 2 now swaps the strike, flipping everyone after it.
      expect(strikers(r), ['a1', 'a1', 'a2', 'a2', 'a1', 'a1']);
      // Per-ball team runs for 3-6 are unchanged.
      expect(r.balls.map((b) => b.teamRuns), [0, 1, 2, 1, 0, 4]);
      // Batter totals re-attributed.
      expect(r.batters['a1']!.runs, 5);
      expect(r.batters['a1']!.balls, 4);
      expect(r.batters['a2']!.runs, 3);
      expect(r.batters['a2']!.balls, 2);
      expect(r.flags, isEmpty);
      expect(r.legalBalls, 6);
      expectInvariants(r);
      // After the over, the ends swap: a2 is on strike next.
      expect(r.strikerId, 'a2');
    });

    test('the original log list itself is never mutated by an edit', () {
      final original = sixBallOver();
      final snapshot = [...original];
      editEvent(original, 2, const CricketEvent.bat(2, 'b1', 1));
      expect(original, snapshot);
    });

    test('1 -> Wide: no strike change, one fewer legal ball, over ends later', () {
      final log = [
        const CricketEvent.dot(1, 'b1'),
        const CricketEvent.bat(2, 'b1', 1),
        const CricketEvent.dot(3, 'b1'),
        const CricketEvent.dot(4, 'b1'),
        const CricketEvent.dot(5, 'b1'),
        const CricketEvent.dot(6, 'b1'),
      ];
      final before = replay(log);
      expect(before.legalBalls, 6);
      expect(before.overs.single.complete, isTrue);

      final after = replay(editEvent(log, 2, const CricketEvent.wide(2, 'b1')));
      expect(after.legalBalls, 5);
      expect(after.overs.single.complete, isFalse);
      expect(after.runs, 1); // 1 wide, not "a normal single" off the bat
      expect(after.batters['a1']!.runs, 0);
      expect(after.batters['a1']!.balls, 5); // balls 1,3,4,5,6 — the wide is not faced
      // No swap from the wide: a1 faces every counted ball.
      expect(strikers(after), ['a1', 'a1', 'a1', 'a1', 'a1', 'a1']);
      // Ball numbering of later balls shifts down by one.
      expect(before.balls[2].ballInOver, 3);
      expect(after.balls[2].ballInOver, 2);
      expectInvariants(after);
    });

    test('Wide -> 1 run: one more legal ball, swap, over ends a ball earlier', () {
      final log = [
        const CricketEvent.dot(1, 'b1'),
        const CricketEvent.wide(2, 'b1'),
        const CricketEvent.dot(3, 'b1'),
        const CricketEvent.dot(4, 'b1'),
        const CricketEvent.dot(5, 'b1'),
        const CricketEvent.dot(6, 'b1'),
      ];
      expect(replay(log).overs.single.complete, isFalse);

      final after = replay(editEvent(log, 2, const CricketEvent.bat(2, 'b1', 1)));
      expect(after.legalBalls, 6);
      expect(after.overs.single.complete, isTrue);
      expect(after.batters['a1']!.runs, 1);
      expect(after.batters['a1']!.balls, 2);
      expect(strikers(after), ['a1', 'a1', 'a2', 'a2', 'a2', 'a2']);
      expectInvariants(after);
    });

    test('4 -> Wide shifts the over boundary: the next over\'s bowler is now mid-over', () {
      final log = [
        ...dots(1, 'b1', 1),
        const CricketEvent.bat(2, 'b1', 4, boundary: Boundary.four),
        ...dots(3, 'b1', 4), // seq 3..6 -> first over complete after seq 6
        ...dots(7, 'b2', 6), // second over by b2
      ];
      expect(replay(log).flags, isEmpty);

      final after = replay(editEvent(log, 2, const CricketEvent.wide(2, 'b1')));
      // Over 1 now needs seq 7 as its 6th counted ball, which b2 bowled.
      expect(after.flagsFor(7).map((f) => f.code), [FlagCode.bowlerChangedMidOver]);
      expect(after.flagsFor(2), isEmpty);
    });

    test('editing an earlier ball into a no-ball makes the next ball a free hit and flags a bowled wicket on it',
        () {
      final log = [
        const CricketEvent.dot(1, 'b1'),
        const CricketEvent.dot(2, 'b1'),
        CricketEvent.wicketBall(3, 'b1', bowledA1()),
      ];
      expect(replay(log).wickets, 1);

      final edited = editEvent(log, 2, const CricketEvent.noBall(2, 'b1'));
      final after = replay(edited);
      expect(after.wickets, 0);
      expect(after.flagsFor(3).single.code, FlagCode.wicketKindNotAllowed);
      // The wicket ball itself is untouched in storage.
      expect(edited[2], log[2]);
      expect(after.blockingFlags, isNotEmpty);
    });

    test('editing a dot into a wicket flags a later wicket for the same batter', () {
      final log = [
        const CricketEvent.dot(1, 'b1'),
        const CricketEvent.dot(2, 'b1'),
        const CricketEvent.dot(3, 'b1'),
        CricketEvent.wicketBall(4, 'b1', bowledA1()), // a1 out here originally
      ];
      expect(replay(log).flags, isEmpty);

      final edited = editEvent(log, 2, CricketEvent.wicketBall(2, 'b1', bowledA1()));
      final after = replay(edited);
      // a1 already went out on ball 2, so ball 4's dismissal of a1 is invalid.
      expect(after.wickets, 1);
      expect(after.flagsFor(4).single.code, FlagCode.outBatterNotAtCrease);
      expect(edited[3], log[3]); // stored input byte-identical
    });

    test('removing a wicket flags a later dismissal of the batter who came in for it', () {
      final log = [
        CricketEvent.wicketBall(1, 'b1', bowledA1(newBatter: 'a3')),
        const CricketEvent.dot(2, 'b1'),
        const CricketEvent.wicketBall(
          3,
          'b1',
          Wicket(kind: WicketKind.bowled, outBatterId: 'a3', newBatterId: 'a4'),
        ),
      ];
      expect(replay(log).flags, isEmpty);

      final after = replay(editEvent(log, 1, const CricketEvent.dot(1, 'b1')));
      expect(after.wickets, 0);
      expect(after.flagsFor(3).single.code, FlagCode.outBatterNotAtCrease);
    });

    test('an edit that ends the innings early flags later balls but deletes none', () {
      final log = [
        ...dots(1, 'b1', 4),
      ];
      final edited = editEvent(
        log,
        1,
        const CricketEvent.bat(1, 'b1', 4, boundary: Boundary.four),
      );
      final after = replay(edited, setup: setupFor(target: 3));
      expect(after.endReason, InningsEnd.targetReached);
      expect(after.flags.map((f) => f.seq), [2, 3, 4]);
      expect(after.flags.every((f) => f.code == FlagCode.ballAfterInningsEnd), isTrue);
      expect(edited.length, 4); // nothing was removed from the log
    });

    test('accepting every flag unblocks saving the result', () {
      final log = [
        const CricketEvent.dot(1, 'b1'),
        const CricketEvent.dot(2, 'b1'),
        CricketEvent.wicketBall(3, 'b1', bowledA1()),
      ];
      final edited = editEvent(log, 2, const CricketEvent.noBall(2, 'b1'));
      expect(replay(edited).needsReview, isTrue);

      final accepted = editEvent(
        edited,
        3,
        edited[2].copyWith(acknowledgedFlags: {FlagCode.wicketKindNotAllowed.name}),
      );
      final r = replay(accepted);
      expect(r.flagsFor(3).single.acknowledged, isTrue);
      expect(r.needsReview, isFalse);
    });

    test('undo of the last ball == replaying the log without it', () {
      final log = sixBallOver();
      final undone = replay(undoLast(log));
      final prefix = replay(log.sublist(0, 5));
      expect(undone.runs, prefix.runs);
      expect(undone.legalBalls, 5);
      expect(undone.strikerId, prefix.strikerId);
      expect(undoLast(<CricketEvent>[]), isEmpty);
    });

    test('deleting a middle ball keeps the others and re-derives everything', () {
      final log = sixBallOver();
      final after = replay(deleteEvent(log, 4)); // drop the single
      expect(after.runs, 10);
      expect(after.legalBalls, 5);
      // No swap from the removed single: a1 faces balls 1-5.
      expect(strikers(after), ['a1', 'a1', 'a1', 'a1', 'a1']);
    });

    test('editing a seq that does not exist is an error', () {
      expect(() => editEvent(sixBallOver(), 99, const CricketEvent.dot(99, 'b1')),
          throwsArgumentError);
    });

    test('a completed-innings edit changes the final numbers the result is built from', () {
      // 2-ball "innings": ball 1 four, ball 2 single -> 5 runs.
      final rules = openRules.copyWith(overs: 1, ballsPerOver: 2);
      final log = [
        const CricketEvent.bat(1, 'b1', 4, boundary: Boundary.four),
        const CricketEvent.bat(2, 'b1', 1),
      ];
      expect(replay(log, rules: rules).runs, 5);
      final fixed = editEvent(log, 1, const CricketEvent.bat(1, 'b1', 1)); // it was a single
      final after = replay(fixed, rules: rules);
      expect(after.runs, 2);
      expect(after.endReason, InningsEnd.oversDone);
    });
  });

  group('randomised logs', () {
    // Builds a valid-looking event by looking at the *current* replayed
    // state, so wickets name real batters and bowlers rotate legally.
    CricketEvent nextEvent(Random rnd, int seq, InningsResult r) {
      final bowler = 'b${1 + (r.legalBalls ~/ 6) % 3}';
      final roll = rnd.nextInt(100);
      if (roll < 3) return CricketEvent.swapStrike(seq);

      Wicket? wicket() {
        final striker = r.strikerId;
        final non = r.nonStrikerId;
        if (striker == null) return null;
        final restricted = r.freeHitNext;
        final kinds = restricted
            ? [WicketKind.runOut]
            : [WicketKind.bowled, WicketKind.caught, WicketKind.runOut];
        final kind = kinds[rnd.nextInt(kinds.length)];
        final out = kind == WicketKind.runOut && non != null && rnd.nextBool() ? non : striker;
        String? fresh;
        for (final b in r.batters.values) {
          if (b.status == BatterStatus.yetToBat) {
            fresh = b.id;
            break;
          }
        }
        return Wicket(
          kind: kind,
          outBatterId: out,
          newBatterId: fresh,
          newBatterEnd: NewBatterEnd.values[rnd.nextInt(2)],
        );
      }

      if (roll < 13) {
        final w = wicket();
        if (w != null) return CricketEvent.wicketBall(seq, bowler, w, runs: rnd.nextInt(2));
      }
      if (roll < 22) {
        final boundary = rnd.nextInt(4) == 0;
        return CricketEvent.wide(seq, bowler,
            extraRuns: boundary ? 4 : rnd.nextInt(3),
            boundary: boundary ? Boundary.four : Boundary.none);
      }
      if (roll < 30) {
        return rnd.nextBool()
            ? CricketEvent.noBall(seq, bowler)
            : CricketEvent.noBall(seq, bowler, runType: RunType.bat, runs: 1 + rnd.nextInt(3));
      }
      if (roll < 32) {
        return CricketEvent(seq: seq, bowlerId: bowler, delivery: Delivery.deadBall);
      }
      if (roll < 40) return CricketEvent.bye(seq, bowler, 1 + rnd.nextInt(2));
      if (roll < 46) return CricketEvent.legBye(seq, bowler, 1);
      if (roll < 54) {
        return rnd.nextBool()
            ? CricketEvent.bat(seq, bowler, 4, boundary: Boundary.four)
            : CricketEvent.bat(seq, bowler, 6, boundary: Boundary.six);
      }
      if (roll < 85) return CricketEvent.bat(seq, bowler, rnd.nextInt(4));
      return CricketEvent.dot(seq, bowler);
    }

    List<CricketEvent> randomLog(Random rnd, {int maxEvents = 60}) {
      final log = <CricketEvent>[];
      var r = replay(log);
      for (var seq = 1; seq <= maxEvents && !r.isEnded; seq++) {
        log.add(nextEvent(rnd, seq, r));
        r = replay(log);
      }
      return log;
    }

    test('invariants hold and no flags appear for 300 random valid innings', () {
      final rnd = Random(2026);
      for (var i = 0; i < 300; i++) {
        final log = randomLog(rnd);
        final r = replay(log);
        expectInvariants(r);
        expect(r.flags, isEmpty, reason: 'log #$i produced flags: ${r.flags}');
      }
    });

    test('editing any ball leaves every other stored input identical and still replays cleanly',
        () {
      final rnd = Random(7);
      for (var i = 0; i < 150; i++) {
        final log = randomLog(rnd, maxEvents: 40);
        if (log.length < 2) continue;
        final k = rnd.nextInt(log.length);
        final target = log[k];
        if (target.kind != EventKind.ball || target.delivery != Delivery.legal) continue;
        if (target.wicket != null) continue;

        final replacement = target.copyWith(
          runType: RunType.bat,
          runs: rnd.nextInt(4),
          boundary: Boundary.none,
        );
        final edited = editEvent(log, target.seq, replacement);

        for (var j = 0; j < log.length; j++) {
          if (j != k) expect(edited[j], log[j]);
        }
        final r = replay(edited);
        // An edit may legitimately produce review flags, but replay never throws
        // and totals stay internally consistent for whatever was applied.
        if (r.flags.isEmpty) expectInvariants(r);

        // Replaying a freshly rebuilt copy of the same inputs (via the map
        // form that Firestore stores) gives the identical derived state.
        final fresh = replay([for (final e in edited) CricketEvent.fromMap(e.toMap())]);
        expect(fresh.runs, r.runs);
        expect(fresh.wickets, r.wickets);
        expect(fresh.legalBalls, r.legalBalls);
        expect(fresh.strikerId, r.strikerId);
        expect(fresh.nonStrikerId, r.nonStrikerId);
        expect(fresh.freeHitNext, r.freeHitNext);
        expect(fresh.flags.length, r.flags.length);
      }
    });

    test('undoLast at every step equals replaying the shorter log', () {
      final rnd = Random(99);
      for (var i = 0; i < 50; i++) {
        final log = randomLog(rnd, maxEvents: 30);
        if (log.isEmpty) continue;
        final a = replay(undoLast(log));
        final b = replay(log.sublist(0, log.length - 1));
        expect(a.runs, b.runs);
        expect(a.strikerId, b.strikerId);
        expect(a.legalBalls, b.legalBalls);
      }
    });
  });
}
