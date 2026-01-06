import 'package:cloud_firestore/cloud_firestore.dart'; // ⬅ szükséges!

class Post {
  final String id;
  final String userId;
  final String username;
  final String imageUrl;
  final String text;
  final DateTime timestamp;
  final bool pinned; // ⬅ ÚJ mező!

  Post({
    required this.id,
    required this.userId,
    required this.username,
    required this.imageUrl,
    required this.text,
    required this.timestamp,
    this.pinned = false, // ⬅ Alapértelmezett érték!
  });

  factory Post.fromJson(Map<String, dynamic> json) => Post(
    id: json['id'],
    userId: json['userId'],
    username: json['username'],
    imageUrl: json['imageUrl'],
    text: json['text'],
    timestamp: (json['timestamp'] as Timestamp).toDate(),
    pinned: json['pinned'] ?? false, // ⬅ Olvassa a Firestore-ból!
  );

  Map<String, dynamic> toJson() {
    return {
      'id': id, // ⬅ Ez is kerüljön bele!
      'userId': userId,
      'username': username,
      'imageUrl': imageUrl,
      'text': text,
      'timestamp': timestamp,
      'pinned': pinned, // ⬅ Ez is mentésre kerül!
    };
  }
}
