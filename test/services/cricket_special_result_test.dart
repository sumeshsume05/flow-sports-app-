import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flow_sports_app/core/constants.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/services/cricket_special_result.dart';
import 'package:flow_sports_app/services/firestore_service.dart';
import 'package:flutter_test/flutter_test.dart';

// No result and walkover against an in-memory Firestore: what lands on the
// match doc, who advances in a knockout, and that taking it back undoes it.

late FakeFirebaseFirestore db;
late FirestoreService service;

Map<String, dynamic> _doc({
  required String code,
  String stage = 'league',
  int number = 1,
  Map<String, dynamic>? teamA = const {'teamId': 'tA', 'name': 'Reds'},
  Map<String, dynamic>? teamB = const {'teamId': 'tB', 'name': 'Blues'},
  Map<String, dynamic>? teamASource,
  Map<String, dynamic>? teamBSource,
  String status = 'upcoming',
}) =>
    {
      'sport': Sport.cricket,
      'category': 'boys',
      'season': '2026',
      'stage': stage,
      'matchNumber': number,
      'label': code,
      'matchCode': code,
      'teamA': teamA,
      'teamB': teamB,
      'teamASource': teamASource,
      'teamBSource': teamBSource,
      'status': status,
      'notifyTopic': '',
      'rules': const CricketRules(overs: 1).toMap(),
    };

Future<Match> _load(String id) async => Match.fromFirestore(await db.collection('matches').doc(id).get());

void main() {
  setUp(() {
    db = FakeFirebaseFirestore();
    service = FirestoreService(firestore: db);
  });

  group('no result', () {
    test('a league match is finished with no result and nothing else changes', () async {
      await db.collection('matches').doc('m1').set(_doc(code: 'L1'));
      expect(await recordNoResult(service, await _load('m1'), reason: 'Rain'), isNull);
      final m = await _load('m1');
      expect(m.status, MatchStatus.completed);
      expect(m.resultType, ResultType.noResult);
      expect(m.resultText, 'No result — Rain');
      expect(m.hasFinalResult, isTrue);
    });

    test('a knockout match cannot end with no result', () async {
      await db.collection('matches').doc('k1').set(_doc(code: 'KO1', stage: 'knockout'));
      expect(await recordNoResult(service, await _load('k1')), contains('needs a winner'));
      expect((await _load('k1')).status, MatchStatus.upcoming);
    });

    test('taking it back returns the match to upcoming and clears the marker', () async {
      await db.collection('matches').doc('m1').set(_doc(code: 'L1'));
      await recordNoResult(service, await _load('m1'));
      expect(await undoSpecialResult(service, await _load('m1')), isNull);
      final m = await _load('m1');
      expect(m.status, MatchStatus.upcoming);
      expect(m.result, isNull);
      expect(m.resultType, isNull);
      expect(m.resultText, isNull);
      expect(m.hasFinalResult, isFalse);
    });
  });

  group('walkover', () {
    test('the chosen side wins; scores stay empty', () async {
      await db.collection('matches').doc('m1').set(_doc(code: 'L1'));
      expect(await recordWalkover(service, await _load('m1'), 'B', reason: 'Reds did not turn up'), isNull);
      final m = await _load('m1');
      expect(m.result, MatchResult.teamB);
      expect(m.resultType, ResultType.walkover);
      expect(m.resultText, 'Blues won by walkover (Reds did not turn up)');
      expect(m.scoreA, isNull);
      expect(m.status, MatchStatus.completed);
    });

    test('refused once scoring has started', () async {
      await db.collection('matches').doc('m1').set({
        ..._doc(code: 'L1', status: 'live'),
        'innings': [
          {
            'batting': 'A',
            'start': {'strikerId': 'a1', 'nonStrikerId': 'a2'},
            'runs': 3,
            'wickets': 0,
            'legalBalls': 2,
            'ended': false,
            'allOut': false,
          },
        ],
      });
      expect(await recordWalkover(service, await _load('m1'), 'A'), contains('Scoring has already started'));
      expect((await _load('m1')).status, MatchStatus.live);
    });

    group('in a knockout', () {
      Future<void> seed() async {
        await db.collection('matches').doc('ko1').set(_doc(code: 'KO1', stage: 'knockout'));
        await db.collection('matches').doc('final').set(_doc(
              code: 'KOF',
              stage: 'knockout',
              number: 2,
              teamA: const {'teamId': null, 'name': null},
              teamB: const {'teamId': 'tC', 'name': 'Cubs'},
              teamASource: const {'type': 'winner', 'seed': null, 'matchCode': 'KO1'},
            ));
      }

      test('the winner moves into its slot of the next round', () async {
        await seed();
        expect(await recordWalkover(service, await _load('ko1'), 'A'), isNull);
        final next = await _load('final');
        expect(next.teamA.teamId, 'tA');
        expect(next.teamB.teamId, 'tC', reason: 'the other slot is left alone');
      });

      test('taking it back empties that slot again', () async {
        await seed();
        await recordWalkover(service, await _load('ko1'), 'A');
        expect(await undoSpecialResult(service, await _load('ko1')), isNull);
        expect((await _load('final')).teamA.teamId, isNull);
        expect((await _load('ko1')).status, MatchStatus.upcoming);
      });

      test('cannot be taken back once the next round has started', () async {
        await seed();
        await recordWalkover(service, await _load('ko1'), 'A');
        await db.collection('matches').doc('final').update({'status': 'live'});
        expect(await undoSpecialResult(service, await _load('ko1')), contains('already been started'));
        expect((await _load('ko1')).resultType, ResultType.walkover);
      });
    });
  });

  test('a match played normally has nothing to take back', () async {
    await db.collection('matches').doc('m1').set({..._doc(code: 'L1'), 'status': 'completed', 'result': 'teamA'});
    expect(await undoSpecialResult(service, await _load('m1')), contains('normal result'));
  });
}
