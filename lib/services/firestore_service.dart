import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
import '../models/chat_message.dart';
import '../models/commentary_entry.dart';
import '../models/match.dart';
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

  Future<void> addTeam(Team team) async {
    try {
      await _db.collection(teamsCollection).add(team.toFirestore());
    } catch (e) {
      throw FirestoreWriteException('Could not add team.', e);
    }
  }

  Future<void> updateTeam(String teamId, {required String name}) async {
    try {
      await _db.collection(teamsCollection).doc(teamId).update({'name': name});
    } catch (e) {
      throw FirestoreWriteException('Could not update team.', e);
    }
  }

  Future<void> deleteTeam(String teamId) async {
    try {
      await _db.collection(teamsCollection).doc(teamId).delete();
    } catch (e) {
      throw FirestoreWriteException('Could not delete team.', e);
    }
  }

  Future<void> addMatch(Match match) async {
    try {
      await _db.collection(matchesCollection).add(match.toFirestore());
    } catch (e) {
      throw FirestoreWriteException('Could not add match.', e);
    }
  }

  /// Writes a batch of freshly generated matches (e.g. from generateLeagueMatches
  /// or generateKnockoutMatches). Caller should first confirm none already exist
  /// for that sport+category+stage to avoid accidental double-generation.
  Future<void> addMatchesBatch(List<Match> matches) async {
    try {
      final batch = _db.batch();
      for (final m in matches) {
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

  Future<void> deleteMatch(String matchId) async {
    try {
      await _db.collection(matchesCollection).doc(matchId).delete();
    } catch (e) {
      throw FirestoreWriteException('Could not delete match.', e);
    }
  }

  /// Deletes every match (all categories, all stages — league, knockout,
  /// tie-breaker) for a sport within a season, in batches of 400 to stay
  /// under Firestore's 500-op batch limit. Teams are left untouched, so
  /// live-flow testing can repeat without re-entering rosters each time.
  Future<void> resetSportMatches({required String sport, required String season}) async {
    try {
      final snap = await _db
          .collection(matchesCollection)
          .where('sport', isEqualTo: sport)
          .where('season', isEqualTo: season)
          .get();
      final docs = snap.docs;
      for (var i = 0; i < docs.length; i += 400) {
        final chunk = docs.skip(i).take(400);
        final batch = _db.batch();
        for (final d in chunk) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
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

  Future<void> setMatchStatus(String matchId, MatchStatus status) async {
    try {
      await _db.collection(matchesCollection).doc(matchId).update({'status': status.name});
    } catch (e) {
      throw FirestoreWriteException('Could not update match status.', e);
    }
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
}
