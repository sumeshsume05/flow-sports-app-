import '../../models/match.dart';
import '../../models/team.dart';
import 'commentary_text.dart';
import 'cricket_event.dart';
import 'cricket_rules.dart';
import 'cricket_toss.dart';
import 'innings_replay.dart';
import 'match_scoring.dart';

/// Wording and numbers the viewer screens show for a cricket match. Pure, so
/// the match card, the detail screen and the tests all read the same thing.

/// "4.3" for 27 legal balls of a 6-ball over.
String oversTextFor(int legalBalls, int ballsPerOver) {
  final bpo = ballsPerOver <= 0 ? 6 : ballsPerOver;
  return '${legalBalls ~/ bpo}.${legalBalls % bpo}';
}

/// One side's line in a list: "45/2" with "(4.3 ov)", or "Yet to bat".
class SideScore {
  final String side; // 'A' | 'B'
  final String name;

  /// Null until this side has started batting.
  final String? score;
  final String? overs;

  /// This side is batting right now.
  final bool batting;

  /// This side's super-over score ("12/1"), when the match went to one — the
  /// latest super over, with [superOverBatting] true while it is in progress.
  final String? superOver;
  final bool superOverBatting;

  const SideScore({
    required this.side,
    required this.name,
    this.score,
    this.overs,
    this.batting = false,
    this.superOver,
    this.superOverBatting = false,
  });

  bool get hasBatted => score != null;
}

/// Both sides' scores from the innings cached on the match doc — no ball log
/// needed, so a list of 30 matches costs nothing extra.
List<SideScore> sideScores(Match match) {
  final bpo = match.rules?.ballsPerOver ?? 6;
  SideScore forSide(String side, String name) {
    // Innings 0 and 1 are the match itself; later ones are super overs.
    InningsRecord? main;
    InningsRecord? latestSuper;
    for (var k = 0; k < match.innings.length; k++) {
      final r = match.innings[k];
      if (r.batting != side) continue;
      if (k < 2) {
        main ??= r;
      } else {
        latestSuper = r;
      }
    }
    final soBatting = latestSuper != null && match.status == MatchStatus.live && !latestSuper.ended;
    final so = latestSuper == null ? null : '${latestSuper.runs}/${latestSuper.wickets}';
    if (main == null) return SideScore(side: side, name: name);
    final inProgress = match.status == MatchStatus.live && !main.ended;
    return SideScore(
      side: side,
      name: name,
      score: '${main.runs}/${main.wickets}',
      overs: oversTextFor(main.legalBalls, bpo),
      batting: inProgress,
      superOver: so,
      superOverBatting: soBatting,
    );
  }

  return [
    forSide('A', match.teamA.name ?? 'TBD'),
    forSide('B', match.teamB.name ?? 'TBD'),
  ];
}

/// Heading of one innings: "Blues innings", or "Super over · Blues" (and
/// "Super over 2 · Blues" when the first one was tied too).
String inningsTitle(InningsView v, String battingTeam) {
  if (!v.isSuperOver) return '$battingTeam innings';
  final n = v.superOverNumber;
  return 'Super over${n > 1 ? ' $n' : ''} · $battingTeam';
}

/// "Blues won the toss and chose to bat", or null before the toss.
String? tossText(CricketToss? toss, String nameA, String nameB) {
  if (toss == null) return null;
  final winner = toss.winner == 'A' ? nameA : nameB;
  return '$winner won the toss and chose to ${toss.elected == 'bat' ? 'bat' : 'bowl'}';
}

/// The one line a list card shows under the scores: the result when it is
/// finished, the chase / state while live, the toss before it starts.
String? matchStatusLine(Match match) {
  switch (match.status) {
    case MatchStatus.completed:
      return match.resultText ?? match.summaryText;
    case MatchStatus.live:
      return match.summaryText;
    case MatchStatus.upcoming:
      return tossText(match.toss, match.teamA.name ?? 'TBD', match.teamB.name ?? 'TBD');
  }
}

/// How a batter was dismissed, scorecard style: "c Ravi b Sam", "b Sam",
/// "run out (Anil)", "not out".
String dismissalText(BatterStats b, String Function(String id) nameOf) {
  switch (b.status) {
    case BatterStatus.yetToBat:
      return 'did not bat';
    case BatterStatus.batting:
      return 'not out';
    case BatterStatus.retired:
      return 'retired';
    case BatterStatus.out:
      break;
  }
  final d = b.dismissal;
  if (d == null) return 'out';
  final bowler = d.bowlerId == null ? null : nameOf(d.bowlerId!);
  final fielder = d.fielderId == null ? null : nameOf(d.fielderId!);
  String withBowler(String head) => bowler == null ? head : '$head b $bowler';
  return switch (d.kind) {
    WicketKind.bowled => bowler == null ? 'bowled' : 'b $bowler',
    WicketKind.caught => d.fielderId != null && d.fielderId == d.bowlerId
        ? 'c & b $bowler'
        : withBowler(fielder == null ? 'caught' : 'c $fielder'),
    WicketKind.lbw => withBowler('lbw'),
    WicketKind.stumped => withBowler(fielder == null ? 'stumped' : 'st $fielder'),
    WicketKind.runOut => fielder == null ? 'run out' : 'run out ($fielder)',
    WicketKind.hitWicket => withBowler('hit wicket'),
    WicketKind.obstructingField => 'obstructing the field',
    WicketKind.hitBallTwice => 'hit the ball twice',
    WicketKind.handledBall => 'handled the ball',
  };
}

/// Resolves player ids to names from both teams' rosters (read at display
/// time, so a renamed player shows the new name everywhere).
String Function(String id) playerNameLookup(Team? a, Team? b) {
  final names = <String, String>{
    for (final t in [a, b])
      if (t != null)
        for (final p in t.players) p.id: p.name,
  };
  return (id) => names[id] ?? 'Unknown player';
}

/// Everything the detail screen needs, worked out from the match doc, both
/// teams and the ball log. [state] is null when the match has not been set up
/// (no rules / toss / squads) or the ball log is not available — the screen
/// then shows only the basics.
class CricketViewData {
  final MatchScoringState? state;
  final String Function(String id) nameOf;

  const CricketViewData(this.state, this.nameOf);

  bool get hasScorecard => state != null && state!.innings.isNotEmpty;
}

CricketViewData buildCricketView({
  required Match match,
  required Team? teamA,
  required Team? teamB,
  required List<LoggedEvent>? events,
}) {
  final nameOf = playerNameLookup(teamA, teamB);
  final rules = match.rules;
  // No ball log yet (still loading, or it could not be read): showing empty
  // innings would read as "0/0", so show nothing instead.
  if (rules == null || match.innings.isEmpty || events == null) {
    return CricketViewData(null, nameOf);
  }
  final state = deriveMatchState(
    rules: rules,
    lineupA: match.lineupA,
    lineupB: match.lineupB,
    toss: match.toss,
    starts: [for (final r in match.innings) r.start],
    events: events,
    nameA: match.teamA.name ?? 'Team A',
    nameB: match.teamB.name ?? 'Team B',
    knockout: match.stage == MatchStage.knockout,
    tieDecision: match.tieDecision,
  );
  return CricketViewData(state, nameOf);
}

/// Strike rate / economy to one decimal, "-" when there is nothing to divide.
String oneDecimal(double v, {bool dashWhenZero = false}) =>
    dashWhenZero && v == 0 ? '-' : v.toStringAsFixed(1);

/// Which ball of its over a delivery is: "1" … "6" for a counted ball, and
/// "Wd" / "Nb" / "Dead" for the ones that are bowled again (so nobody has to
/// read "0.3"-style numbers).
String ballLabel(BallRecord b) {
  if (b.countsAsBall) return '${b.ballInOver}';
  return switch (b.delivery) {
    Delivery.wide => 'Wd',
    Delivery.noBall => 'Nb',
    Delivery.deadBall => 'Dead',
    Delivery.legal => '${b.ballInOver}',
  };
}

/// Long form for headings: "Ball 3", "Wide", "No ball", "Dead ball".
String ballLabelLong(BallRecord b) {
  if (b.countsAsBall) return 'Ball ${b.ballInOver}';
  return switch (b.delivery) {
    Delivery.wide => 'Wide',
    Delivery.noBall => 'No ball',
    Delivery.deadBall => 'Dead ball',
    Delivery.legal => 'Ball ${b.ballInOver}',
  };
}

/// "Over 3 · Ball 4" (over numbers start at 1 for people, not 0).
String ballPlace(BallRecord b) => 'Over ${b.over + 1} · ${ballLabelLong(b)}';

class CommentaryLine {
  final String label;
  final String text;
  final bool wicket;
  final bool boundary;

  const CommentaryLine(this.label, this.text, {this.wicket = false, this.boundary = false});
}

/// One over of the match for the viewer: a heading and its balls, newest first.
class OverGroup {
  final int number; // 1-based
  final String? bowlerName;
  final int runs; // runs the batting team got in this over
  final int wickets;
  final bool complete;
  final List<CommentaryLine> lines;

  const OverGroup({
    required this.number,
    required this.bowlerName,
    required this.runs,
    required this.wickets,
    required this.complete,
    required this.lines,
  });

  /// "Over 3 · Dinesh bowling · 7 runs · 1 wicket"
  String get header {
    final parts = <String>[
      'Over $number',
      if (bowlerName != null) '$bowlerName bowling',
      '$runs ${runs == 1 ? 'run' : 'runs'}',
      if (wickets > 0) '$wickets ${wickets == 1 ? 'wicket' : 'wickets'}',
      if (!complete) 'in progress',
    ];
    return parts.join(' · ');
  }
}

/// The ball-by-ball commentary grouped over by over, newest over first (and
/// newest ball first inside it). [maxOvers] limits how far back it goes so a
/// long match stays light; null shows everything.
List<OverGroup> overGroups(
  InningsResult r,
  String Function(String id) nameOf, {
  int? maxOvers,
  bool freeHitRule = true,
}) {
  final groups = <OverGroup>[];
  for (final o in r.overs.reversed) {
    if (maxOvers != null && groups.length >= maxOvers) break;
    if (o.balls.isEmpty) continue;
    groups.add(OverGroup(
      number: o.over + 1,
      bowlerName: o.bowlerId == null ? null : nameOf(o.bowlerId!),
      runs: o.balls.fold(0, (s, b) => s + b.teamRuns),
      wickets: o.balls.where((b) => b.isWicket).length,
      complete: o.complete,
      lines: [
        for (final b in o.balls.reversed)
          CommentaryLine(
            ballLabel(b),
            ballCommentary(b, nameOf, freeHitRule: freeHitRule),
            wicket: b.isWicket,
            boundary: b.completedRuns == 0 && b.batRuns >= 4,
          ),
      ],
    ));
  }
  return groups;
}

/// Batters in the order they came to the crease (openers first, then each
/// replacement), which is how a scorecard lists them. Players who have not
/// batted are left out.
List<String> battingOrder(InningsResult r) {
  final order = <String>[];
  void add(String? id) {
    if (id != null && !order.contains(id) && r.batters[id]?.status != BatterStatus.yetToBat) {
      order.add(id);
    }
  }

  add(r.setup.strikerId);
  add(r.setup.nonStrikerId);
  for (final b in r.balls) {
    add(b.strikerId);
    add(b.nonStrikerId);
  }
  // Someone sent in on the very last ball has no delivery of their own yet.
  for (final id in r.setup.battingLineup) {
    add(id);
  }
  return order;
}

/// "Extras 5 (wd 2, nb 1, b 1, lb 1)" — only the kinds that happened.
String extrasText(Extras e) {
  final parts = <String>[
    if (e.wides > 0) 'wd ${e.wides}',
    if (e.noBalls > 0) 'nb ${e.noBalls}',
    if (e.byes > 0) 'b ${e.byes}',
    if (e.legByes > 0) 'lb ${e.legByes}',
  ];
  return parts.isEmpty ? 'Extras 0' : 'Extras ${e.total} (${parts.join(', ')})';
}

/// "1-12 (Ravi, 1.4)".
String fallOfWicketText(FallOfWicket f, String Function(String id) nameOf) =>
    '${f.wicketNumber}-${f.teamRuns} (${nameOf(f.batterId)}, ${f.oversText})';
