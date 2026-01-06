// services/like_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class LikeService {
  final _db = FirebaseFirestore.instance;

  Stream<int> getLikeCount(String postId) {
    return _db
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Future<void> toggleLike(String postId, String userId) async {
    final ref = _db.collection('posts').doc(postId).collection('likes').doc(userId);
    final doc = await ref.get();
    if (doc.exists) {
      await ref.delete();
    } else {
      await ref.set({'likedAt': FieldValue.serverTimestamp()});
    }
  }

  Stream<bool> isLiked(String postId, String userId) {
    return _db
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists);
  }
}
