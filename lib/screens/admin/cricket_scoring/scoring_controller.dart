import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/cricket/cricket_event.dart';
import '../../../core/cricket/cricket_rules.dart';
import '../../../core/cricket/match_scoring.dart';
import '../../../core/utils/bracket_resolver.dart';
import '../../../models/match.dart';
import '../../../models/team.dart';
import '../../../services/firestore_service.dart';

/// Holds everything the cricket scoring screens share — the match doc, both
/// teams (for player names), the ball log and the replayed state — and the
/// actions that change them. Every action recomputes the derived summary from
/// the *new* log and writes it in the same batch as the ball (see
/// `FirestoreService.appendCricketBall`), so the doc never disagrees with the
/// log. Writes are not awaited by the keypad: Firestore applies them locally
/// at once and queues them when there is no signal.
class CricketScoringController extends ChangeNotifier {
  final String matchId;
  final FirestoreService _service;
  final String? editorId;

  CricketScoringController(this.matchId, {FirestoreService? service, this.editorId})
      : _service = service ?? FirestoreService() {
    _subs.add(_service.watchMatch(matchId).listen(_onMatch, onError: _onError));
    _subs.add(_service.watchBalls(matchId).listen((b) {
      events = b;
      ballsLoaded = true;
      _recompute();
    }, onError: _onError));
  }

  final _subs = <StreamSubscription<dynamic>>[];
  StreamSubscription<Team?>? _subA;
  StreamSubscription<Team?>? _subB;
  String? _teamAId;
  String? _teamBId;

  Match? match;
  bool matchLoaded = false;
  bool ballsLoaded = false;
  Team? teamA;
  Team? teamB;
  List<LoggedEvent> events = const [];
  MatchScoringState? state;
  Object? error;

  CricketRules get rules => match?.rules ?? const CricketRules();
  String get nameA => match?.teamA.name ?? 'Team A';
  String get nameB => match?.teamB.name ?? 'Team B';
  String teamName(String side) => side == 'A' ? nameA : nameB;

  bool get ready => matchLoaded && ballsLoaded && match != null;
  bool get isCompleted => match?.status == MatchStatus.completed;

  List<InningsStart> get starts => [for (final i in match?.innings ?? const <InningsRecord>[]) i.start];

  Map<String, String> get _names => {
        for (final t in [teamA, teamB])
          if (t != null)
            for (final p in t.players) p.id: p.name,
      };

  String nameOf(String id) => _names[id] ?? 'Player';

  void _onError(Object e) {
    error = e;
    notifyListeners();
  }

  void _onMatch(Match? m) {
    match = m;
    matchLoaded = true;
    if (m != null) {
      if (m.teamA.teamId != _teamAId) {
        _teamAId = m.teamA.teamId;
        _subA?.cancel();
        if (_teamAId != null) {
          _subA = _service.watchTeam(_teamAId!).listen((t) {
            teamA = t;
            notifyListeners();
          }, onError: _onError);
        }
      }
      if (m.teamB.teamId != _teamBId) {
        _teamBId = m.teamB.teamId;
        _subB?.cancel();
        if (_teamBId != null) {
          _subB = _service.watchTeam(_teamBId!).listen((t) {
            teamB = t;
            notifyListeners();
          }, onError: _onError);
        }
      }
    }
    _recompute();
  }

  void _recompute() {
    final m = match;
    if (m != null && ballsLoaded) {
      state = _derive(starts, events);
    }
    notifyListeners();
  }

  MatchScoringState _derive(List<InningsStart> starts, List<LoggedEvent> evs) => deriveMatchState(
        rules: rules,
        lineupA: match!.lineupA,
        lineupB: match!.lineupB,
        toss: match!.toss,
        starts: starts,
        events: evs,
        nameA: nameA,
        nameB: nameB,
        knockout: match!.stage == MatchStage.knockout,
        tieDecision: match!.tieDecision,
      );

  Map<String, dynamic> _summary(MatchScoringState s, List<InningsStart> starts) => summaryFields(
        state: s,
        starts: starts,
        nameOf: nameOf,
        nameA: nameA,
        nameB: nameB,
        rules: rules,
      );

  // ---- actions -----------------------------------------------------------

  Future<void> startInnings(InningsStart start) {
    final next = [...starts, start];
    final s = _derive(next, events);
    return _service.saveCricketSummary(matchId, _summary(s, next), markLive: true);
  }

  /// A tied knockout match whose winner the admin picks by hand ([side] 'A' |
  /// 'B'), or null to take the pick back (a super over is offered again).
  Future<void> decideTie(String? side) {
    final m = match!;
    final s = deriveMatchState(
      rules: rules,
      lineupA: m.lineupA,
      lineupB: m.lineupB,
      toss: m.toss,
      starts: starts,
      events: events,
      nameA: nameA,
      nameB: nameB,
      knockout: m.stage == MatchStage.knockout,
      tieDecision: side,
    );
    return _service.saveCricketSummary(
      matchId,
      _summary(s, starts),
      extra: {'tieDecision': side},
    );
  }

  /// Adds one event to the innings being scored.
  Future<void> addEvent(CricketEvent e) {
    final cur = state!.current!;
    if (cur.result.isEnded) return Future.value(); // a late tap after the innings ended
    final logged = LoggedEvent(cur.index, e.copyWith(seq: nextSeq(events)));
    final s = _derive(starts, [...events, logged]);
    return _service.appendCricketBall(matchId, logged, _summary(s, starts));
  }

  /// Seq numbers are assigned here, so callers build events with seq 0.
  Future<void> addBall(CricketEvent Function(int seq) build) {
    final cur = state!.current!;
    // A late tap (the screen was still drawing the old buttons) must not add a
    // ball after the over / wickets / target already ended the innings.
    if (cur.result.isEnded) return Future.value();
    final seq = nextSeq(events);
    final logged = LoggedEvent(cur.index, build(seq));
    final s = _derive(starts, [...events, logged]);
    return _service.appendCricketBall(matchId, logged, _summary(s, starts));
  }

  Future<void> editBall(LoggedEvent before, CricketEvent after) {
    final edited = LoggedEvent(before.innings, after.copyWith(seq: before.seq));
    final next = [for (final e in events) e.seq == before.seq ? edited : e];
    return _service.editCricketBall(
      matchId,
      before: before,
      after: edited,
      summary: _summary(_derive(starts, next), starts),
      editedBy: editorId,
    );
  }

  Future<void> deleteBall(LoggedEvent ball, {bool undo = false}) {
    final next = [for (final e in events) if (e.seq != ball.seq) e];
    return _service.deleteCricketBall(
      matchId,
      before: ball,
      summary: _summary(_derive(starts, next), starts),
      undo: undo,
      editedBy: editorId,
    );
  }

  /// Undo = remove the newest event of the innings being scored.
  Future<void> undo() {
    final cur = state?.current;
    final mine = [for (final e in events) if (e.innings == cur?.index) e];
    if (mine.isEmpty) return Future.value();
    return deleteBall(mine.last, undo: true);
  }

  Future<void> acknowledge(int seq, Set<String> codes) => _service.setBallAcknowledged(matchId, seq, codes);

  /// Saves the result (and fills the next knockout slots). Returns a message
  /// when it can't, null on success.
  Future<String?> finish() async {
    final m = match!;
    final s = state!;
    if (s.phase != ScoringPhase.finished || s.result == null) return 'The match isn\'t finished yet.';
    if (s.hasBlockingFlags) {
      return '${s.blockingFlags.length} ball${s.blockingFlags.length == 1 ? '' : 's'} still need review. '
          'Fix them or accept them as they are first.';
    }
    final fields = resultFields(s);
    var slotWrites = <SlotWrite>[];
    if (m.stage == MatchStage.knockout) {
      if (fields['result'] == 'tie') {
        return 'This knockout match is tied and a knockout needs a winner. Play a super over, or pick '
            'the winner by hand.';
      }
      final all = await _service.fetchMatches(
        sport: m.sport,
        category: m.category,
        season: m.season,
        stage: 'knockout',
      );
      final completed = Match(
        id: m.id,
        sport: m.sport,
        category: m.category,
        season: m.season,
        stage: m.stage,
        matchNumber: m.matchNumber,
        label: m.label,
        matchCode: m.matchCode,
        teamA: m.teamA,
        teamB: m.teamB,
        scoreA: fields['scoreA'] as int,
        scoreB: fields['scoreB'] as int,
        result: fields['result'] == 'teamA' ? MatchResult.teamA : MatchResult.teamB,
        status: MatchStatus.completed,
        notifyTopic: m.notifyTopic,
      );
      final others = all.where((x) => x.id != m.id).toList();
      final stale = staleDependentUpdates(resolveDependentSlots(completed: completed, otherKnockoutMatches: others), all);
      if (stale.isNotEmpty) {
        return 'This changes who advances, but ${stale.map((x) => x.label).join(', ')} already started or was '
            'played. Reset the later round first, then save this result.';
      }
      slotWrites = dependentSlotWrites(completed: completed, otherKnockoutMatches: others);
    }
    await _service.finishCricketMatch(matchId, resultFields: fields, slotWrites: slotWrites);
    return null;
  }

  /// Reopens a finished match for editing. Returns a message when a later
  /// knockout round has already been started from its result.
  Future<String?> reopen() async {
    final m = match!;
    var clears = <SlotWrite>[];
    if (m.stage == MatchStage.knockout) {
      final all = await _service.fetchMatches(
        sport: m.sport,
        category: m.category,
        season: m.season,
        stage: 'knockout',
      );
      final dependents = dependentsOf(m.matchCode, all.where((x) => x.id != m.id).toList());
      final started = dependents.where(isStarted).toList();
      if (started.isNotEmpty) {
        return "Can't reopen ${m.label}: ${started.map((x) => x.label).join(', ')} "
            '${started.length == 1 ? 'has' : 'have'} already been started or played from its result. '
            'Reset the later round first, then come back to this match.';
      }
      clears = unresolveSlotWrites(m.matchCode, dependents);
    }
    await _service.reopenCricketMatch(matchId, clears: clears);
    return null;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subA?.cancel();
    _subB?.cancel();
    super.dispose();
  }
}
