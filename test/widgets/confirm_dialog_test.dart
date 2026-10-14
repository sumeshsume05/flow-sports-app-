import 'package:flow_sports_app/widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('plain: shows the title, message and bullets; Cancel returns false', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await confirmAction(
            context,
            title: 'Create 28 league matches?',
            message: 'They appear for viewers straight away.',
            bullets: const ['Boys: 28 matches', 'Girls: 15 matches'],
            confirmLabel: 'Create',
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Create 28 league matches?'), findsOneWidget);
    expect(find.text('They appear for viewers straight away.'), findsOneWidget);
    expect(find.text('Boys: 28 matches'), findsOneWidget);
    expect(find.text('Girls: 15 matches'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('plain: the action button returns true', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              result = await confirmAction(context, title: 'Sure?', confirmLabel: 'Do it'),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Do it'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('danger: the confirm button is red', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => confirmAction(context, title: 'Delete?', confirmLabel: 'Reset Cricket', danger: true),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Reset Cricket'));
    expect(button.style?.backgroundColor?.resolve({}), isNotNull);
  });

  testWidgets('type-to-confirm: locked until the word is typed (any case, spaces ignored)', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await confirmAction(
            context,
            title: 'Reset?',
            confirmLabel: 'Reset Cricket',
            typeToConfirm: 'RESET',
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    FilledButton button() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Reset Cricket'));
    expect(find.text('Type RESET to confirm:'), findsOneWidget);
    expect(button().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'reset now');
    await tester.pump();
    expect(button().onPressed, isNull, reason: 'a wrong word does not unlock it');

    await tester.enterText(find.byType(TextField), ' reset ');
    await tester.pump();
    expect(button().onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Reset Cricket'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('type-to-confirm: closing without typing returns false', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await confirmAction(
            context,
            title: 'Reset?',
            confirmLabel: 'Reset',
            typeToConfirm: 'RESET',
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
