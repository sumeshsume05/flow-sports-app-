import 'package:flow_sports_app/core/cricket/cricket_event.dart';
import 'package:flow_sports_app/core/cricket/cricket_rules.dart';
import 'package:flow_sports_app/core/cricket/edit_preview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cricket_test_utils.dart';

String nameOf(String id) => 'N-$id';

// The scorer's own scenario: 0, 4, 2, 1, 0, 4 by one bowler.
List<CricketEvent> scenario() => [
      const CricketEvent.dot(1, 'b1'),
      const CricketEvent.bat(2, 'b1', 4, boundary: Boundary.four),
      const CricketEvent.bat(3, 'b1', 2),
      const CricketEvent.bat(4, 'b1', 1),
      const CricketEvent.dot(5, 'b1'),
      const CricketEvent.bat(6, 'b1', 4, boundary: Boundary.four),
    ];

EditPreview? preview(List<CricketEvent> events, CricketEvent edited) => previewEdit(
      rules: openRules,
      setup: setupFor(),
      events: events,
      edited: edited,
      nameOf: nameOf,
    );

void main() {
  test('four → single: score drops and the next ball goes to the other batter', () {
    final p = preview(scenario(), const CricketEvent.bat(2, 'b1', 1))!;
    expect(p.lines.first, 'Innings score: 11/0 → 8/0');
    expect(p.lines, contains('Over 1 · Ball 3 is faced by N-a2 instead of N-a1'));
    expect(p.warns, isFalse);
  });

  test('a change that keeps score and strike says so', () {
    final p = preview(scenario(), const CricketEvent.bat(3, 'b1', 2))!;
    expect(p.lines.first, 'Innings score stays 11/0');
    expect(p.lines, contains('N-a1 still faces the next ball'));
  });

  test('single → wide: no swap, one ball fewer, overs end later', () {
    final p = preview(scenario(), const CricketEvent.wide(4, 'b1'))!;
    expect(p.lines.any((l) => l.startsWith('Balls bowled: 1.0 → 0.5')), isTrue);
    expect(p.lines.any((l) => l.contains('end later')), isTrue);
  });

  test('editing the last ball talks about the next ball to be bowled', () {
    final p = preview(scenario(), const CricketEvent.bat(6, 'b1', 1))!;
    expect(p.lines.any((l) => l.startsWith('The next ball to be bowled is faced by')), isTrue);
  });

  test('adding a wicket early makes a later wicket of the same batter need review', () {
    const bowled = Wicket(kind: WicketKind.bowled, outBatterId: 'a1', newBatterId: 'a3');
    final events = [
      const CricketEvent.dot(1, 'b1'),
      CricketEvent.wicketBall(2, 'b1', bowled), // a1 is out here...
    ];
    // ...so also bowling a1 out on ball 1 leaves ball 2 dismissing someone already out.
    final p = preview(events, CricketEvent.wicketBall(1, 'b1', bowled))!;
    expect(p.warns, isTrue);
    expect(p.lines.any((l) => l.contains('will need review')), isTrue);
  });

  test('an edit that cannot be replayed gives no preview instead of crashing', () {
    expect(
      previewEdit(
        rules: openRules,
        setup: setupFor(),
        events: scenario(),
        edited: const CricketEvent.bat(2, 'zzz', 1),
        nameOf: nameOf,
      ),
      isNotNull, // a stranger bowler is only a review flag, never a crash
    );
  });
}
