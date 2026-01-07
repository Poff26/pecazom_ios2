import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';

class PostService {
  final _db = FirebaseFirestore.instance;

  Future<void> addPost(Post post) async {
    await _db.collection('posts').doc(post.id).set(post.toJson());
  }

  Stream<List<Post>> getPosts() {
    return _db
        .collection('posts')
        .orderBy('pinned', descending: true) // Kitűzött posztok előre
        .orderBy('timestamp', descending: true) // Frissek fentebb
        .snapshots()
        .map((snap) => snap.docs
        .map((doc) => Post.fromJson({...doc.data(), 'id': doc.id}))
        .toList());
  }

  Future<void> deletePost(String postId) async {
    await _db.collection('posts').doc(postId).delete();
  }
}

Future<bool> isCurrentUserAdmin() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;

  final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  return doc.exists && doc.data()?['role'] == 'admin';
}
