import 'dart:math';

import 'package:flow_sports_app/core/cricket/auto_play.dart';
import 'package:flow_sports_app/core/cricket/cricket_event.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/cricket_toss.dart';
import 'package:flow_sports_app/core/cricket/innings_replay.dart';
import 'package:flow_sports_app/core/cricket/match_result.dart';
import 'package:flow_sports_app/core/cricket/match_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cricket_test_utils.dart';

const _rules = CricketRules(
  overs: 1,
  lastManStands: false,
  maxOversPerBowler: null,
  legByesAllowed: true,
  allowedWickets: CricketRules.allWickets,
);
const _lineupA = ['a1', 'a2', 'a3', 'a4'];
const _lineupB = ['b1', 'b2', 'b3', 'b4'];
const _toss = CricketToss(winner: 'A', elected: 'bat'); // A bats first
const _start0 = InningsStart(strikerId: 'a1', nonStrikerId: 'a2');
const _start1 = InningsStart(strikerId: 'b1', nonStrikerId: 'b2');

MatchScoringState derive({
  CricketToss? toss = _toss,
  List<InningsStart> starts = const [],
  List<LoggedEvent> events = const [],
  List<String> lineupA = _lineupA,
  List<String> lineupB = _lineupB,
  CricketRules rules = _rules,
}) =>
    deriveMatchState(
      rules: rules,
      lineupA: lineupA,
      lineupB: lineupB,
      toss: toss,
      starts: starts,
      events: events,
      nameA: 'Reds',
      nameB: 'Blues',
    );

List<LoggedEvent> inn(int innings, List<CricketEvent> events) => [for (final e in events) LoggedEvent(innings, e)];

/// One over (6 legal balls) by [bowler] scoring [runsPerBall] off each ball.
List<CricketEvent> over(int startSeq, String bowler, int runsPerBall) => [
      for (var i = 0; i < 6; i++)
        runsPerBall == 0 ? CricketEvent.dot(startSeq + i, bowler) : CricketEvent.bat(startSeq + i, bowler, runsPerBall),
    ];

void main() {
  group('match phases', () {
    test('no toss or small squads: setup is incomplete', () {
      expect(derive(toss: null).phase, ScoringPhase.needsSetup);
      expect(derive(lineupA: const ['a1']).phase, ScoringPhase.needsSetup);
      expect(derive(lineupB: const []).phase, ScoringPhase.needsSetup);
    });

    test('ready but no innings yet → waiting for the first openers', () {
      final s = derive();
      expect(s.phase, ScoringPhase.awaitingInnings);
      expect(s.nextInningsIndex, 0);
    });

    test('an innings in progress is scoring, batting side comes from the toss', () {
      final s = derive(starts: [_start0], events: inn(0, [CricketEvent.dot(1, 'b1')]));
      expect(s.phase, ScoringPhase.scoring);
      expect(s.current!.battingSide, 'A');
      expect(s.current!.result.legalBalls, 1);
    });

    test('toss: B chose to bat → B bats first', () {
      final s = derive(
        toss: const CricketToss(winner: 'A', elected: 'bowl'),
        starts: [const InningsStart(strikerId: 'b1', nonStrikerId: 'b2')],
      );
      expect(s.current!.battingSide, 'B');
    });

    test('first innings over → break, then the second needs openers', () {
      final s = derive(starts: [_start0], events: inn(0, over(1, 'b1', 1)));
      expect(s.phase, ScoringPhase.awaitingInnings);
      expect(s.nextInningsIndex, 1);
      expect(s.innings.single.result.endReason, InningsEnd.oversDone);
    });

    test('target for the chase = first innings + 1, derived from the log', () {
      final s = derive(
        starts: [_start0, _start1],
        events: inn(0, over(1, 'b1', 2)) + inn(1, [CricketEvent.dot(7, 'a1')]),
      );
      expect(s.innings[0].result.runs, 12);
      expect(s.innings[1].result.setup.target, 13);
      expect(s.phase, ScoringPhase.scoring);
    });

    test('chase finished: result text and runs per side', () {
      final s = derive(
        starts: [_start0, _start1],
        events: inn(0, over(1, 'b1', 1)) + inn(1, over(7, 'a1', 2)),
      );
      expect(s.phase, ScoringPhase.finished);
      expect(s.result!.winner, CricketWinner.teamB);
      expect(s.result!.text, startsWith('Blues won by'));
      expect(s.runsFor('A'), 6);
      expect(s.runsFor('B'), anyOf(7, 8));
    });

    test('defending side wins when the chase falls short', () {
      final s = derive(
        starts: [_start0, _start1],
        events: inn(0, over(1, 'b1', 2)) + inn(1, over(7, 'a1', 1)),
      );
      expect(s.result!.winner, CricketWinner.teamA);
      expect(s.result!.text, 'Reds won by 6 runs');
    });

    test('equal scores tie', () {
      final s = derive(
        starts: [_start0, _start1],
        events: inn(0, over(1, 'b1', 1)) + inn(1, over(7, 'a1', 1)),
      );
      expect(s.result!.winner, CricketWinner.tie);
    });

    test('editing a first-innings ball changes the second innings target automatically', () {
      final first = over(1, 'b1', 1);
      final events = inn(0, first) + inn(1, [CricketEvent.dot(7, 'a1')]);
      final before = derive(starts: [_start0, _start1], events: events);
      expect(before.innings[1].result.setup.target, 7);

      final edited = inn(0, editEvent(first, 1, CricketEvent.bat(1, 'b1', 4, boundary: Boundary.four))) +
          inn(1, [CricketEvent.dot(7, 'a1')]);
      final after = derive(starts: [_start0, _start1], events: edited);
      expect(after.innings[1].result.setup.target, 10);
    });

    test('openers missing from the squad → broken, not a crash', () {
      final s = derive(
        starts: [const InningsStart(strikerId: 'zz', nonStrikerId: 'a2')],
      );
      expect(s.phase, ScoringPhase.broken);
      expect(s.problem, isNotNull);
    });

    test('flags from any innings block saving', () {
      // wide then bowler change mid-over → bowlerChangedMidOver flag
      final s = derive(starts: [_start0], events: inn(0, [CricketEvent.dot(1, 'b1'), CricketEvent.dot(2, 'b2')]));
      expect(s.hasBlockingFlags, isTrue);
    });
  });

  group('bowler choice', () {
    test('a fresh innings, and the ball after an over, need a bowler', () {
      final fresh = derive(starts: [_start0]).current!.result;
      expect(needsNewBowler(fresh), isTrue);

      final midOver = derive(starts: [_start0], events: inn(0, [CricketEvent.dot(1, 'b1')])).current!.result;
      expect(needsNewBowler(midOver), isFalse);

      final rules2 = _rules.copyWith(overs: 3);
      final afterOver = derive(rules: rules2, starts: [_start0], events: inn(0, over(1, 'b1', 1))).current!.result;
      expect(needsNewBowler(afterOver), isTrue);
    });

    test('a wide opening the new over means the bowler was already picked', () {
      final rules2 = _rules.copyWith(overs: 3);
      final r = derive(
        rules: rules2,
        starts: [_start0],
        events: inn(0, [...over(1, 'b1', 1), CricketEvent.wide(7, 'b2')]),
      ).current!.result;
      expect(needsNewBowler(r), isFalse);
      expect(r.currentBowlerId, 'b2');
    });

    test('a dead ball is re-bowled by the same bowler', () {
      final r = derive(
        starts: [_start0],
        events: inn(0, [const CricketEvent(seq: 1, bowlerId: 'b1', delivery: Delivery.deadBall)]),
      ).current!.result;
      expect(needsNewBowler(r), isFalse);
      expect(r.currentBowlerId, 'b1');
    });

    test('warns about the same bowler twice in a row and a bowler over the limit', () {
      final rules2 = _rules.copyWith(overs: 4, maxOversPerBowler: 1);
      final r = derive(
        rules: rules2,
        starts: [_start0],
        events: inn(0, [...over(1, 'b1', 0), ...over(7, 'b2', 0)]),
      ).current!.result;
      final byId = {for (final c in bowlerChoices(r)) c.id: c};
      expect(byId['b2']!.issue, BowlerIssue.justBowled);
      expect(byId['b1']!.issue, BowlerIssue.overLimit);
      expect(byId['b3']!.issue, BowlerIssue.none);
      expect(byId['b1']!.oversText, '1.0');
    });

    test('available batters exclude the two at the crease and anyone out', () {
      final r = derive(
        starts: [_start0],
        events: inn(0, [
          CricketEvent.wicketBall(1, 'b1', const Wicket(kind: WicketKind.bowled, outBatterId: 'a1', newBatterId: 'a3')),
        ]),
      ).current!.result;
      expect(availableBatters(r), ['a4']);
    });
  });

  group('scoredBall', () {
    test('dot, bat runs and boundaries', () {
      expect(scoredBall(seq: 1, bowlerId: 'b1', rules: _rules).runType, RunType.none);
      final single = scoredBall(seq: 1, bowlerId: 'b1', rules: _rules, runsTapped: 1);
      expect([single.runType, single.runs, single.boundary], [RunType.bat, 1, Boundary.none]);
      final four = scoredBall(seq: 1, bowlerId: 'b1', rules: _rules, runsTapped: 4);
      expect([four.runType, four.runs, four.boundary], [RunType.bat, 4, Boundary.four]);
      final six = scoredBall(seq: 1, bowlerId: 'b1', rules: _rules, runsTapped: 6);
      expect([six.runs, six.boundary], [6, Boundary.six]);
    });

    test('boundary values follow the rules', () {
      final r = _rules.copyWith(boundaryFour: 3, boundarySix: 5);
      expect(scoredBall(seq: 1, bowlerId: 'b', rules: r, runsTapped: 4).runs, 3);
      expect(scoredBall(seq: 1, bowlerId: 'b', rules: r, runsTapped: 6).runs, 5);
    });

    test('wide + 4 is wide extras, never off the bat', () {
      final e = scoredBall(seq: 1, bowlerId: 'b1', rules: _rules, delivery: Delivery.wide, extra: RunType.bye, runsTapped: 4);
      expect([e.delivery, e.runType, e.runs, e.boundary], [Delivery.wide, RunType.none, 4, Boundary.four]);
    });

    test('no-ball + bat runs, and no-ball + bye', () {
      final bat = scoredBall(seq: 1, bowlerId: 'b1', rules: _rules, delivery: Delivery.noBall, runsTapped: 1);
      expect([bat.runType, bat.runs], [RunType.bat, 1]);
      final bye = scoredBall(
          seq: 1, bowlerId: 'b1', rules: _rules, delivery: Delivery.noBall, extra: RunType.bye, runsTapped: 1);
      expect([bye.runType, bye.runs], [RunType.bye, 1]);
    });

    test('bye 4 is a boundary of extras; bye with 0 runs is just a dot', () {
      final e = scoredBall(seq: 1, bowlerId: 'b1', rules: _rules, extra: RunType.bye, runsTapped: 4);
      expect([e.runType, e.runs, e.boundary], [RunType.bye, 4, Boundary.four]);
      expect(scoredBall(seq: 1, bowlerId: 'b1', rules: _rules, extra: RunType.legBye).runType, RunType.none);
    });

    test('the replay agrees with what the buttons mean', () {
      final r = derive(
        starts: [_start0],
        events: inn(0, [
          scoredBall(seq: 1, bowlerId: 'b1', rules: _rules, delivery: Delivery.wide, runsTapped: 4),
          scoredBall(seq: 2, bowlerId: 'b1', rules: _rules, delivery: Delivery.noBall, runsTapped: 6),
        ]),
      ).current!.result;
      expect(r.runs, 5 + 7);
      expect(r.legalBalls, 0);
      expect(r.freeHitNext, isTrue);
    });

    test('nextSeq continues across innings', () {
      expect(nextSeq(const []), 1);
      expect(nextSeq([...inn(0, over(1, 'b1', 1)), ...inn(1, [CricketEvent.dot(7, 'a1')])]), 8);
    });
  });

  group('what is written to the match doc', () {
    String name(String id) => id;

    Map<String, dynamic> summary(MatchScoringState s, List<InningsStart> starts) => summaryFields(
          state: s,
          starts: starts,
          nameOf: name,
          nameA: 'Reds',
          nameB: 'Blues',
          rules: _rules,
        );

    test('live innings: score line, live block, latest commentary', () {
      final s = derive(starts: [_start0], events: inn(0, [CricketEvent.bat(1, 'b1', 1)]));
      final m = summary(s, [_start0]);
      expect(m['summaryText'], 'Reds 1/0 (0.1 ov)');
      expect(m['scoreA'], 1);
      expect(m['scoreB'], 0);
      expect((m['live'] as Map)['strikerId'], 'a2'); // single swapped the strike
      expect((m['live'] as Map)['bowlerId'], 'b1');
      expect(m['lastCommentaryText'], contains('b1 to a1'));
      final innings = m['innings'] as List;
      expect((innings.single as Map)['runs'], 1);
      expect((innings.single as Map)['ended'], false);
    });

    test('chase line shows what is needed', () {
      final s = derive(
        starts: [_start0, _start1],
        events: inn(0, over(1, 'b1', 1)) + inn(1, [CricketEvent.dot(7, 'a1')]),
      );
      expect(summary(s, [_start0, _start1])['summaryText'], 'Blues 0/0 (0.1 ov) · Blues need 7 runs in 5 balls');
    });

    test('innings break and a finished match', () {
      final brk = derive(starts: [_start0], events: inn(0, over(1, 'b1', 1)));
      expect(summary(brk, [_start0])['summaryText'], 'Reds 6/0 (1.0 ov) · Blues to bat');
      expect(summary(brk, [_start0])['live'], isNull);

      final done = derive(
        starts: [_start0, _start1],
        events: inn(0, over(1, 'b1', 2)) + inn(1, over(7, 'a1', 1)),
      );
      final m = summary(done, [_start0, _start1]);
      expect(m['summaryText'], 'Reds won by 6 runs');
      expect((m['innings'] as List).length, 2);
      final f = resultFields(done);
      expect(f['result'], 'teamA');
      expect(f['status'], 'completed');
      expect([f['scoreA'], f['scoreB']], [12, 6]);
      expect(f['resultText'], 'Reds won by 6 runs');
    });

    test('an all-out innings is recorded as all out (for net run rate)', () {
      final rules = _rules.copyWith(overs: 5);
      final outs = [
        CricketEvent.wicketBall(1, 'b1', const Wicket(kind: WicketKind.bowled, outBatterId: 'a1', newBatterId: 'a3')),
        CricketEvent.wicketBall(2, 'b1', const Wicket(kind: WicketKind.bowled, outBatterId: 'a3', newBatterId: 'a4')),
        CricketEvent.wicketBall(3, 'b1', const Wicket(kind: WicketKind.bowled, outBatterId: 'a4')),
      ];
      final s = deriveMatchState(
        rules: rules,
        lineupA: _lineupA,
        lineupB: _lineupB,
        toss: _toss,
        starts: [_start0],
        events: inn(0, outs),
        nameA: 'Reds',
        nameB: 'Blues',
      );
      final rec = InningsRecord.fromMap(
          (summaryFields(state: s, starts: [_start0], nameOf: name, nameA: 'Reds', nameB: 'Blues', rules: rules)['innings'] as List)
              .single as Map<String, dynamic>);
      expect(rec.allOut, isTrue);
      expect(rec.ended, isTrue);
      expect(rec.wickets, 3);
      expect(rec.legalBalls, 3);
    });
  });

  group('stored shapes', () {
    test('LoggedEvent round-trips with its innings', () {
      const e = LoggedEvent(1, CricketEvent(seq: 9, bowlerId: 'b1', runType: RunType.bat, runs: 4, boundary: Boundary.four));
      final back = LoggedEvent.fromMap(e.toMap());
      expect(back.innings, 1);
      expect(back.event, e.event);
    });

    test('InningsRecord round-trips', () {
      const r = InningsRecord(
        batting: 'B',
        start: InningsStart(strikerId: 'x', nonStrikerId: 'y', maxOvers: 3),
        runs: 40,
        wickets: 2,
        legalBalls: 17,
        ended: true,
        allOut: false,
      );
      final back = InningsRecord.fromMap(r.toMap());
      expect([back.batting, back.start.strikerId, back.start.nonStrikerId, back.start.maxOvers], ['B', 'x', 'y', 3]);
      expect([back.runs, back.wickets, back.legalBalls, back.ended, back.allOut], [40, 2, 17, true, false]);
    });
  });

  group('auto-play (Test Lab)', () {
    for (final rules in [
      const CricketRules.tapeBall().copyWith(overs: 4),
      const CricketRules.t20().copyWith(overs: 5),
      const CricketRules.tapeBall().copyWith(overs: 3, lastManStands: false, squadSize: 5),
    ]) {
      test('every simulated match is clean and finished (${rules.overs} ov, last-man ${rules.lastManStands})', () {
        final a = [for (var i = 1; i <= 8; i++) 'a$i'];
        final b = [for (var i = 1; i <= 6; i++) 'b$i'];
        for (var seed = 0; seed < 40; seed++) {
          final sim = simulateMatch(
            rules: rules,
            lineupA: a,
            lineupB: b,
            battingFirst: seed.isEven ? 'A' : 'B',
            random: Random(seed),
          );
          final s = deriveMatchState(
            rules: rules,
            lineupA: a,
            lineupB: b,
            toss: CricketToss(winner: seed.isEven ? 'A' : 'B', elected: 'bat'),
            starts: sim.starts,
            events: sim.events,
            nameA: 'A',
            nameB: 'B',
          );
          expect(s.phase, ScoringPhase.finished, reason: 'seed $seed');
          expect(s.blockingFlags, isEmpty, reason: 'seed $seed: ${s.blockingFlags}');
          expect(s.result, isNotNull);
          for (final v in s.innings) {
            expectInvariants(v.result);
          }
          // seq numbers are unique and continue across innings
          final seqs = sim.events.map((e) => e.seq).toList();
          expect(seqs.toSet().length, seqs.length);
        }
      });
    }

    test('a log that is deliberately damaged is caught as a flag (sanity check on the check)', () {
      final a = [for (var i = 1; i <= 8; i++) 'a$i'];
      final b = [for (var i = 1; i <= 6; i++) 'b$i'];
      final sim = simulateMatch(rules: const CricketRules.tapeBall(), lineupA: a, lineupB: b, battingFirst: 'A', random: Random(3));
      final damaged = [...sim.events.where((e) => e.innings == 0), const LoggedEvent(0, CricketEvent(seq: 9999, bowlerId: 'nobody'))];
      final s = deriveMatchState(
        rules: const CricketRules.tapeBall(),
        lineupA: a,
        lineupB: b,
        toss: _toss,
        starts: [sim.starts[0]],
        events: damaged,
        nameA: 'A',
        nameB: 'B',
      );
      expect(s.hasBlockingFlags, isTrue);
    });
  });
}
