import 'package:flow_sports_app/core/cricket/cricket_event.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/innings_replay.dart';
import 'package:flow_sports_app/screens/admin/cricket_scoring/wicket_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _rules = CricketRules(
  overs: 6,
  lastManStands: false,
  maxOversPerBowler: null,
  allowedWickets: CricketRules.tapeBallWickets,
);

InningsResult _innings({
  List<String> batting = const ['a1', 'a2', 'a3', 'a4'],
  List<CricketEvent> events = const [],
}) =>
    replayInnings(
      _rules,
      InningsSetup(
        battingLineup: batting,
        bowlingLineup: const ['b1', 'b2'],
        strikerId: batting[0],
        nonStrikerId: batting[1],
      ),
      events,
    );

/// Opens the sheet from a button and returns what it produced once closed.
Future<WicketEntry?> _openSheet(
  WidgetTester tester,
  InningsResult innings, {
  Delivery delivery = Delivery.legal,
  required Future<void> Function() interact,
}) async {
  WicketEntry? result;
  var closed = false;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await showWicketSheet(
                context,
                innings: innings,
                delivery: delivery,
                extraRunsAreWide: delivery == Delivery.wide,
                nameOf: (id) => id,
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await interact();
  await tester.pumpAndSettle();
  expect(closed, isTrue, reason: 'the sheet closed with a result');
  return result;
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save wicket'));
  await tester.tap(find.text('Save wicket'));
}

void main() {
  group('which dismissals are offered', () {
    test('normal ball: whatever the rules allow', () {
      expect(wicketKindsFor(_rules, Delivery.legal, false), contains(WicketKind.bowled));
      expect(wicketKindsFor(_rules, Delivery.legal, false), isNot(contains(WicketKind.lbw))); // tape ball: no LBW
    });

    test('wide: only stumped / run out / hit wicket and the like', () {
      final kinds = wicketKindsFor(const CricketRules.t20(), Delivery.wide, false);
      expect(kinds, containsAll([WicketKind.stumped, WicketKind.runOut, WicketKind.hitWicket]));
      expect(kinds, isNot(contains(WicketKind.bowled)));
      expect(kinds, isNot(contains(WicketKind.caught)));
    });

    test('no-ball or free hit: only run out and the like', () {
      for (final kinds in [
        wicketKindsFor(const CricketRules.t20(), Delivery.noBall, false),
        wicketKindsFor(const CricketRules.t20(), Delivery.legal, true),
      ]) {
        expect(kinds, contains(WicketKind.runOut));
        expect(kinds, isNot(contains(WicketKind.bowled)));
        expect(kinds, isNot(contains(WicketKind.lbw)));
      }
    });
  });

  testWidgets('a bowled wicket needs the next batter, then saves them on strike', (tester) async {
    final entry = await _openSheet(tester, _innings(), interact: () async {
      // Save is off until someone is picked to come in.
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save wicket')).onPressed, isNull);
      await tester.tap(find.widgetWithText(ChoiceChip, 'a3'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save wicket')).onPressed, isNotNull);
      await _save(tester);
    });
    expect(entry, isNotNull);
    expect(entry!.wicket.kind, WicketKind.bowled);
    expect(entry.wicket.outBatterId, 'a1'); // the batter on strike
    expect(entry.wicket.newBatterId, 'a3');
    expect(entry.wicket.newBatterEnd, NewBatterEnd.onStrike);
    expect(entry.runs, 0);
  });

  testWidgets('run out with no runs run: striker out at the far end → new batter at the other end', (tester) async {
    final entry = await _openSheet(tester, _innings(), interact: () async {
      await tester.tap(find.widgetWithText(ChoiceChip, 'Run out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'a4'));
      await tester.pumpAndSettle();
      await _save(tester);
    });
    expect(entry!.wicket.kind, WicketKind.runOut);
    expect(entry.wicket.outBatterId, 'a1');
    expect(entry.wicket.newBatterEnd, NewBatterEnd.offStrike);
  });

  testWidgets('run out after one run: the default end flips, and the runs are returned', (tester) async {
    final entry = await _openSheet(tester, _innings(), interact: () async {
      await tester.tap(find.widgetWithText(ChoiceChip, 'Run out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '1'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'a3'));
      await tester.pumpAndSettle();
      await _save(tester);
    });
    expect(entry!.runs, 1);
    expect(entry.wicket.newBatterEnd, NewBatterEnd.onStrike);
  });

  testWidgets('the non-striker can be the one run out', (tester) async {
    final entry = await _openSheet(tester, _innings(), interact: () async {
      await tester.tap(find.widgetWithText(ChoiceChip, 'Run out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'a2'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'a3'));
      await tester.pumpAndSettle();
      await _save(tester);
    });
    expect(entry!.wicket.outBatterId, 'a2');
    // a2 (non-striker) run out at the striker's end with no run: new batter takes strike.
    expect(entry.wicket.newBatterEnd, NewBatterEnd.onStrike);
  });

  testWidgets('a free hit offers only a run out', (tester) async {
    final onFreeHit = _innings(events: [CricketEvent.noBall(1, 'b1')]);
    expect(onFreeHit.freeHitNext, isTrue);
    await _openSheet(tester, onFreeHit, interact: () async {
      expect(find.widgetWithText(ChoiceChip, 'Run out'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Bowled'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'a3'));
      await tester.pumpAndSettle();
      await _save(tester);
    });
  });

  testWidgets('a wicket that ends the innings needs no next batter', (tester) async {
    final entry = await _openSheet(tester, _innings(batting: const ['a1', 'a2']), interact: () async {
      expect(find.text('Next batter'), findsNothing);
      await _save(tester);
    });
    expect(entry!.wicket.newBatterId, isNull);
  });

  testWidgets('cancelling gives nothing back', (tester) async {
    WicketEntry? result = const WicketEntry(Wicket(kind: WicketKind.bowled, outBatterId: 'x'), 0);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async => result = await showWicketSheet(
            context,
            innings: _innings(),
            delivery: Delivery.legal,
            extraRunsAreWide: false,
            nameOf: (id) => id,
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // tap the scrim
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
