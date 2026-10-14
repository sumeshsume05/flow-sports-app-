import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
import '../core/cricket/auto_play.dart';
import '../core/cricket/cricket_toss.dart';
import '../core/cricket/match_result.dart';
import '../core/cricket/match_scoring.dart';
import '../core/test_lab/test_scenarios.dart';
import '../core/utils/bracket_resolver.dart';
import '../models/match.dart';
import '../models/team.dart';
import 'firestore_service.dart';

/// Test data for the admin's Test Lab. EVERYTHING here is scoped to
/// `category == Category.test` for one sport and the active season, so real
/// Boys/Girls data can never be created, changed or deleted by it. Test
/// teams and matches are stored exactly like real ones — same collections,
/// same screens, same logic — which is what makes them a faithful test; they
/// are just invisible to viewers (Home and the CSV export only loop over
/// `Category.all`).
class TestLabService {
  final FirebaseFirestore _db;
  final FirestoreService _firestoreService;

  TestLabService({FirebaseFirestore? firestore, FirestoreService? firestoreService})
      : _db = firestore ?? FirebaseFirestore.instance,
        _firestoreService = firestoreService ?? FirestoreService(firestore: firestore);

  Query<Map<String, dynamic>> _teams(String sport, String season) => _db
      .collection(teamsCollection)
      .where('sport', isEqualTo: sport)
      .where('category', isEqualTo: Category.test)
      .where('season', isEqualTo: season);

  Query<Map<String, dynamic>> _matches(String sport, String season) => _db
      .collection(matchesCollection)
      .where('sport', isEqualTo: sport)
      .where('category', isEqualTo: Category.test)
      .where('season', isEqualTo: season);

  /// How much test data currently exists for [sport].
  Future<({int teams, int matches})> counts(String sport, String season) async {
    final t = await _teams(sport, season).count().get();
    final m = await _matches(sport, season).count().get();
    return (teams: t.count ?? 0, matches: m.count ?? 0);
  }

  Future<void> _deleteRefs(List<DocumentReference> refs) async {
    for (var i = 0; i < refs.length; i += 400) {
      final batch = _db.batch();
      for (final r in refs.skip(i).take(400)) {
        batch.delete(r);
      }
      await batch.commit();
    }
  }

  /// Deletes one match together with its sub-collections (commentary, point
  /// log, cricket balls and their audit trail) — shared with the real
  /// delete-match path so both clear exactly the same things.
  Future<void> _deleteMatchWithSubcollections(DocumentReference<Map<String, dynamic>> ref) =>
      _firestoreService.deleteMatchTrees([ref]);

  /// Removes every test team and match (and their sub-collections and the
  /// stored tournament plan) for [sport]. Real categories are never queried.
  Future<void> reset(String sport, String season) async {
    final matchDocs = (await _matches(sport, season).get()).docs;
    for (final doc in matchDocs) {
      await _deleteMatchWithSubcollections(doc.reference);
    }
    final teamDocs = (await _teams(sport, season).get()).docs;
    await _deleteRefs([for (final d in teamDocs) d.reference]);
    // The cricket Plan screen's saved plan for the test category, if any.
    try {
      await _db.collection(configCollection).doc('cricketPlan_${Category.test}_$season').delete();
    } on FirebaseException catch (_) {}
  }

  /// Replaces any existing test data with the scenario's teams (and, for
  /// cricket, their players and sections).
  Future<int> createScenario(String sport, String season, TestScenario scenario) async {
    await reset(sport, season);
    final specs = buildScenarioTeams(sport, scenario);
    final batch = _db.batch();
    for (final s in specs) {
      batch.set(
        _db.collection(teamsCollection).doc(),
        Team(
          id: '',
          sport: sport,
          category: Category.test,
          name: s.name,
          season: season,
          section: s.section,
          players: s.players,
        ).toFirestore(),
      );
    }
    await batch.commit();
    return specs.length;
  }

  /// Plays every unplayed test match of [stage] ('league' or 'tiebreaker')
  /// with made-up scores (badminton style: winner 21, loser 0–19). With
  /// [allTies] every match ends 21–21 — for the league that leaves every team
  /// level (the quickest way to reach the tie-breaker flow); for tie-breakers
  /// it forces another round. Matches that already have a result are left
  /// alone. Returns how many matches were filled in.
  Future<int> playStage(String sport, String season,
      {required String stage, required bool allTies, Random? random}) async {
    final rnd = random ?? Random();
    final snap = await _matches(sport, season).where('stage', isEqualTo: stage).get();
    final todo = unplayedMatches(snap.docs.map(Match.fromFirestore).toList());
    for (var i = 0; i < todo.length; i += 400) {
      final batch = _db.batch();
      for (final m in todo.skip(i).take(400)) {
        final s = testScores(tie: allTies, aWins: rnd.nextBool(), loserScore: rnd.nextInt(20));
        batch.update(_db.collection(matchesCollection).doc(m.id), {
          'scoreA': s.a,
          'scoreB': s.b,
          'result': Match.computeResult(s.a, s.b)!.name,
          'status': MatchStatus.completed.name,
        });
      }
      await batch.commit();
    }
    return todo.length;
  }

  Future<int> playLeague(String sport, String season, {required bool allTies, Random? random}) =>
      playStage(sport, season, stage: 'league', allTies: allTies, random: random);

  Future<int> playTiebreakers(String sport, String season, {required bool allTies, Random? random}) =>
      playStage(sport, season, stage: 'tiebreaker', allTies: allTies, random: random);

  /// Plays the knockout bracket one match at a time, resolving each next
  /// round exactly like saving a real result does. Stops when nothing more
  /// can be played; [note] explains why when a manual step is needed.
  Future<({int played, String? note})> playKnockout(String sport, String season, {Random? random}) async {
    final rnd = random ?? Random();
    var played = 0;
    for (var guard = 0; guard < 20; guard++) {
      final all = (await _matches(sport, season).where('stage', isEqualTo: 'knockout').get())
          .docs
          .map(Match.fromFirestore)
          .toList()
        ..sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
      final next = all
          .where((m) => m.result == null && m.teamA.teamId != null && m.teamB.teamId != null)
          .firstOrNull;
      if (next == null) {
        return (played: played, note: _knockoutNote(all));
      }
      final s = testScores(tie: false, aWins: rnd.nextBool(), loserScore: rnd.nextInt(20));
      final result = Match.computeResult(s.a, s.b)!;
      final completed = Match(
        id: next.id,
        sport: next.sport,
        category: next.category,
        season: next.season,
        stage: next.stage,
        matchNumber: next.matchNumber,
        label: next.label,
        matchCode: next.matchCode,
        teamA: next.teamA,
        teamB: next.teamB,
        scoreA: s.a,
        scoreB: s.b,
        result: result,
        status: MatchStatus.completed,
        notifyTopic: next.notifyTopic,
      );
      await _firestoreService.saveResultAndResolveSlots(
        matchId: next.id,
        scoreA: s.a,
        scoreB: s.b,
        result: result,
        slotWrites: dependentSlotWrites(
          completed: completed,
          otherKnockoutMatches: all.where((m) => m.id != next.id).toList(),
        ),
      );
      played++;
    }
    return (played: played, note: null);
  }

  String? _knockoutNote(List<Match> all) {
    if (all.isEmpty) return 'There is no knockout bracket yet — generate it first.';
    final kof1 = all.where((m) => m.matchCode == 'KOF1').firstOrNull;
    final kof2 = all.where((m) => m.matchCode == 'KOF2').firstOrNull;
    final hasDecider = all.any((m) => m.matchCode == 'KOF3');
    if (kof1?.result != null &&
        kof2?.result != null &&
        kof1!.result != kof2!.result &&
        !hasDecider) {
      return 'The best-of-3 Final is 1–1. Schedule the decider (Game 3) in Generate Bracket, then play it.';
    }
    if (all.every((m) => m.result != null)) return 'The whole knockout is played.';
    return null;
  }

  // --- Cricket auto-play ---

  /// Plays one test cricket match completely with the real scoring engine:
  /// picks the squads (the match's own, else the first players of each team),
  /// tosses, then writes a rule-abiding ball-by-ball log, the cached summary
  /// and the result — exactly what a scorer's taps would have produced. Any
  /// balls already scored for it are replaced. Returns null on success, or why
  /// the match was skipped.
  Future<String?> _playCricketMatch(
    Match m,
    Random rnd, {
    List<Match> otherKnockout = const [],
  }) async {
    final teamA = Team.fromFirestore(await _db.collection(teamsCollection).doc(m.teamA.teamId).get());
    final teamB = Team.fromFirestore(await _db.collection(teamsCollection).doc(m.teamB.teamId).get());
    final rules = m.rules ?? await _firestoreService.watchCricketRules().first;

    List<String> squad(List<String> saved, Team t) {
      final active = t.activePlayers.map((p) => p.id).toSet();
      final keep = saved.where(active.contains).toList();
      return keep.length >= 2 ? keep : t.activePlayers.take(rules.squadSize).map((p) => p.id).toList();
    }

    final lineupA = squad(m.lineupA, teamA);
    final lineupB = squad(m.lineupB, teamB);
    if (lineupA.length < 2 || lineupB.length < 2) {
      return '${m.label}: each team needs at least 2 players (add them in Teams > Players).';
    }

    final isKnockout = m.stage == MatchStage.knockout;
    CricketToss? toss;
    SimulatedMatch? sim;
    MatchScoringState? state;
    for (var attempt = 0; attempt < 40; attempt++) {
      toss = CricketToss(winner: rnd.nextBool() ? 'A' : 'B', elected: rnd.nextBool() ? 'bat' : 'bowl');
      sim = simulateMatch(
        rules: rules,
        lineupA: lineupA,
        lineupB: lineupB,
        battingFirst: toss.battingFirstSide,
        random: rnd,
      );
      state = deriveMatchState(
        rules: rules,
        lineupA: lineupA,
        lineupB: lineupB,
        toss: toss,
        starts: sim.starts,
        events: sim.events,
        nameA: m.teamA.name ?? 'Team A',
        nameB: m.teamB.name ?? 'Team B',
      );
      // A knockout needs a winner (super overs come later), so replay a tie.
      if (!isKnockout || state.result?.winner != CricketWinner.tie) break;
    }
    if (state == null || state.result == null || sim == null || toss == null) {
      return '${m.label}: could not play it.';
    }
    if (isKnockout && state.result!.winner == CricketWinner.tie) {
      return '${m.label}: stayed tied after many tries — super overs aren\'t built yet.';
    }

    final names = {for (final p in [...teamA.players, ...teamB.players]) p.id: p.name};
    final fields = {
      ...summaryFields(
        state: state,
        starts: sim.starts,
        nameOf: (id) => names[id] ?? 'Player',
        nameA: m.teamA.name ?? 'Team A',
        nameB: m.teamB.name ?? 'Team B',
        rules: rules,
      ),
      ...resultFields(state),
      'rules': rules.toMap(),
      'lineupA': lineupA,
      'lineupB': lineupB,
      'toss': toss.toMap(),
    };

    // Replace any balls scored earlier (read tolerantly: the rules may not be deployed yet).
    final ballsRef = _db.collection(matchesCollection).doc(m.id).collection('balls');
    final old = <DocumentReference<Map<String, dynamic>>>[];
    try {
      old.addAll((await ballsRef.get()).docs.map((d) => d.reference));
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
    await _deleteRefs(old);

    final writes = [for (final e in sim.events) e];
    for (var i = 0; i < writes.length; i += 400) {
      final batch = _db.batch();
      for (final e in writes.skip(i).take(400)) {
        batch.set(ballsRef.doc(FirestoreService.ballDocId(e.seq)), {
          ...e.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    var slotWrites = <SlotWrite>[];
    if (isKnockout) {
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
      slotWrites = dependentSlotWrites(completed: completed, otherKnockoutMatches: otherKnockout);
    }
    await _firestoreService.finishCricketMatch(m.id, resultFields: fields, slotWrites: slotWrites);
    return null;
  }

  /// Plays every unplayed cricket test match of [stage] ('league' or
  /// 'tiebreaker'). Returns how many were played and a note for any skipped.
  Future<({int played, String? note})> playCricketStage(String sport, String season,
      {required String stage, Random? random}) async {
    final rnd = random ?? Random();
    final snap = await _matches(sport, season).where('stage', isEqualTo: stage).get();
    final todo = unplayedMatches(snap.docs.map(Match.fromFirestore).toList());
    var played = 0;
    String? note;
    for (final m in todo) {
      final problem = await _playCricketMatch(m, rnd);
      if (problem == null) {
        played++;
      } else {
        note = problem;
      }
    }
    return (played: played, note: note);
  }

  /// Plays the cricket knockout one match at a time so each result fills the
  /// next round, like saving real results.
  Future<({int played, String? note})> playCricketKnockout(String sport, String season, {Random? random}) async {
    final rnd = random ?? Random();
    var played = 0;
    for (var guard = 0; guard < 20; guard++) {
      final all = (await _matches(sport, season).where('stage', isEqualTo: 'knockout').get())
          .docs
          .map(Match.fromFirestore)
          .toList()
        ..sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
      final next = all
          .where((m) => m.result == null && m.teamA.teamId != null && m.teamB.teamId != null)
          .firstOrNull;
      if (next == null) return (played: played, note: _knockoutNote(all));
      final problem = await _playCricketMatch(next, rnd, otherKnockout: all.where((m) => m.id != next.id).toList());
      if (problem != null) return (played: played, note: problem);
      played++;
    }
    return (played: played, note: null);
  }
}
