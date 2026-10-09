import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
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

  /// Deletes one match together with its sub-collections. The match and its
  /// commentary go in one batch; the append-only point log can only be removed
  /// once the match no longer exists (the rule allows it exactly then), so it
  /// is cleared second — and skipped, not fatal, if the rules haven't been
  /// updated yet (those orphaned entries sit under a deleted match and are
  /// never read again).
  Future<void> _deleteMatchWithSubcollections(DocumentReference<Map<String, dynamic>> ref) async {
    // Sub-collections that have no Firestore rule yet (the cricket ball log
    // arrives with live scoring) can't even be read, so reading is tolerant:
    // anything unreadable is treated as empty and skipped.
    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> docsOf(String name) async {
      try {
        return (await ref.collection(name).get()).docs;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') return const [];
        rethrow;
      }
    }

    final commentary = await docsOf(commentaryCollection);
    final pointLog = await docsOf(pointLogCollection);
    final balls = await docsOf('balls');
    final edits = await docsOf('ballEdits');
    final batch = _db.batch();
    batch.delete(ref);
    for (final d in [...commentary, ...balls, ...edits]) {
      batch.delete(d.reference);
    }
    await batch.commit();
    try {
      await _deleteRefs([for (final d in pointLog) d.reference]);
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
  }

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
      await _firestoreService.saveResultAndResolveDependents(
        matchId: next.id,
        scoreA: s.a,
        scoreB: s.b,
        result: result,
        dependentUpdates: resolveDependentSlots(
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
}
