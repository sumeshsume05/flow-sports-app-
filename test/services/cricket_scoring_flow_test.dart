import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flow_sports_app/core/constants.dart';
import 'package:flow_sports_app/core/cricket/cricket_event.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/match_scoring.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/models/player.dart';
import 'package:flow_sports_app/screens/admin/cricket_scoring/scoring_controller.dart';
import 'package:flow_sports_app/services/firestore_service.dart';
import 'package:flow_sports_app/services/test_lab_service.dart';
import 'package:flutter_test/flutter_test.dart';

// The real FirestoreService + controller running against an in-memory
// Firestore: what the scorer's taps write, what a viewer would read back, and
// that the cached summary on the match doc never disagrees with the ball log.

const _rules = CricketRules(
  overs: 1, // one over each keeps whole matches short
  lastManStands: false,
  maxOversPerBowler: null,
  legByesAllowed: true,
  allowedWickets: CricketRules.allWickets,
);

List<Map<String, dynamic>> _players(String prefix) => [
      for (var i = 1; i <= 4; i++) Player(id: '$prefix$i', name: '${prefix.toUpperCase()}$i').toMap(),
    ];

late FakeFirebaseFirestore db;
late FirestoreService service;

Map<String, dynamic> _matchDoc({
  String id = 'm1',
  String stage = 'league',
  String code = 'L1',
  int number = 1,
  bool ready = true,
  Map<String, dynamic>? teamA = const {'teamId': 'tA', 'name': 'Reds'},
  Map<String, dynamic>? teamB = const {'teamId': 'tB', 'name': 'Blues'},
  Map<String, dynamic>? teamASource,
  Map<String, dynamic>? teamBSource,
  String category = 'boys',
}) =>
    {
      'sport': Sport.cricket,
      'category': category,
      'season': '2026',
      'stage': stage,
      'matchNumber': number,
      'label': 'Match $number',
      'matchCode': code,
      'teamA': teamA,
      'teamB': teamB,
      'teamASource': teamASource,
      'teamBSource': teamBSource,
      'status': 'upcoming',
      'notifyTopic': '',
      'rules': _rules.toMap(),
      if (ready) ...{
        'lineupA': ['a1', 'a2', 'a3', 'a4'],
        'lineupB': ['b1', 'b2', 'b3', 'b4'],
        'toss': {'winner': 'A', 'elected': 'bat'}, // Reds bat first
      },
    };

Future<CricketScoringController> _open([String id = 'm1']) async {
  final c = CricketScoringController(id, service: service);
  await pumpEventQueue();
  return c;
}

Future<Map<String, dynamic>> _match([String id = 'm1']) async =>
    (await db.collection('matches').doc(id).get()).data()!;

Future<List<Map<String, dynamic>>> _balls([String id = 'm1']) async =>
    (await db.collection('matches').doc(id).collection('balls').orderBy('seq').get())
        .docs
        .map((d) => d.data())
        .toList();

Future<void> _add(CricketScoringController c, CricketEvent Function(int seq) build) async {
  await c.addBall(build);
  await pumpEventQueue();
}

const _open0 = InningsStart(strikerId: 'a1', nonStrikerId: 'a2');
const _open1 = InningsStart(strikerId: 'b1', nonStrikerId: 'b2');

Future<void> _startFirst(CricketScoringController c) async {
  await c.startInnings(_open0);
  await pumpEventQueue();
}

CricketEvent _bat(int seq, int runs, {String bowler = 'b1', Boundary boundary = Boundary.none}) =>
    CricketEvent.bat(seq, bowler, runs, boundary: boundary);

void main() {
  setUp(() async {
    db = FakeFirebaseFirestore();
    service = FirestoreService(firestore: db);
    await db.collection('teams').doc('tA').set({
      'sport': Sport.cricket, 'category': 'boys', 'season': '2026', 'name': 'Reds', 'players': _players('a'),
    });
    await db.collection('teams').doc('tB').set({
      'sport': Sport.cricket, 'category': 'boys', 'season': '2026', 'name': 'Blues', 'players': _players('b'),
    });
    await db.collection('matches').doc('m1').set(_matchDoc());
  });

  group('starting and scoring', () {
    test('nothing to score until setup (toss + squads) is saved', () async {
      await db.collection('matches').doc('m2').set(_matchDoc(id: 'm2', ready: false));
      final c = await _open('m2');
      expect(c.state!.phase, ScoringPhase.needsSetup);
      c.dispose();
    });

    test('starting the innings goes live and records the openers', () async {
      final c = await _open();
      expect(c.state!.phase, ScoringPhase.awaitingInnings);
      await _startFirst(c);
      final m = await _match();
      expect(m['status'], 'live');
      expect((m['innings'] as List).single['strikerId'], 'a1');
      expect(c.state!.phase, ScoringPhase.scoring);
      expect(c.match!.innings.single.start.nonStrikerId, 'a2');
      c.dispose();
    });

    test('each ball is its own document and the match doc is updated in the same write', () async {
      final c = await _open();
      await _startFirst(c);
      await _add(c, (s) => CricketEvent.dot(s, 'b1'));
      await _add(c, (s) => _bat(s, 4, boundary: Boundary.four));
      await _add(c, (s) => CricketEvent.wide(s, 'b1'));

      final balls = await _balls();
      expect(balls.map((b) => b['seq']), [1, 2, 3]);
      expect(balls.every((b) => b['innings'] == 0), isTrue);
      expect(balls[1]['runs'], 4);
      expect(balls[1]['boundary'], 'four');
      expect(balls.every((b) => b['createdAt'] != null), isTrue);

      final ids = (await db.collection('matches').doc('m1').collection('balls').get()).docs.map((d) => d.id).toList()
        ..sort();
      expect(ids, ['b000001', 'b000002', 'b000003']);

      final m = await _match();
      expect(m['scoreA'], 5); // 4 + wide
      expect(m['scoreB'], 0);
      expect(m['summaryText'], 'Reds 5/0 (0.2 ov)');
      expect((m['live'] as Map)['bowlerId'], 'b1');
      expect(m['lastCommentaryText'], contains('Wide'));
      expect(m['lastCommentaryAt'], isNotNull);
      c.dispose();
    });

    test('the same sequence number twice overwrites — a double tap can never duplicate a ball', () async {
      final c = await _open();
      await _startFirst(c);
      final ev = const LoggedEvent(0, CricketEvent(seq: 1, bowlerId: 'b1'));
      await service.appendCricketBall('m1', ev, {});
      await service.appendCricketBall('m1', ev, {});
      expect((await _balls()).length, 1);
      c.dispose();
    });

    test('a late tap after the over is finished adds nothing (no "ball not counted" later)', () async {
      final c = await _open();
      await _startFirst(c);
      for (var i = 0; i < 6; i++) {
        await _add(c, (s) => _bat(s, 6, boundary: Boundary.six));
      }
      expect(c.state!.current!.result.isEnded, isTrue);
      await _add(c, (s) => _bat(s, 6, boundary: Boundary.six)); // the stale 7th tap
      await c.addEvent(const CricketEvent.swapStrike(0));
      await pumpEventQueue();
      expect((await _balls()).length, 6);
      expect(c.state!.hasBlockingFlags, isFalse);
      c.dispose();
    });

    test('a wicket brings in the next batter and is stored as inputs only', () async {
      final c = await _open();
      await _startFirst(c);
      await _add(
        c,
        (s) => CricketEvent.wicketBall(
            s, 'b1', const Wicket(kind: WicketKind.bowled, outBatterId: 'a1', newBatterId: 'a3')),
      );
      final ball = (await _balls()).single;
      expect(ball['wicket']['newBatterId'], 'a3');
      expect(ball.containsKey('strikerId'), isFalse, reason: 'derived state is never stored on a ball');
      expect(ball.containsKey('over'), isFalse);
      final live = (await _match())['live'] as Map;
      expect(live['strikerId'], 'a3');
      expect(live['nonStrikerId'], 'a2');
      c.dispose();
    });
  });

  group('undo, edit, delete', () {
    test('undo removes the newest ball and the score follows; the audit trail keeps it', () async {
      final c = await _open();
      await _startFirst(c);
      await _add(c, (s) => _bat(s, 1));
      await _add(c, (s) => _bat(s, 2));
      await c.undo();
      await pumpEventQueue();
      expect((await _balls()).map((b) => b['seq']), [1]);
      expect((await _match())['scoreA'], 1);
      final audit = (await db.collection('matches').doc('m1').collection('ballEdits').get()).docs.single.data();
      expect(audit['action'], 'undo');
      expect(audit['ballSeq'], 2);
      expect(audit['before']['runs'], 2);
      expect(audit['after'], isNull);
      // and the next ball reuses the freed number
      await _add(c, (s) => _bat(s, 3));
      expect((await _balls()).map((b) => b['seq']), [1, 2]);
      c.dispose();
    });

    test('undo with nothing scored does nothing', () async {
      final c = await _open();
      await _startFirst(c);
      await c.undo();
      expect((await _balls()), isEmpty);
      c.dispose();
    });

    test('the scenario from the brief: 0,4,2,1,0,4 → change ball 2 to a single → 11 becomes 8', () async {
      final c = await _open();
      await _startFirst(c);
      final inputs = [
        CricketEvent.dot(1, 'b1'),
        _bat(2, 4, boundary: Boundary.four),
        _bat(3, 2),
        _bat(4, 1),
        CricketEvent.dot(5, 'b1'),
        _bat(6, 4, boundary: Boundary.four),
      ];
      for (final e in inputs) {
        await _add(c, (_) => e);
      }
      expect((await _match())['scoreA'], 11);
      final before = await _balls();

      final target = c.events.firstWhere((e) => e.seq == 2);
      await c.editBall(target, CricketEvent.bat(2, 'b1', 1));
      await pumpEventQueue();

      final m = await _match();
      expect(m['scoreA'], 8);
      expect(m['summaryText'], 'Reds 8/0 (1.0 ov) · Blues to bat');

      // Only ball 2 was rewritten — every later ball still holds the scorer's original inputs.
      final after = await _balls();
      for (final i in [0, 2, 3, 4, 5]) {
        expect(after[i], before[i], reason: 'ball ${i + 1} untouched');
      }
      expect(after[1]['runs'], 1);
      expect(after[1]['boundary'], 'none');

      // Derived: the strike is re-worked after the edit.
      final r = c.state!.current!.result;
      expect(r.balls[2].strikerId, 'a2'); // ball 3 is now faced by the other batter
      expect(r.batters['a1']!.runs + r.batters['a2']!.runs + r.extras.total, 8);

      final audit = (await db.collection('matches').doc('m1').collection('ballEdits').get()).docs.single.data();
      expect(audit['action'], 'edit');
      expect(audit['before']['runs'], 4);
      expect(audit['after']['runs'], 1);
      c.dispose();
    });

    test('deleting a ball in the middle re-derives everything after it', () async {
      final c = await _open();
      await _startFirst(c);
      for (var i = 1; i <= 3; i++) {
        await _add(c, (s) => _bat(s, 1));
      }
      await c.deleteBall(c.events.firstWhere((e) => e.seq == 2));
      await pumpEventQueue();
      expect((await _balls()).map((b) => b['seq']), [1, 3]);
      expect((await _match())['scoreA'], 2);
      c.dispose();
    });

    test('removing a wicket flags the later new-batter input but never rewrites it', () async {
      final c = await _open();
      await _startFirst(c);
      await _add(
        c,
        (s) => CricketEvent.wicketBall(
            s, 'b1', const Wicket(kind: WicketKind.bowled, outBatterId: 'a1', newBatterId: 'a3')),
      );
      await _add(c, (s) => _bat(s, 1));
      final stored = await _balls();
      await c.editBall(c.events.first, CricketEvent.dot(1, 'b1')); // not out after all
      await pumpEventQueue();
      expect((await _balls()).last, stored.last, reason: 'the later ball is untouched');
      expect(c.state!.hasBlockingFlags, isFalse, reason: 'ball 2 is still valid on its own');
      c.dispose();
    });

    test('accepting a flag as-is is stored on that ball', () async {
      final c = await _open();
      await _startFirst(c);
      await _add(c, (s) => CricketEvent.dot(s, 'b1'));
      await _add(c, (s) => CricketEvent.dot(s, 'b2')); // bowler changed mid-over → review flag
      expect(c.state!.hasBlockingFlags, isTrue);
      final flag = c.state!.blockingFlags.single;
      await c.acknowledge(flag.seq, {flag.code.name});
      await pumpEventQueue();
      expect((await _balls()).last['acknowledgedFlags'], [flag.code.name]);
      expect(c.state!.hasBlockingFlags, isFalse);
      c.dispose();
    });
  });

  group('finishing', () {
    Future<CricketScoringController> playOut({
      required int firstRuns,
      required int secondRuns,
      String id = 'm1',
    }) async {
      final c = await _open(id);
      await _startFirst(c);
      for (var i = 0; i < 6; i++) {
        await _add(c, (s) => firstRuns == 0 ? CricketEvent.dot(s, 'b1') : _bat(s, firstRuns));
      }
      expect(c.state!.phase, ScoringPhase.awaitingInnings);
      expect(c.state!.nextInningsIndex, 1);
      expect((await _match(id))['summaryText'], contains('Blues to bat'));
      await c.startInnings(_open1);
      await pumpEventQueue();
      for (var i = 0; i < 6 && c.state!.phase == ScoringPhase.scoring; i++) {
        await _add(c, (s) => secondRuns == 0 ? CricketEvent.dot(s, 'a1') : _bat(s, secondRuns, bowler: 'a1'));
      }
      return c;
    }

    test('innings break → chase → result saved with scores and text', () async {
      final c = await playOut(firstRuns: 2, secondRuns: 1);
      expect(c.state!.phase, ScoringPhase.finished);
      expect(await c.finish(), isNull);
      await pumpEventQueue();
      final m = await _match();
      expect(m['status'], 'completed');
      expect(m['result'], 'teamA');
      expect(m['scoreA'], 12);
      expect(m['scoreB'], 6);
      expect(m['resultText'], 'Reds won by 6 runs');
      final innings = (m['innings'] as List).cast<Map>();
      expect(innings.map((i) => i['ended']), [true, true]);
      expect(innings.map((i) => i['legalBalls']), [6, 6]);

      final parsed = Match.fromFirestore(await db.collection('matches').doc('m1').get());
      expect(parsed.hasFinalResult, isTrue);
      expect(parsed.innings.length, 2);
      expect(parsed.resultText, 'Reds won by 6 runs');
      c.dispose();
    });

    test('a chase that gets there wins by wickets with balls to spare', () async {
      final c = await playOut(firstRuns: 1, secondRuns: 4);
      expect(await c.finish(), isNull);
      final m = await _match();
      expect(m['result'], 'teamB');
      expect(m['resultText'], 'Blues won by 3 wickets (4 balls left)');
      c.dispose();
    });

    test('equal scores are a tie (one point each in the league)', () async {
      final c = await playOut(firstRuns: 1, secondRuns: 1);
      expect(await c.finish(), isNull);
      expect((await _match())['result'], 'tie');
      c.dispose();
    });

    test('cannot save while a ball still needs review; can after accepting it', () async {
      final c = await _open();
      await _startFirst(c);
      await _add(c, (s) => CricketEvent.dot(s, 'b1'));
      await _add(c, (s) => CricketEvent.dot(s, 'b2')); // flag
      for (var i = 0; i < 4; i++) {
        await _add(c, (s) => CricketEvent.dot(s, 'b2'));
      }
      await c.startInnings(_open1);
      await pumpEventQueue();
      for (var i = 0; i < 6; i++) {
        await _add(c, (s) => CricketEvent.dot(s, 'a1'));
      }
      expect(c.state!.phase, ScoringPhase.finished);
      final blocked = await c.finish();
      expect(blocked, contains('need review'));
      expect((await _match())['status'], 'live');

      // Every ball after the change was bowled by someone other than the over's first bowler.
      for (final f in c.state!.blockingFlags) {
        await c.acknowledge(f.seq, {f.code.name});
      }
      await pumpEventQueue();
      expect(c.state!.hasBlockingFlags, isFalse);
      expect(await c.finish(), isNull);
      expect((await _match())['status'], 'completed');
      c.dispose();
    });

    test('reopening a finished league match makes it live again with no result', () async {
      final c = await playOut(firstRuns: 2, secondRuns: 1);
      await c.finish();
      await pumpEventQueue();
      expect(await c.reopen(), isNull);
      await pumpEventQueue();
      final m = await _match();
      expect(m['status'], 'live');
      expect(m['result'], isNull);
      expect(m['resultText'], isNull);
      expect(Match.fromFirestore(await db.collection('matches').doc('m1').get()).hasFinalResult, isFalse);
      // …and a ball can be corrected, then the result saved again.
      await c.editBall(c.events.firstWhere((e) => e.seq == 1), _bat(1, 6, boundary: Boundary.six));
      await pumpEventQueue();
      expect(await c.finish(), isNull);
      expect((await _match())['scoreA'], 16);
      c.dispose();
    });
  });

  group('knockout matches', () {
    Future<void> seedBracket() async {
      await db.collection('matches').doc('m1').set(_matchDoc(stage: 'knockout', code: 'KO1', number: 1));
      await db.collection('matches').doc('final').set(_matchDoc(
            id: 'final',
            stage: 'knockout',
            code: 'KOF',
            number: 2,
            ready: false,
            teamA: const {'teamId': null, 'name': null},
            teamB: const {'teamId': 'tB', 'name': 'Blues'},
            teamASource: const {'type': 'winner', 'seed': null, 'matchCode': 'KO1'},
          ));
    }

    Future<CricketScoringController> playKo({required int first, required int second}) async {
      final c = await _open();
      await _startFirst(c);
      for (var i = 0; i < 6; i++) {
        await _add(c, (s) => _bat(s, first));
      }
      await c.startInnings(_open1);
      await pumpEventQueue();
      for (var i = 0; i < 6 && c.state!.phase == ScoringPhase.scoring; i++) {
        await _add(c, (s) => _bat(s, second, bowler: 'a1'));
      }
      return c;
    }

    test('the winner fills ONLY its own slot of the next round', () async {
      await seedBracket();
      final c = await playKo(first: 2, second: 1);
      expect(await c.finish(), isNull);
      final next = await _match('final');
      expect(next['teamA']['teamId'], 'tA'); // Reds won
      expect(next['teamB']['teamId'], 'tB', reason: 'the other slot is left alone');
      c.dispose();
    });

    test('a tied knockout is not finished: it waits for a super over and nothing is advanced', () async {
      await seedBracket();
      final c = await playKo(first: 1, second: 1);
      expect(c.state!.phase, ScoringPhase.awaitingInnings);
      expect(c.state!.superOverNext, isTrue);
      expect((await _match())['summaryText'], 'Match tied · super over next');
      expect(await c.finish(), contains('isn\'t finished'));
      expect((await _match())['status'], 'live');
      expect((await _match('final'))['teamA']['teamId'], isNull);
      c.dispose();
    });

    test('a super over decides it: the winner moves on, the match score is unchanged', () async {
      await seedBracket();
      final c = await playKo(first: 1, second: 1);
      // Blues (batted second) open the super over: 1 over, 2 wickets.
      await c.startInnings(_open1);
      await pumpEventQueue();
      expect(c.state!.current!.isSuperOver, isTrue);
      expect(c.state!.current!.battingSide, 'B');
      for (var i = 0; i < 6; i++) {
        await _add(c, (s) => _bat(s, i == 0 ? 4 : 0, bowler: 'a1', boundary: i == 0 ? Boundary.four : Boundary.none));
      }
      expect(c.state!.nextInningsIndex, 3);
      await c.startInnings(_open0);
      await pumpEventQueue();
      await _add(c, (s) => _bat(s, 6, bowler: 'b1', boundary: Boundary.six)); // Reds chase 5, hit 6
      expect(c.state!.phase, ScoringPhase.finished);
      expect(c.state!.result!.text, contains('Reds won the super over'));

      final doc = await _match();
      expect(doc['scoreA'], 6);
      expect(doc['scoreB'], 6);
      expect((doc['innings'] as List).length, 4);
      expect(await c.finish(), isNull);
      final done = await _match();
      expect(done['result'], 'teamA');
      expect(done['status'], 'completed');
      expect((await _match('final'))['teamA']['teamId'], 'tA');
      c.dispose();
    });

    test('the admin can pick the winner of a tied knockout by hand, and take the pick back', () async {
      await seedBracket();
      final c = await playKo(first: 1, second: 1);
      await c.decideTie('B');
      await pumpEventQueue();
      expect(c.state!.phase, ScoringPhase.finished);
      expect(c.state!.decidedByAdmin, isTrue);
      expect((await _match())['tieDecision'], 'B');
      expect((await _match())['summaryText'], contains('given the win'));

      expect(await c.finish(), isNull);
      final done = await _match();
      expect(done['result'], 'teamB');
      expect(done['resultText'], contains('decided by the admin'));
      expect((await _match('final'))['teamA']['teamId'], 'tB'); // Blues take the slot

      // Reopen, take the pick back: a super over is on offer again.
      expect(await c.reopen(), isNull);
      await pumpEventQueue();
      await c.decideTie(null);
      await pumpEventQueue();
      expect(c.state!.superOverNext, isTrue);
      expect((await _match())['tieDecision'], isNull);
      c.dispose();
    });

    test('reopening puts the slot back to TBD — unless the next round has already started', () async {
      await seedBracket();
      final c = await playKo(first: 2, second: 1);
      await c.finish();
      await pumpEventQueue();

      await db.collection('matches').doc('final').update({'status': 'live'});
      final refused = await c.reopen();
      expect(refused, contains("Can't reopen"));
      expect((await _match())['status'], 'completed');
      expect((await _match('final'))['teamA']['teamId'], 'tA');

      await db.collection('matches').doc('final').update({'status': 'upcoming'});
      expect(await c.reopen(), isNull);
      expect((await _match())['status'], 'live');
      expect((await _match('final'))['teamA']['teamId'], isNull);
      expect((await _match('final'))['teamB']['teamId'], 'tB');
      c.dispose();
    });
  });

  group('squads edited after the innings started', () {
    test('openers no longer in the squad → a clear problem, not a crash', () async {
      final c = await _open();
      await _startFirst(c);
      await db.collection('matches').doc('m1').update({'lineupA': ['a3', 'a4']});
      await pumpEventQueue();
      expect(c.state!.phase, ScoringPhase.broken);
      c.dispose();
    });
  });

  group('Test Lab auto-play', () {
    Future<void> seedTestMatch() async {
      await db.collection('teams').doc('tA').update({'category': Category.test});
      await db.collection('teams').doc('tB').update({'category': Category.test});
      await db.collection('matches').doc('m1').set(_matchDoc(category: Category.test, ready: false));
    }

    test('plays a whole match: balls, summary and result agree, and the replay of the stored balls matches', () async {
      await seedTestMatch();
      final lab = TestLabService(firestore: db, firestoreService: service);
      final r = await lab.playCricketStage(Sport.cricket, '2026', stage: 'league', random: Random(5));
      expect(r.played, 1);
      expect(r.note, isNull);

      final m = await _match();
      expect(m['status'], 'completed');
      expect(m['resultText'], isNotNull);
      expect(m['lineupA'], isNotEmpty);
      expect(m['toss'], isNotNull);

      final c = await _open();
      expect(c.state!.phase, ScoringPhase.finished);
      expect(c.state!.hasBlockingFlags, isFalse, reason: 'auto-play only produces valid scoring');
      expect(c.state!.runsFor('A'), m['scoreA']);
      expect(c.state!.runsFor('B'), m['scoreB']);
      expect(c.state!.result!.text, m['resultText']);
      c.dispose();

      // Already played → nothing more to do.
      final again = await lab.playCricketStage(Sport.cricket, '2026', stage: 'league', random: Random(6));
      expect(again.played, 0);
    });

    test('a knockout played with ties goes to a super over, and the stored balls replay to the same result',
        () async {
      await db.collection('teams').doc('tA').update({'category': Category.test});
      await db.collection('teams').doc('tB').update({'category': Category.test});
      await db.collection('matches').doc('m1').set(
          _matchDoc(stage: 'knockout', code: 'KOF', category: Category.test, ready: false));
      final lab = TestLabService(firestore: db, firestoreService: service);
      final r = await lab.playCricketKnockout(Sport.cricket, '2026', random: Random(3), forceTie: true);
      expect(r.played, 1);
      expect(r.note, 'The whole knockout is played.');

      final m = await _match();
      expect(m['status'], 'completed');
      expect(m['result'], anyOf('teamA', 'teamB'));
      expect((m['innings'] as List).length, greaterThan(2), reason: 'a super over was played');
      expect(m['scoreA'], m['scoreB'], reason: 'the match itself ended level');
      expect(m['resultText'], contains('super over'));

      final c = await _open();
      expect(c.state!.phase, ScoringPhase.finished);
      expect(c.state!.hasBlockingFlags, isFalse);
      expect(c.state!.result!.text, m['resultText']);
      c.dispose();
    });

    test('teams with fewer than 2 players are skipped with a reason', () async {
      await seedTestMatch();
      await db.collection('teams').doc('tA').update({'players': _players('a').take(1).toList()});
      final lab = TestLabService(firestore: db, firestoreService: service);
      final r = await lab.playCricketStage(Sport.cricket, '2026', stage: 'league', random: Random(1));
      expect(r.played, 0);
      expect(r.note, contains('at least 2 players'));
    });

    test('reset removes the test match together with its balls and audit entries', () async {
      await seedTestMatch();
      final lab = TestLabService(firestore: db, firestoreService: service);
      await lab.playCricketStage(Sport.cricket, '2026', stage: 'league', random: Random(2));
      final c = await _open();
      await c.editBall(c.events.first, c.events.first.event.copyWith(runs: 0, runType: RunType.none));
      await pumpEventQueue();
      c.dispose();
      expect((await db.collection('matches').doc('m1').collection('balls').get()).docs, isNotEmpty);
      expect((await db.collection('matches').doc('m1').collection('ballEdits').get()).docs, isNotEmpty);

      await lab.reset(Sport.cricket, '2026');
      expect((await db.collection('matches').get()).docs, isEmpty);
      expect((await db.collection('matches').doc('m1').collection('balls').get()).docs, isEmpty);
      expect((await db.collection('matches').doc('m1').collection('ballEdits').get()).docs, isEmpty);
    });
  });
}
