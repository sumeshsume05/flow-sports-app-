import 'package:cloud_firestore/cloud_firestore.dart';

class CommentaryEntry {
  final String id;
  final String text;
  final DateTime? createdAt;
  final String postedByUid;

  const CommentaryEntry({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.postedByUid,
  });

  factory CommentaryEntry.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return CommentaryEntry(
      id: doc.id,
      text: data['text'] as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      postedByUid: data['postedByUid'] as String,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'postedByUid': postedByUid,
      };
}
