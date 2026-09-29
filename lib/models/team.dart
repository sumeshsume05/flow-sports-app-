import 'package:cloud_firestore/cloud_firestore.dart';

class Team {
  final String id;
  final String sport;
  final String category;
  final String name;
  final int? seed;
  final String season;

  /// Which league section this team belongs to (e.g. 'A', 'B'), or null when
  /// the category uses a single flat round-robin. Absent on every team
  /// written before this field existed — that's the same as null, and the
  /// whole category is treated as non-sectioned until every team in it has a
  /// section assigned. See round_robin.generateSectionedLeagueMatches.
  final String? section;

  Team({
    required this.id,
    required this.sport,
    required this.category,
    required this.name,
    required this.season,
    this.seed,
    this.section,
  });

  factory Team.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Team(
      id: doc.id,
      sport: data['sport'] as String,
      category: data['category'] as String,
      name: data['name'] as String,
      season: data['season'] as String? ?? '',
      seed: data['seed'] as int?,
      section: data['section'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'sport': sport,
        'category': category,
        'name': name,
        'season': season,
        'seed': seed,
        'section': section,
      };

  Team copyWith({int? seed, String? section}) => Team(
        id: id,
        sport: sport,
        category: category,
        name: name,
        season: season,
        seed: seed ?? this.seed,
        section: section ?? this.section,
      );

  // Value equality by id — Firestore snapshots rebuild fresh Team instances
  // on every emission, and widgets like DropdownButtonFormField compare
  // selected values by == against the current items list, so identity
  // equality would spuriously fail even when the same team is selected.
  @override
  bool operator ==(Object other) => other is Team && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
