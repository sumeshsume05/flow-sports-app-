import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flow_sports_app/screens/admin/admin_match_edit_screen.dart';
import 'package:flow_sports_app/services/firestore_service.dart';
import 'package:flow_sports_app/widgets/score_input_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The badminton match screen the admin uses courtside: Start / Reset ask first,
// the live + / − buttons update at once and can be undone, and Save Result
// says what it will do before it does it.

late FakeFirebaseFirestore db;

Future<void> _open(WidgetTester tester, {String status = 'upcoming', int? a, int? b, String? result}) async {
  db = FakeFirebaseFirestore();
  await db.collection('matches').doc('m1').set({
    'sport': 'badminton', 'category': 'boys', 'season': '2026', 'stage': 'league', 'matchNumber': 1,
    'label': 'Match 1', 'matchCode': 'L1', 'status': status, 'notifyTopic': '',
    'teamA': {'teamId': 'tA', 'name': 'Reds'}, 'teamB': {'teamId': 'tB', 'name': 'Blues'},
    'scoreA': a, 'scoreB': b, 'result': result,
  });
  tester.view.physicalSize = const Size(822, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: AdminMatchEditScreen(matchId: 'm1', service: FirestoreService(firestore: db)),
  ));
  await _settle(tester);
}

/// The LIVE badge pulses forever, so wait a fixed time instead of "settling".
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f, warnIfMissed: false);
  await _settle(tester);
}

Future<Map<String, dynamic>> _match(WidgetTester tester) async =>
    (await tester.runAsync(() async => (await db.collection('matches').doc('m1').get()).data()))!;

Future<List<Map<String, dynamic>>> _log(WidgetTester tester) async =>
    (await tester.runAsync(() async => (await db.collection('matches').doc('m1').collection('pointLog').get())
        .docs
        .map((d) => d.data())
        .toList()))!;

void main() {
  testWidgets('Start Match asks first; Cancel changes nothing, confirming makes it live', (tester) async {
    await _open(tester);
    await _tap(tester, find.text('Start Match'));
    expect(find.text('Start this match?'), findsOneWidget);
    expect(find.textContaining('LIVE for every viewer'), findsOneWidget);
    await _tap(tester, find.text('Cancel'));
    expect((await _match(tester))['status'], 'upcoming');

    await _tap(tester, find.text('Start Match'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Start match'));
    expect((await _match(tester))['status'], 'live');
  });

  testWidgets('Reset to Upcoming asks first', (tester) async {
    await _open(tester, status: 'live', a: 3, b: 2);
    await _tap(tester, find.text('Reset to Upcoming'));
    expect(find.text('Reset to Upcoming?'), findsWidgets);
    expect(find.textContaining('stops being LIVE'), findsOneWidget);
    await _tap(tester, find.text('Cancel'));
    expect((await _match(tester))['status'], 'live');

    await _tap(tester, find.text('Reset to Upcoming'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Reset to Upcoming'));
    expect((await _match(tester))['status'], 'upcoming');
  });

  testWidgets('a finished match: resetting it warns the result is removed', (tester) async {
    await _open(tester, status: 'completed', a: 21, b: 15, result: 'teamA');
    await _tap(tester, find.text('Reset to Upcoming'));
    expect(find.textContaining('stops counting in the standings'), findsOneWidget);
    await _tap(tester, find.text('Cancel'));
    expect((await _match(tester))['result'], 'teamA');
  });

  testWidgets('live + and −: the screen changes at once, the match and log follow, Undo takes it back',
      (tester) async {
    await _open(tester, status: 'live', a: 0, b: 0);
    final plusA = find.widgetWithIcon(IconButton, Icons.add).first;

    await _tap(tester, plusA);
    await _tap(tester, plusA);
    expect(find.text('2'), findsWidgets);
    var m = await _match(tester);
    expect([m['scoreA'], m['scoreB']], [2, 0]);
    var log = await _log(tester);
    expect(log.length, 2);

    expect(find.text('Undo last tap (Reds +1)'), findsOneWidget);
    await _tap(tester, find.text('Undo last tap (Reds +1)'));
    m = await _match(tester);
    expect(m['scoreA'], 1);
    log = await _log(tester);
    expect(log.length, 3, reason: 'the correction is a new entry; nothing is edited or deleted');
    expect(log.where((e) => e['scoreA'] == 1).length, 2);

    // Nothing left to undo.
    final undo = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Undo last tap'));
    expect(undo.onPressed, isNull);
  });

  testWidgets('− at 0 is not offered', (tester) async {
    await _open(tester, status: 'live', a: 0, b: 1);
    final minusButtons = tester.widgetList<IconButton>(find.widgetWithIcon(IconButton, Icons.remove)).toList();
    expect(minusButtons[0].onPressed, isNull); // Reds at 0
    expect(minusButtons[1].onPressed, isNotNull); // Blues at 1
  });

  testWidgets('Save Result says what it will do; Cancel saves nothing', (tester) async {
    await _open(tester, status: 'live', a: 0, b: 0);
    final fields = find.byType(ScoreInputField);
    await tester.enterText(find.descendant(of: fields.at(0), matching: find.byType(TextField)), '21');
    await tester.enterText(find.descendant(of: fields.at(1), matching: find.byType(TextField)), '15');
    await tester.pump();

    await _tap(tester, find.text('Save Result'));
    expect(find.text('Save this result?'), findsOneWidget);
    expect(find.text('Reds beat Blues, 21–15.'), findsOneWidget);
    expect(find.text('Reds gets 2 standings points, Blues gets 0.'), findsOneWidget);
    await _tap(tester, find.text('Cancel'));
    var m = await _match(tester);
    expect(m['status'], 'live');
    expect(m['result'], isNull);

    await _tap(tester, find.text('Save Result'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Save result'));
    m = await _match(tester);
    expect(m['status'], 'completed');
    expect(m['result'], 'teamA');
    expect([m['scoreA'], m['scoreB']], [21, 15]);
  });
}
