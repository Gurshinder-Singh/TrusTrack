import 'package:cloud_firestore/cloud_firestore.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> streamMessages(
      String circleCode) {
    return _db
        .collection('sessions')
        .doc(circleCode.trim().toUpperCase())
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> sendMessage({
    required String circleCode,
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    final cleanText = text.trim();

    if (cleanText.isEmpty) return;

    await _db
        .collection('sessions')
        .doc(circleCode.trim().toUpperCase())
        .collection('messages')
        .add({
      'senderId': senderId,
      'senderName': senderName,
      'text': cleanText,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
