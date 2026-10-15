import 'dart:math';

import 'package:flow_sports_app/core/cricket/auto_play.dart';
import 'package:flow_sports_app/core/cricket/cricket_event.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/cricket_toss.dart';
import 'package:flow_sports_app/core/cricket/innings_replay.dart';
import 'package:flow_sports_app/core/cricket/match_display.dart';
import 'package:flow_sports_app/core/cricket/match_result.dart';
import 'package:flow_sports_app/core/cricket/match_scoring.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flutter_test/flutter_test.dart';

// A tied knockout match goes to a super over: 1 over each, 2 wickets, the side
// that batted second in the match bats first, and it repeats while level.

const _rules = CricketRules(
  overs: 1,
  lastManStands: false,
  maxOversPerBowler: null,
  allowedWickets: CricketRules.allWickets,
);
const _lineupA = ['a1', 'a2', 'a3', 'a4'];
const _lineupB = ['b1', 'b2', 'b3', 'b4'];
const _toss = CricketToss(winner: 'A', elected: 'bat'); // A bats first, B second

const _openA = InningsStart(strikerId: 'a1', nonStrikerId: 'a2');
const _openB = InningsStart(strikerId: 'b1', nonStrikerId: 'b2');

/// One over of [runs] by [bowler] in [innings], numbered from [seq].
List<LoggedEvent> over(int innings, int seq, String bowler, List<int> runs) => [
      for (var i = 0; i < runs.length; i++)
        LoggedEvent(
          innings,
          runs[i] == 0
              ? CricketEvent.dot(seq + i, bowler)
              : CricketEvent.bat(
                  seq + i,
                  bowler,
                  runs[i],
                  boundary: runs[i] == 4
                      ? Boundary.four
                      : runs[i] == 6
                          ? Boundary.six
                          : Boundary.none,
                ),
        ),
    ];

/// Both main innings level at 6 — A bat 6 singles, B chase 6 singles.
List<LoggedEvent> tiedMain() => [
      ...over(0, 1, 'b1', [1, 1, 1, 1, 1, 1]),
      ...over(1, 7, 'a1', [1, 1, 1, 1, 1, 1]),
    ];

MatchScoringState derive({
  required List<InningsStart> starts,
  required List<LoggedEvent> events,
  bool knockout = true,
  String? tieDecision,
  CricketRules rules = _rules,
}) =>
    deriveMatchState(
      rules: rules,
      lineupA: _lineupA,
      lineupB: _lineupB,
      toss: _toss,
      starts: starts,
      events: events,
      nameA: 'Reds',
      nameB: 'Blues',
      knockout: knockout,
      tieDecision: tieDecision,
    );

void main() {
  group('who bats when', () {
    test('main innings follow the toss; the super over opens with the side that batted second', () {
      expect([for (var i = 0; i < 6; i++) battingSideForInnings('A', i)], ['A', 'B', 'B', 'A', 'A', 'B']);
      expect([for (var i = 0; i < 6; i++) battingSideForInnings('B', i)], ['B', 'A', 'A', 'B', 'B', 'A']);
    });
  });

  group('a tied match', () {
    test('a tied knockout waits for a super over instead of finishing', () {
      final s = derive(starts: [_openA, _openB], events: tiedMain());
      expect(s.phase, ScoringPhase.awaitingInnings);
      expect(s.nextInningsIndex, 2);
      expect(s.superOverNext, isTrue);
      expect(s.result, isNull);
    });

    test('a tied LEAGUE match is still just a tie', () {
      final s = derive(starts: [_openA, _openB], events: tiedMain(), knockout: false);
      expect(s.phase, ScoringPhase.finished);
      expect(s.result!.winner, CricketWinner.tie);
    });

    test('with super overs switched off a tied knockout finishes as a tie (the admin must pick)', () {
      final s = derive(
        starts: [_openA, _openB],
        events: tiedMain(),
        rules: _rules.copyWith(superOverOnKnockoutTie: false),
      );
      expect(s.phase, ScoringPhase.finished);
      expect(s.result!.winner, CricketWinner.tie);
    });

    test('a match that is not level never offers a super over', () {
      final s = derive(starts: [
        _openA,
        _openB
      ], events: [
        ...over(0, 1, 'b1', [1, 1, 1, 1, 1, 1]),
        ...over(1, 7, 'a1', [1, 1, 1, 1, 1, 0]),
      ]);
      expect(s.phase, ScoringPhase.finished);
      expect(s.result!.winner, CricketWinner.teamA);
    });
  });

  group('playing the super over', () {
    test('the side that batted second in the match bats first, for 1 over and 2 wickets', () {
      final s = derive(starts: [_openA, _openB, _openB], events: [...tiedMain(), ...over(2, 13, 'a1', [4])]);
      expect(s.phase, ScoringPhase.scoring);
      final v = s.current!;
      expect(v.isSuperOver, isTrue);
      expect(v.superOverNumber, 1);
      expect(v.battingSide, 'B');
      expect(v.result.maxBalls, 6);
      expect(v.result.maxWickets, 2);
    });

    test('two wickets end the super-over innings', () {
      final s = derive(starts: [
        _openA,
        _openB,
        _openB
      ], events: [
        ...tiedMain(),
        const LoggedEvent(
            2,
            CricketEvent.wicketBall(
                13, 'a1', Wicket(kind: WicketKind.bowled, outBatterId: 'b1', newBatterId: 'b3'))),
        const LoggedEvent(
            2,
            CricketEvent.wicketBall(
                14, 'a1', Wicket(kind: WicketKind.bowled, outBatterId: 'b3', newBatterId: 'b4'))),
      ]);
      expect(s.phase, ScoringPhase.awaitingInnings);
      expect(s.nextInningsIndex, 3);
      expect(s.current!.result.wickets, 2);
      expect(s.current!.result.endReason, InningsEnd.allOut);
    });

    test('the chasing side needs one more than the first super-over innings', () {
      final s = derive(starts: [
        _openA,
        _openB,
        _openB,
        _openA
      ], events: [
        ...tiedMain(),
        ...over(2, 13, 'a1', [4, 4, 0, 0, 0, 0]), // Blues 8
        ...over(3, 19, 'b1', [6]),
      ]);
      final v = s.current!;
      expect(v.battingSide, 'A');
      expect(v.result.setup.target, 9);
      expect(v.result.runsNeeded, 3);
      expect(s.phase, ScoringPhase.scoring);
    });

    test('winning the super over decides the match; main-innings runs are unchanged', () {
      final s = derive(starts: [
        _openA,
        _openB,
        _openB,
        _openA
      ], events: [
        ...tiedMain(),
        ...over(2, 13, 'a1', [4, 4, 0, 0, 0, 0]), // Blues 8
        ...over(3, 19, 'b1', [1, 1, 1, 0, 0, 0]), // Reds 3
      ]);
      expect(s.phase, ScoringPhase.finished);
      expect(s.result!.winner, CricketWinner.teamB);
      expect(s.result!.text, 'Match tied — Blues won the super over (8/0 to 3/0)');
      expect(s.runsFor('A'), 6);
      expect(s.runsFor('B'), 6, reason: 'super-over runs never count in the match score');
      expect(s.decidedByAdmin, isFalse);
    });

    test('the chase can win the super over early', () {
      final s = derive(starts: [
        _openA,
        _openB,
        _openB,
        _openA
      ], events: [
        ...tiedMain(),
        ...over(2, 13, 'a1', [1, 0, 0, 0, 0, 0]), // Blues 1
        ...over(3, 19, 'b1', [4]), // Reds 4 — target reached on ball 1
      ]);
      expect(s.phase, ScoringPhase.finished);
      expect(s.result!.winner, CricketWinner.teamA);
      expect(s.current!.result.endReason, InningsEnd.targetReached);
    });

    test('a tied super over repeats, with the batting order flipped', () {
      final events = [
        ...tiedMain(),
        ...over(2, 13, 'a1', [2, 0, 0, 0, 0, 0]),
        ...over(3, 19, 'b1', [2, 0, 0, 0, 0, 0]),
      ];
      final tied = derive(starts: [_openA, _openB, _openB, _openA], events: events);
      expect(tied.phase, ScoringPhase.awaitingInnings);
      expect(tied.nextInningsIndex, 4);
      expect(tied.superOverNext, isTrue);

      final second = derive(
        starts: [_openA, _openB, _openB, _openA, _openA],
        events: [...events, ...over(4, 25, 'b1', [1])],
      );
      expect(second.phase, ScoringPhase.scoring);
      expect(second.current!.battingSide, 'A', reason: 'Reds batted second last time, so they open now');
      expect(second.current!.superOverNumber, 2);

      final done = derive(starts: [
        _openA,
        _openB,
        _openB,
        _openA,
        _openA,
        _openB
      ], events: [
        ...events,
        ...over(4, 25, 'b1', [6, 0, 0, 0, 0, 0]),
        ...over(5, 31, 'a1', [1, 0, 0, 0, 0, 0]),
      ]);
      expect(done.phase, ScoringPhase.finished);
      expect(done.result!.winner, CricketWinner.teamA);
      expect(done.result!.text, contains('super over 2'));
    });
  });

  group('picking the winner by hand', () {
    test('settles a tie that is waiting for a super over', () {
      final s = derive(starts: [_openA, _openB], events: tiedMain(), tieDecision: 'B');
      expect(s.phase, ScoringPhase.finished);
      expect(s.result!.winner, CricketWinner.teamB);
      expect(s.result!.text, 'Match tied — Blues given the win (decided by the admin)');
      expect(s.decidedByAdmin, isTrue);
    });

    test('also settles a tie when super overs are off, and after a tied super over', () {
      final off = derive(
        starts: [_openA, _openB],
        events: tiedMain(),
        tieDecision: 'A',
        rules: _rules.copyWith(superOverOnKnockoutTie: false),
      );
      expect(off.result!.winner, CricketWinner.teamA);

      final events = [
        ...tiedMain(),
        ...over(2, 13, 'a1', [2, 0, 0, 0, 0, 0]),
        ...over(3, 19, 'b1', [2, 0, 0, 0, 0, 0]),
      ];
      final afterSo = derive(starts: [_openA, _openB, _openB, _openA], events: events, tieDecision: 'A');
      expect(afterSo.phase, ScoringPhase.finished);
      expect(afterSo.result!.winner, CricketWinner.teamA);
      expect(afterSo.decidedByAdmin, isTrue);
    });

    test('is ignored when the scores are no longer level, or a super over decided it', () {
      final notLevel = derive(starts: [
        _openA,
        _openB
      ], events: [
        ...over(0, 1, 'b1', [1, 1, 1, 1, 1, 1]),
        ...over(1, 7, 'a1', [1, 1, 1, 1, 1, 0]),
      ], tieDecision: 'B');
      expect(notLevel.result!.winner, CricketWinner.teamA);
      expect(notLevel.decidedByAdmin, isFalse);

      final soWon = derive(starts: [
        _openA,
        _openB,
        _openB,
        _openA
      ], events: [
        ...tiedMain(),
        ...over(2, 13, 'a1', [4, 4, 0, 0, 0, 0]),
        ...over(3, 19, 'b1', [1, 0, 0, 0, 0, 0]),
      ], tieDecision: 'A');
      expect(soWon.result!.winner, CricketWinner.teamB);
      expect(soWon.decidedByAdmin, isFalse);
    });
  });

  group('what the match doc shows', () {
    Map<String, dynamic> summary(MatchScoringState s, List<InningsStart> starts) => summaryFields(
          state: s,
          starts: starts,
          nameOf: (id) => id,
          nameA: 'Reds',
          nameB: 'Blues',
          rules: _rules,
        );

    test('the summary line follows each step', () {
      final starts = [_openA, _openB, _openB, _openA, _openA];
      expect(summary(derive(starts: starts.take(2).toList(), events: tiedMain()), starts)['summaryText'],
          'Match tied · super over next');

      final s2 = derive(starts: starts.take(3).toList(), events: [...tiedMain(), ...over(2, 13, 'a1', [4])]);
      expect(summary(s2, starts)['summaryText'], startsWith('Super over: Blues 4/0'));

      final s3 = derive(
          starts: starts.take(3).toList(),
          events: [...tiedMain(), ...over(2, 13, 'a1', [4, 0, 0, 0, 0, 0])]);
      expect(summary(s3, starts)['summaryText'], 'Super over: Blues 4/0 (1.0 ov) · Reds to bat');

      final tiedSo = derive(starts: starts.take(4).toList(), events: [
        ...tiedMain(),
        ...over(2, 13, 'a1', [2, 0, 0, 0, 0, 0]),
        ...over(3, 19, 'b1', [2, 0, 0, 0, 0, 0]),
      ]);
      expect(summary(tiedSo, starts)['summaryText'], 'Super over tied too · another super over next');
    });

    test('scoreA / scoreB stay the main-innings runs and every innings is cached', () {
      final starts = [_openA, _openB, _openB, _openA];
      final s = derive(starts: starts, events: [
        ...tiedMain(),
        ...over(2, 13, 'a1', [4, 4, 0, 0, 0, 0]),
        ...over(3, 19, 'b1', [1, 0, 0, 0, 0, 0]),
      ]);
      final f = summary(s, starts);
      expect(f['scoreA'], 6);
      expect(f['scoreB'], 6);
      expect((f['innings'] as List).length, 4);
      final r = resultFields(s);
      expect(r['result'], 'teamB');
      expect(r['resultText'], contains('won the super over'));
    });

    test('the list card shows the main score plus the super over', () {
      final starts = [_openA, _openB, _openB, _openA];
      final s = derive(starts: starts, events: [
        ...tiedMain(),
        ...over(2, 13, 'a1', [4, 4, 0, 0, 0, 0]),
        ...over(3, 19, 'b1', [1, 0, 0, 0, 0, 0]),
      ]);
      final match = Match(
        id: 'm',
        sport: 'cricket',
        category: 'boys',
        season: '2026',
        stage: MatchStage.knockout,
        matchNumber: 1,
        label: 'KO1',
        matchCode: 'KO1',
        teamA: TeamRef(teamId: 'tA', name: 'Reds'),
        teamB: TeamRef(teamId: 'tB', name: 'Blues'),
        notifyTopic: '',
        status: MatchStatus.completed,
        rules: _rules,
        innings: [for (final k in (summary(s, starts)['innings'] as List)) InningsRecord.fromMap(k as Map<String, dynamic>)],
      );
      final scores = sideScores(match);
      expect(scores[0].score, '6/0');
      expect(scores[0].superOver, '1/0');
      expect(scores[1].score, '6/0');
      expect(scores[1].superOver, '8/0');
      expect(scores.any((x) => x.batting || x.superOverBatting), isFalse);
    });
  });

  group('auto-play (Test Lab)', () {
    test('a simulated tied knockout always ends with a clean, replayable super over', () {
      var withSuperOver = 0;
      for (var seed = 0; seed < 400; seed++) {
        final sim = simulateMatch(
          rules: _rules,
          lineupA: _lineupA,
          lineupB: _lineupB,
          battingFirst: 'A',
          superOver: true,
          random: Random(seed),
        );
        final s = derive(starts: sim.starts, events: sim.events);
        expect(s.hasBlockingFlags, isFalse, reason: 'seed $seed');
        expect(s.phase, ScoringPhase.finished, reason: 'seed $seed');
        expect(s.result!.winner, isNot(CricketWinner.tie), reason: 'seed $seed');
        if (sim.starts.length > 2) {
          withSuperOver++;
          expect(sim.starts.length.isEven, isTrue);
        }
      }
      expect(withSuperOver, greaterThan(0), reason: 'some of 400 one-over matches should be level');
    });

    test('without super overs a level match stays level', () {
      var levels = 0;
      for (var seed = 0; seed < 400; seed++) {
        final sim = simulateMatch(
          rules: _rules,
          lineupA: _lineupA,
          lineupB: _lineupB,
          battingFirst: 'A',
          random: Random(seed),
        );
        expect(sim.starts.length, 2);
        if (derive(starts: sim.starts, events: sim.events, knockout: false).result!.winner == CricketWinner.tie) {
          levels++;
        }
      }
      expect(levels, greaterThan(0));
    });
  });
}
