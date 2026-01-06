// models/comment.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String postId;
  final String userId;
  final String username;
  final String text;
  final DateTime timestamp;

  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.username,
    required this.text,
    required this.timestamp,
  });

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: json['id'],
    postId: json['postId'],
    userId: json['userId'],
    username: json['username'],
    text: json['text'],
    timestamp: (json['timestamp'] as Timestamp).toDate(),
  );

  Map<String, dynamic> toJson() => {
    'postId': postId,
    'userId': userId,
    'username': username,
    'text': text,
    'timestamp': timestamp,
  };
}


