import 'cricket_event.dart';
import 'cricket_rules.dart';
import 'innings_replay.dart';
import 'match_display.dart';

/// What saving an edited ball would change, worked out by replaying the
/// innings with and without the edit (nothing is written). Shown in the Edit
/// ball screen so the scorer sees the effect before tapping Save.
class EditPreview {
  /// One plain sentence per effect, most important first.
  final List<String> lines;

  /// Worth a warning colour: later balls would need review.
  final bool warns;

  const EditPreview(this.lines, {this.warns = false});

  bool get isEmpty => lines.isEmpty;
}

/// [events] is the innings' current log (the original ball included); [edited]
/// replaces the event with the same `seq`. Returns null when the edited log
/// can't be replayed at all.
EditPreview? previewEdit({
  required CricketRules rules,
  required InningsSetup setup,
  required List<CricketEvent> events,
  required CricketEvent edited,
  required String Function(String id) nameOf,
}) {
  final InningsResult before;
  final InningsResult after;
  try {
    before = replayInnings(rules, setup, events);
    after = replayInnings(rules, setup, [for (final e in events) e.seq == edited.seq ? edited : e]);
  } on ArgumentError {
    return null;
  }

  final lines = <String>[];
  var warns = false;

  if (before.runs != after.runs || before.wickets != after.wickets) {
    lines.add('Innings score: ${before.scoreText} → ${after.scoreText}');
  } else {
    lines.add('Innings score stays ${after.scoreText}');
  }

  if (before.legalBalls != after.legalBalls) {
    lines.add('Balls bowled: ${before.oversText} → ${after.oversText} overs '
        '(overs end ${after.legalBalls < before.legalBalls ? 'later' : 'sooner'})');
  }

  // Who faces the delivery right after the edited one.
  BallRecord? nextIn(InningsResult r) {
    for (final b in r.balls) {
      if (b.seq > edited.seq) return b;
    }
    return null;
  }

  final nextBefore = nextIn(before);
  final nextAfter = nextIn(after);
  if (nextBefore != null && nextAfter != null) {
    final was = nextBefore.strikerId;
    final now = nextAfter.strikerId;
    if (was != now && now != null) {
      lines.add('${ballPlace(nextAfter)} is faced by ${nameOf(now)} instead of '
          '${was == null ? 'someone else' : nameOf(was)}');
    } else if (now != null) {
      lines.add('${nameOf(now)} still faces the next ball');
    }
  } else if (before.strikerId != after.strikerId && after.strikerId != null) {
    lines.add('The next ball to be bowled is faced by ${nameOf(after.strikerId!)} '
        '(was ${before.strikerId == null ? 'someone else' : nameOf(before.strikerId!)})');
  }

  if (before.isEnded != after.isEnded) {
    lines.add(after.isEnded ? 'The innings would end at this point.' : 'The innings would no longer be over.');
    warns = true;
  }

  final flagsBefore = before.blockingFlags.length;
  final flagsAfter = after.blockingFlags.length;
  if (flagsAfter > flagsBefore) {
    final n = flagsAfter - flagsBefore;
    lines.add('⚠ $n later ball${n == 1 ? '' : 's'} will need review after this change');
    warns = true;
  } else if (flagsAfter < flagsBefore) {
    final n = flagsBefore - flagsAfter;
    lines.add('Clears $n review warning${n == 1 ? '' : 's'}');
  }

  return EditPreview(lines, warns: warns);
}
