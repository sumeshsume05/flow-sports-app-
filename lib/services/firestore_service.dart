import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
import '../core/cricket/cricket_rules.dart';
import '../core/cricket/cricket_toss.dart';
import '../core/cricket/match_rules_stamp.dart';
import '../core/utils/team_rename.dart';
import '../models/chat_message.dart';
import '../models/commentary_entry.dart';
import '../models/match.dart';
import '../models/player.dart';
import '../models/point_log_entry.dart';
import '../models/season.dart';
import '../models/team.dart';

/// Thrown when a Firestore write fails outright (e.g. permission denied or a
/// malformed request) — distinct from being offline, which Firestore's local
/// queue already handles silently and successfully (the write just waits to
/// sync once connectivity returns).
class FirestoreWriteException implements Exception {
  final String message;
  final Object cause;

  FirestoreWriteException(this.message, this.cause);

  @override
  String toString() => message;
}

/// Thin wrapper around Firestore reads/writes. Screens consume the typed
/// streams directly via StreamBuilder — no extra state-management layer
/// needed for an app this size.
class FirestoreService {
  final FirebaseFirestore _db;

  FirestoreService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  Stream<List<Team>> watchTeams({
    required String sport,
    required String category,
    required String season,
  }) {
    return _db
        .collection(teamsCollection)
        .where('sport', isEqualTo: sport)
        .where('category', isEqualTo: category)
        .where('season', isEqualTo: season)
        .snapshots()
        .map((snap) => snap.docs.map(Team.fromFirestore).toList());
  }

  Stream<List<Match>> watchMatches({
    required String sport,
    required String category,
    required String season,
  }) {
    return _db
        .collection(matchesCollection)
        .where('sport', isEqualTo: sport)
        .where('category', isEqualTo: category)
        .where('season', isEqualTo: season)
        .orderBy('stage')
        .orderBy('matchNumber')
        .snapshots()
        .map((snap) => snap.docs.map(Match.fromFirestore).toList());
  }

  Stream<Match?> watchMatch(String matchId) {
    return _db
        .collection(matchesCollection)
        .doc(matchId)
        .snapshots()
        .map((doc) => doc.exists ? Match.fromFirestore(doc) : null);
  }

  /// Same as [watchMatch], but also reports whether the latest snapshot still
  /// has a write queued locally that hasn't reached the server yet — used by
  /// the score-entry screen to show an honest "Saved — syncing…" vs "Synced"
  /// state instead of nothing.
  Stream<(Match? match, bool hasPendingWrites)> watchMatchWithSyncStatus(String matchId) {
    return _db
        .collection(matchesCollection)
        .doc(matchId)
        .snapshots(includeMetadataChanges: true)
        .map((doc) => (doc.exists ? Match.fromFirestore(doc) : null, doc.metadata.hasPendingWrites));
  }

  Future<List<Team>> fetchTeams({
    required String sport,
    required String category,
    required String season,
  }) async {
    final snap = await _db
        .collection(teamsCollection)
        .where('sport', isEqualTo: sport)
        .where('category', isEqualTo: category)
        .where('season', isEqualTo: season)
        .get();
    return snap.docs.map(Team.fromFirestore).toList();
  }

  Future<List<Match>> fetchMatches({
    required String sport,
    required String category,
    required String season,
    String? stage,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection(matchesCollection)
        .where('sport', isEqualTo: sport)
        .where('category', isEqualTo: category)
        .where('season', isEqualTo: season);
    if (stage != null) {
      query = query.where('stage', isEqualTo: stage);
    }
    final snap = await query.get();
    return snap.docs.map(Match.fromFirestore).toList();
  }

  Stream<Team?> watchTeam(String teamId) {
    return _db
        .collection(teamsCollection)
        .doc(teamId)
        .snapshots()
        .map((doc) => doc.exists ? Team.fromFirestore(doc) : null);
  }

  /// Replaces a team's whole roster. Players are only ever added, renamed or
  /// deactivated (never removed), so ids that appear in lineups and ball
  /// events stay resolvable.
  Future<void> updateTeamPlayers(String teamId, List<Player> players) async {
    try {
      await _db
          .collection(teamsCollection)
          .doc(teamId)
          .update({'players': players.map((p) => p.toMap()).toList()});
    } catch (e) {
      throw FirestoreWriteException('Could not save players.', e);
    }
  }

  /// Which sports viewers see on Home: `config/enabledSports` = `{sport: bool}`.
  Future<void> setSportEnabled(String sport, bool enabled) async {
    try {
      await _db
          .collection(configCollection)
          .doc('enabledSports')
          .set({sport: enabled}, SetOptions(merge: true));
    } catch (e) {
      throw FirestoreWriteException('Could not update visible sports.', e);
    }
  }

  /// Tournament-wide default cricket rules (`config/cricketRules`). Falls
  /// back to the tape-ball preset until an admin saves one.
  Stream<CricketRules> watchCricketRules() {
    return _db
        .collection(configCollection)
        .doc('cricketRules')
        .snapshots()
        .map((doc) => CricketRules.fromMap(doc.data()));
  }

  Future<void> saveCricketRules(CricketRules rules) async {
    try {
      await _db.collection(configCollection).doc('cricketRules').set(rules.toMap());
    } catch (e) {
      throw FirestoreWriteException('Could not save cricket rules.', e);
    }
  }

  /// Saves a cricket match's own rules snapshot, the two playing squads (as
  /// player ids) and the toss in one write.
  Future<void> saveCricketSetup(
    String matchId, {
    required CricketRules rules,
    required List<String> lineupA,
    required List<String> lineupB,
    required CricketToss? toss,
  }) async {
    try {
      await _db.collection(matchesCollection).doc(matchId).update({
        'rules': rules.toMap(),
        'lineupA': lineupA,
        'lineupB': lineupB,
        'toss': toss?.toMap(),
      });
    } catch (e) {
      throw FirestoreWriteException('Could not save match setup.', e);
    }
  }

  Future<void> addTeam(Team team) async {
    try {
      await _db.collection(teamsCollection).add(team.toFirestore());
    } catch (e) {
      throw FirestoreWriteException('Could not add team.', e);
    }
  }

  /// Renames a team *and* every match that already references it. Match docs
  /// carry a denormalized copy of each team's name (`teamA`/`teamB`), so
  /// updating only `teams/{id}` would leave already-generated matches
  /// showing the old name. Written in chunked batches (400 ops) to stay
  /// under Firestore's 500-op limit; see [matchesNeedingNameUpdate].
  Future<void> updateTeam(String teamId, {required String name}) async {
    try {
      final matchesRef = _db.collection(matchesCollection);
      final asA = await matchesRef.where('teamA.teamId', isEqualTo: teamId).get();
      final asB = await matchesRef.where('teamB.teamId', isEqualTo: teamId).get();
      final matches = [...asA.docs, ...asB.docs].map(Match.fromFirestore).toList();
      final updates = matchesNeedingNameUpdate(matches, teamId: teamId, newName: name);

      // The team doc itself goes in the first chunk.
      final ops = <void Function(WriteBatch)>[
        (b) => b.update(_db.collection(teamsCollection).doc(teamId), {'name': name}),
        for (final u in updates) (b) => b.update(matchesRef.doc(u.matchId), u.fields),
      ];
      for (var i = 0; i < ops.length; i += 400) {
        final batch = _db.batch();
        for (final op in ops.skip(i).take(400)) {
          op(batch);
        }
        await batch.commit();
      }
    } catch (e) {
      throw FirestoreWriteException('Could not update team.', e);
    }
  }

  /// [section] is the team's new league section (e.g. 'A', 'B'), or null to
  /// clear it back to a non-sectioned team.
  Future<void> updateTeamSection(String teamId, String? section) async {
    try {
      await _db.collection(teamsCollection).doc(teamId).update({'section': section});
    } catch (e) {
      throw FirestoreWriteException('Could not update team section.', e);
    }
  }

  Future<void> deleteTeam(String teamId) async {
    try {
      await _db.collection(teamsCollection).doc(teamId).delete();
    } catch (e) {
      throw FirestoreWriteException('Could not delete team.', e);
    }
  }

  /// Cricket matches are stamped with the tournament's current default rules
  /// at the moment they are created (schedule, knockout, tie-breaker, decider
  /// or a manual match all come through here), so changing the default later
  /// never alters a match that already exists. Other sports pass through
  /// untouched, with no extra read.
  Future<List<Match>> _withCricketRules(List<Match> matches) async {
    if (!matches.any(needsCricketRules)) return matches;
    final doc = await _db.collection(configCollection).doc('cricketRules').get();
    return stampCricketRules(matches, CricketRules.fromMap(doc.data()));
  }

  Future<void> addMatch(Match match) async {
    try {
      final stamped = (await _withCricketRules([match])).single;
      await _db.collection(matchesCollection).add(stamped.toFirestore());
    } catch (e) {
      throw FirestoreWriteException('Could not add match.', e);
    }
  }

  /// Writes a batch of freshly generated matches (e.g. from generateLeagueMatches
  /// or generateKnockoutMatches). Caller should first confirm none already exist
  /// for that sport+category+stage to avoid accidental double-generation.
  Future<void> addMatchesBatch(List<Match> matches) async {
    try {
      final stamped = await _withCricketRules(matches);
      final batch = _db.batch();
      for (final m in stamped) {
        final ref = _db.collection(matchesCollection).doc();
        batch.set(ref, m.toFirestore());
      }
      await batch.commit();
    } catch (e) {
      throw FirestoreWriteException('Could not save the generated matches.', e);
    }
  }

  Future<void> updateMatch(String matchId, Map<String, dynamic> fields) async {
    try {
      await _db.collection(matchesCollection).doc(matchId).update(fields);
    } catch (e) {
      throw FirestoreWriteException('Could not save changes.', e);
    }
  }

  /// Deletes a match together with the sub-collections it owns. The match and
  /// its commentary go in one batch; the append-only point log can only be
  /// removed once the match no longer exists (the rule allows it exactly
  /// then), so it is cleared second — and skipped, not fatal, if the rules
  /// haven't been updated yet (those orphaned entries are never read again).
  Future<void> _deleteMatchDocs(List<DocumentReference<Map<String, dynamic>>> matchRefs) async {
    for (final ref in matchRefs) {
      final commentary = await ref.collection(commentaryCollection).get();
      final pointLog = await ref.collection(pointLogCollection).get();
      final batch = _db.batch();
      batch.delete(ref);
      for (final d in commentary.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      for (var i = 0; i < pointLog.docs.length; i += 400) {
        final b = _db.batch();
        for (final d in pointLog.docs.skip(i).take(400)) {
          b.delete(d.reference);
        }
        try {
          await b.commit();
        } on FirebaseException catch (e) {
          if (e.code != 'permission-denied') rethrow;
          break;
        }
      }
    }
  }

  Future<void> deleteMatch(String matchId) async {
    try {
      await _deleteMatchDocs([_db.collection(matchesCollection).doc(matchId)]);
    } catch (e) {
      throw FirestoreWriteException('Could not delete match.', e);
    }
  }

  /// How many matches (any stage, any status) involve [teamId] on either side.
  Future<int> countMatchesForTeam(String teamId) async {
    final matches = _db.collection(matchesCollection);
    final a = await matches.where('teamA.teamId', isEqualTo: teamId).count().get();
    final b = await matches.where('teamB.teamId', isEqualTo: teamId).count().get();
    return (a.count ?? 0) + (b.count ?? 0);
  }

  /// Deletes every match (all categories, all stages — league, knockout,
  /// tie-breaker, friendly) for a sport within a season, with their
  /// commentary and point logs. Teams are left untouched, so live-flow testing
  /// can repeat without re-entering rosters each time.
  Future<void> resetSportMatches({required String sport, required String season}) async {
    try {
      final snap = await _db
          .collection(matchesCollection)
          .where('sport', isEqualTo: sport)
          .where('season', isEqualTo: season)
          .get();
      await _deleteMatchDocs([for (final d in snap.docs) d.reference]);
    } catch (e) {
      throw FirestoreWriteException('Could not reset matches.', e);
    }
  }

  /// Saves a result (scores computed to a MatchResult, status -> completed) and
  /// applies any dependent knockout-slot resolutions in one atomic batch write,
  /// so two admins editing at once can't leave the bracket half-updated.
  Future<void> saveResultAndResolveDependents({
    required String matchId,
    required int scoreA,
    required int scoreB,
    required MatchResult result,
    required List<Match> dependentUpdates,
  }) async {
    try {
      final batch = _db.batch();
      batch.update(_db.collection(matchesCollection).doc(matchId), {
        'scoreA': scoreA,
        'scoreB': scoreB,
        'result': result.name,
        'status': MatchStatus.completed.name,
      });
      for (final m in dependentUpdates) {
        batch.update(_db.collection(matchesCollection).doc(m.id), {
          'teamA': m.teamA.toMap(),
          'teamB': m.teamB.toMap(),
        });
      }
      await batch.commit();
    } catch (e) {
      throw FirestoreWriteException('Could not save the result.', e);
    }
  }

  /// Atomically adjusts a match's reaction count for [emoji] by [delta]
  /// (1 to react, -1 to undo). Cheap enough to allow without admin auth: it
  /// rides on the same match doc viewers already stream via
  /// [watchMatch]/[watchMatches], no extra reads.
  Future<void> incrementReaction(String matchId, String emoji, {int delta = 1}) async {
    try {
      await _db
          .collection(matchesCollection)
          .doc(matchId)
          .update({'reactionCounts.$emoji': FieldValue.increment(delta)});
    } catch (e) {
      throw FirestoreWriteException('Could not update reaction.', e);
    }
  }

  /// Casts (or switches) a viewer's "who wins" prediction for [matchId]. If
  /// [previousChoice] is given (the device already had a pick), that count
  /// is decremented in the same write that increments [choice] — an atomic
  /// switch rather than two separate round trips. Same trust level as
  /// reactions: cheap enough for no admin auth, rides on the existing match
  /// doc stream, no extra reads.
  Future<void> castPrediction(String matchId, {required String choice, String? previousChoice}) async {
    try {
      final updates = {'predictionCounts.$choice': FieldValue.increment(1)};
      if (previousChoice != null && previousChoice != choice) {
        updates['predictionCounts.$previousChoice'] = FieldValue.increment(-1);
      }
      await _db.collection(matchesCollection).doc(matchId).update(updates);
    } catch (e) {
      throw FirestoreWriteException('Could not save your prediction.', e);
    }
  }

  /// Moving a match away from `completed` also clears its `result`, so a match
  /// that is reset to upcoming (or restarted live) stops counting in standings
  /// and the podium. The scores themselves are kept — nothing entered is
  /// thrown away; saving the result again re-completes it.
  Future<void> setMatchStatus(String matchId, MatchStatus status) async {
    try {
      await _db.collection(matchesCollection).doc(matchId).update({
        'status': status.name,
        if (status != MatchStatus.completed) 'result': null,
      });
    } catch (e) {
      throw FirestoreWriteException('Could not update match status.', e);
    }
  }

  /// Resets a completed knockout match and, in the same batch, sets the
  /// downstream slots it had filled back to TBD, so nobody stays advanced on a
  /// result that no longer exists. [unresolved] are the not-yet-started
  /// dependents with those slots already cleared (see
  /// `unresolveDependentSlots`).
  Future<void> resetKnockoutMatch(
    String matchId,
    MatchStatus status, {
    required List<Match> unresolved,
  }) async {
    try {
      final batch = _db.batch();
      batch.update(_db.collection(matchesCollection).doc(matchId), {
        'status': status.name,
        'result': null,
      });
      for (final m in unresolved) {
        batch.update(_db.collection(matchesCollection).doc(m.id), {
          'teamA': m.teamA.toMap(),
          'teamB': m.teamB.toMap(),
        });
      }
      await batch.commit();
    } catch (e) {
      throw FirestoreWriteException('Could not reset the match.', e);
    }
  }

  /// [scheduledAt] is null to clear/cancel a previously set date & time.
  Future<void> setMatchSchedule(String matchId, DateTime? scheduledAt) async {
    try {
      await _db.collection(matchesCollection).doc(matchId).update({
        'scheduledAt': scheduledAt == null ? null : Timestamp.fromDate(scheduledAt),
      });
    } catch (e) {
      throw FirestoreWriteException('Could not update the match schedule.', e);
    }
  }

  // --- Presence (admin install/active-now counts) ---

  /// One-time write for a device's very first ever app open — sets both
  /// `firstSeenAt` and `lastSeenAt` in a single atomic write, so there's no
  /// window where the doc exists with only one of them. Safe to retry (same
  /// doc id every time): a retry just means `firstSeenAt` ends up slightly
  /// later than the true first launch, never a duplicate or a race.
  Future<void> registerPresence({required String deviceId, required int appVersion}) async {
    try {
      await _db.collection(presenceCollection).doc(deviceId).set({
        'deviceId': deviceId,
        'firstSeenAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
        'appVersion': appVersion,
      });
    } catch (e) {
      throw FirestoreWriteException('Could not register presence.', e);
    }
  }

  /// Called on every later app open/resume — only touches `lastSeenAt` (and
  /// `appVersion`, in case the device updated since its last heartbeat).
  /// Requires the doc to already exist (see [registerPresence]); the rules
  /// deny an update against a nonexistent doc, same as any other update.
  Future<void> heartbeat({required String deviceId, required int appVersion}) async {
    try {
      await _db.collection(presenceCollection).doc(deviceId).update({
        'lastSeenAt': FieldValue.serverTimestamp(),
        'appVersion': appVersion,
      });
    } catch (e) {
      throw FirestoreWriteException('Could not update presence.', e);
    }
  }

  /// Total unique devices that have ever opened the app at least once —
  /// this can only grow, since there's no way to detect an uninstall.
  Future<int> fetchInstallCount() async {
    final result = await _db.collection(presenceCollection).count().get();
    return result.count ?? 0;
  }

  /// Devices whose most recent heartbeat (app open/resume) was within
  /// [window] of now — a rough proxy for "using the app right now."
  Future<int> fetchActiveCount({Duration window = const Duration(minutes: 5)}) async {
    final cutoff = Timestamp.fromDate(DateTime.now().subtract(window));
    final result = await _db
        .collection(presenceCollection)
        .where('lastSeenAt', isGreaterThan: cutoff)
        .count()
        .get();
    return result.count ?? 0;
  }

  // --- Seasons ---

  /// A fresh Firestore-generated id for a new season doc, without a network
  /// round trip — the caller uses it to build the Season before saving.
  String newSeasonId() => _db.collection(seasonsCollection).doc().id;

  Stream<List<Season>> watchSeasons() {
    return _db
        .collection(seasonsCollection)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Season.fromFirestore).toList());
  }

  Future<void> createSeason(Season season) async {
    try {
      await _db.collection(seasonsCollection).doc(season.id).set(season.toFirestore());
    } catch (e) {
      throw FirestoreWriteException('Could not create season.', e);
    }
  }

  Future<void> updateSeason(String seasonId, Map<String, dynamic> fields) async {
    try {
      await _db.collection(seasonsCollection).doc(seasonId).update(fields);
    } catch (e) {
      throw FirestoreWriteException('Could not update season.', e);
    }
  }

  Future<void> setActiveSeason(String seasonId) async {
    try {
      await _db.collection(configCollection).doc('activeSeason').set({'seasonId': seasonId});
    } catch (e) {
      throw FirestoreWriteException('Could not switch season.', e);
    }
  }

  Future<void> setChatEnabled(bool enabled) async {
    try {
      await _db.collection(configCollection).doc('chatSettings').set({'enabled': enabled});
    } catch (e) {
      throw FirestoreWriteException('Could not update chat settings.', e);
    }
  }

  /// [text] empty clears the Home-screen announcement.
  Future<void> setAnnouncement(String text) async {
    try {
      await _db.collection(configCollection).doc('announcement').set({
        'text': text,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw FirestoreWriteException('Could not update the announcement.', e);
    }
  }

  // --- Chat ---

  /// Bounded window of the most recent messages, newest first — kept small
  /// via [chatWindowSize] so this live listener stays cheap regardless of
  /// how much the collection grows over the event (see rules/model docs).
  Stream<List<ChatMessage>> watchRecentChatMessages({required String season, int limit = chatWindowSize}) {
    return _db
        .collection(chatMessagesCollection)
        .where('season', isEqualTo: season)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(ChatMessage.fromFirestore).toList());
  }

  Future<void> sendChatMessage(ChatMessage message) async {
    try {
      await _db.collection(chatMessagesCollection).add(message.toFirestore());
    } catch (e) {
      throw FirestoreWriteException('Could not send message.', e);
    }
  }

  /// Moderation: removes a message. Already covered by the existing
  /// `allow update, delete: if isAdmin()` chat rule — no rules change needed.
  Future<void> deleteChatMessage(String messageId) async {
    try {
      await _db.collection(chatMessagesCollection).doc(messageId).delete();
    } catch (e) {
      throw FirestoreWriteException('Could not delete message.', e);
    }
  }

  // --- Commentary ---

  /// Chronological (oldest first) live-commentary feed for one match, capped
  /// defensively even though a single match realistically only ever
  /// accumulates a few dozen entries.
  Stream<List<CommentaryEntry>> watchCommentary(String matchId, {int limit = 100}) {
    return _db
        .collection(matchesCollection)
        .doc(matchId)
        .collection(commentaryCollection)
        .orderBy('createdAt')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(CommentaryEntry.fromFirestore).toList());
  }

  /// Also denormalizes the entry's text/time onto the match doc itself
  /// (`lastCommentaryText`/`lastCommentaryAt`), in the same batch, so the
  /// match list can preview the latest entry without an extra listener per
  /// card — same cost-conscious pattern as `reactionCounts`.
  Future<void> postCommentary(String matchId, CommentaryEntry entry) async {
    try {
      final matchRef = _db.collection(matchesCollection).doc(matchId);
      final entryRef = matchRef.collection(commentaryCollection).doc();
      final batch = _db.batch();
      batch.set(entryRef, entry.toFirestore());
      batch.update(matchRef, {
        'lastCommentaryText': entry.text,
        'lastCommentaryAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } catch (e) {
      throw FirestoreWriteException('Could not post commentary.', e);
    }
  }

  // --- Live score (point log) ---

  /// Atomically bumps [team]'s score by [delta] (+1 to record a point, -1 to
  /// undo a wrong tap) and appends a [PointLogEntry] with the resultant
  /// score, in one transaction — a transaction rather than a plain
  /// increment-and-batch because the resultant score has to be *read* before
  /// it can be logged, and because the result is clamped at 0 (so a stray
  /// extra -1 tap can't go negative). Returns the resultant (scoreA, scoreB)
  /// so the caller can keep its own final-score fields in sync without a
  /// redundant read.
  Future<(int scoreA, int scoreB)> incrementLiveScore(
    String matchId, {
    required String team, // 'A' or 'B'
    required int delta, // +1 or -1
  }) async {
    try {
      final matchRef = _db.collection(matchesCollection).doc(matchId);
      return await _db.runTransaction((tx) async {
        final snap = await tx.get(matchRef);
        var scoreA = (snap.data()?['scoreA'] as int?) ?? 0;
        var scoreB = (snap.data()?['scoreB'] as int?) ?? 0;
        if (team == 'A') {
          scoreA = (scoreA + delta).clamp(0, 999);
        } else {
          scoreB = (scoreB + delta).clamp(0, 999);
        }
        tx.update(matchRef, {'scoreA': scoreA, 'scoreB': scoreB});
        tx.set(
          matchRef.collection(pointLogCollection).doc(),
          PointLogEntry(id: '', team: team, scoreA: scoreA, scoreB: scoreB, createdAt: null)
              .toFirestore(),
        );
        return (scoreA, scoreB);
      });
    } catch (e) {
      throw FirestoreWriteException('Could not update the live score.', e);
    }
  }

  /// Chronological (oldest first) point-by-point log for one match — same
  /// shape/limit reasoning as [watchCommentary].
  Stream<List<PointLogEntry>> watchPointLog(String matchId, {int limit = 200}) {
    return _db
        .collection(matchesCollection)
        .doc(matchId)
        .collection(pointLogCollection)
        .orderBy('createdAt')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(PointLogEntry.fromFirestore).toList());
  }
}
