import 'package:cloud_firestore/cloud_firestore.dart';

/// One dated tournament run (e.g. "March 2026 Sports Meet"). Every team and
/// match carries a `season` field equal to some Season's `id`, so switching
/// the active season changes which data every screen reads/writes without
/// mixing different runs together.
class Season {
  final String id;
  final String label;
  final DateTime date;
  final DateTime createdAt;

  Season({required this.id, required this.label, required this.date, required this.createdAt});

  factory Season.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Season(
      id: doc.id,
      label: data['label'] as String,
      date: (data['date'] as Timestamp).toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'label': label,
        'date': Timestamp.fromDate(date),
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
