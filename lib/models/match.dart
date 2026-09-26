import 'package:cloud_firestore/cloud_firestore.dart';

enum MatchStage { league, knockout, tiebreaker }

enum MatchStatus { upcoming, live, completed }

enum MatchResult { teamA, teamB, tie }

MatchStage stageFromString(String s) =>
    MatchStage.values.firstWhere((e) => e.name == s, orElse: () => MatchStage.league);

MatchStatus statusFromString(String s) => MatchStatus.values
    .firstWhere((e) => e.name == s, orElse: () => MatchStatus.upcoming);

MatchResult? resultFromString(String? s) {
  if (s == null) return null;
  return MatchResult.values.firstWhere((e) => e.name == s);
}

/// A resolved-or-TBD reference to one side of a match.
class TeamRef {
  final String? teamId;
  final String? name;

  const TeamRef({this.teamId, this.name});

  bool get isTbd => teamId == null;

  static const TeamRef tbd = TeamRef();

  factory TeamRef.fromMap(Map<String, dynamic>? map) {
    if (map == null) return TeamRef.tbd;
    return TeamRef(teamId: map['teamId'] as String?, name: map['name'] as String?);
  }

  Map<String, dynamic> toMap() => {'teamId': teamId, 'name': name};
}

/// Describes how a knockout slot should be auto-filled once its dependency resolves.
/// type is one of: "seed", "winner", "loser".
class MatchSource {
  final String type;
  final int? seed;
  final String? matchCode;

  const MatchSource.seed(this.seed)
      : type = 'seed',
        matchCode = null;

  const MatchSource.winnerOf(this.matchCode)
      : type = 'winner',
        seed = null;

  const MatchSource.loserOf(this.matchCode)
      : type = 'loser',
        seed = null;

  const MatchSource._raw(this.type, this.seed, this.matchCode);

  static MatchSource? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    return MatchSource._raw(
      map['type'] as String,
      map['seed'] as int?,
      map['matchCode'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {'type': type, 'seed': seed, 'matchCode': matchCode};
}

class Match {
  final String id;
  final String sport;
  final String category;
  final String season;
  final MatchStage stage;
  final int matchNumber;
  final String label;
  final String matchCode;

  final TeamRef teamA;
  final TeamRef teamB;
  final MatchSource? teamASource;
  final MatchSource? teamBSource;

  final int? scoreA;
  final int? scoreB;
  final MatchResult? result;

  final MatchStatus status;

  final DateTime? scheduledAt;
  final String? venue;
  final String? court;
  final String? notes;

  final String notifyTopic;

  /// Viewer reaction tap counts, keyed by [ReactionEmoji] key. Absent on
  /// docs written before this feature, hence the empty-map default.
  final Map<String, int> reactionCounts;

  /// Only set for `stage == tiebreaker` matches: which tie-breaker round this
  /// belongs to (1, 2, ...). A tie-breaker can itself end in another tie
  /// among some or all of its teams, needing a fresh round among just the
  /// still-tied subset — this distinguishes that new round's matches from
  /// the earlier one's, since both can involve overlapping/identical teams.
  final int? tiebreakerRound;

  Match({
    required this.id,
    required this.sport,
    required this.category,
    required this.season,
    required this.stage,
    required this.matchNumber,
    required this.label,
    required this.matchCode,
    required this.teamA,
    required this.teamB,
    this.teamASource,
    this.teamBSource,
    this.scoreA,
    this.scoreB,
    this.result,
    this.status = MatchStatus.upcoming,
    this.scheduledAt,
    this.venue,
    this.court,
    this.notes,
    required this.notifyTopic,
    this.reactionCounts = const {},
    this.tiebreakerRound,
  });

  factory Match.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Match(
      id: doc.id,
      sport: data['sport'] as String,
      category: data['category'] as String,
      season: data['season'] as String? ?? '',
      stage: stageFromString(data['stage'] as String),
      matchNumber: data['matchNumber'] as int,
      label: data['label'] as String,
      matchCode: data['matchCode'] as String,
      teamA: TeamRef.fromMap(data['teamA'] as Map<String, dynamic>?),
      teamB: TeamRef.fromMap(data['teamB'] as Map<String, dynamic>?),
      teamASource: MatchSource.fromMap(data['teamASource'] as Map<String, dynamic>?),
      teamBSource: MatchSource.fromMap(data['teamBSource'] as Map<String, dynamic>?),
      scoreA: data['scoreA'] as int?,
      scoreB: data['scoreB'] as int?,
      result: resultFromString(data['result'] as String?),
      status: statusFromString(data['status'] as String? ?? 'upcoming'),
      scheduledAt: (data['scheduledAt'] as Timestamp?)?.toDate(),
      venue: data['venue'] as String?,
      court: data['court'] as String?,
      notes: data['notes'] as String?,
      notifyTopic: data['notifyTopic'] as String? ?? '',
      reactionCounts: (data['reactionCounts'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          const {},
      tiebreakerRound: data['tiebreakerRound'] as int?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'sport': sport,
        'category': category,
        'season': season,
        'stage': stage.name,
        'matchNumber': matchNumber,
        'label': label,
        'matchCode': matchCode,
        'teamA': teamA.toMap(),
        'teamB': teamB.toMap(),
        'teamASource': teamASource?.toMap(),
        'teamBSource': teamBSource?.toMap(),
        'scoreA': scoreA,
        'scoreB': scoreB,
        'result': result?.name,
        'status': status.name,
        'scheduledAt': scheduledAt == null ? null : Timestamp.fromDate(scheduledAt!),
        'venue': venue,
        'court': court,
        'notes': notes,
        'notifyTopic': notifyTopic,
        'tiebreakerRound': tiebreakerRound,
      };

  /// Computes the result from scores the moment they're saved, mirroring the
  /// source spreadsheet's Winner formula (tie modeled for fidelity even though
  /// a completed badminton game can't actually finish level).
  static MatchResult? computeResult(int? scoreA, int? scoreB) {
    if (scoreA == null || scoreB == null) return null;
    if (scoreA == scoreB) return MatchResult.tie;
    return scoreA > scoreB ? MatchResult.teamA : MatchResult.teamB;
  }
}
