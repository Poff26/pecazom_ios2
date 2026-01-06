import 'package:cloud_firestore/cloud_firestore.dart';

class StatsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<int> getTotalPins(String uid) async {
    final snap = await _db
        .collection('fishing_pins')
        .where('userId', isEqualTo: uid)
        .get();
    return snap.docs.length;
  }

  Future<int> getTotalCatches(String uid) async {
    final snap = await _db
        .collection('fishing_catches')
        .where('userId', isEqualTo: uid)
        .get();
    return snap.docs.length;
  }
}
