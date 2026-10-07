import 'package:cloud_firestore/cloud_firestore.dart';

/// One tap of the admin's live-score +/- control, append-only — a
/// correction (a - tap) is its own new entry, never an edit of a previous
/// one, so the log stays an honest record of what actually happened.
/// [scoreA]/[scoreB] are the resultant score right after this tap, not a
/// delta, so the viewer-facing ticker can render each line standalone.
class PointLogEntry {
  final String id;
  final String team; // 'A' or 'B' — which team this tap was for
  final int scoreA;
  final int scoreB;
  final DateTime? createdAt;

  const PointLogEntry({
    required this.id,
    required this.team,
    required this.scoreA,
    required this.scoreB,
    required this.createdAt,
  });

  factory PointLogEntry.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return PointLogEntry(
      id: doc.id,
      team: data['team'] as String,
      scoreA: data['scoreA'] as int,
      scoreB: data['scoreB'] as int,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'team': team,
        'scoreA': scoreA,
        'scoreB': scoreB,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
