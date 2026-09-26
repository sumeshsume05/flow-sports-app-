import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String text;
  final String authorName;
  final String authorDeviceId;
  final DateTime? createdAt;
  final String season;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.authorName,
    required this.authorDeviceId,
    required this.createdAt,
    required this.season,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return ChatMessage(
      id: doc.id,
      text: data['text'] as String,
      authorName: data['authorName'] as String,
      authorDeviceId: data['authorDeviceId'] as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      season: data['season'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'text': text,
        'authorName': authorName,
        'authorDeviceId': authorDeviceId,
        'createdAt': FieldValue.serverTimestamp(),
        'season': season,
      };
}
