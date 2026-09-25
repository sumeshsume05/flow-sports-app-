import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/widgets/status_badge.dart';

void main() {
  testWidgets('StatusBadge shows LIVE for a live match', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StatusBadge(status: MatchStatus.live))),
    );
    // The LIVE dot's pulse starts via a zero-delay Future — elapsing fake time
    // flushes it so the animation is fully under way before we assert/teardown.
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('LIVE'), findsOneWidget);
    // Replace the tree so the repeating animation's controller disposes
    // cleanly instead of leaving anything pending at test teardown.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
