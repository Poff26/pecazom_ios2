import 'package:cloud_firestore/cloud_firestore.dart';

class AiPurchaseService {
  AiPurchaseService(this._db);

  final FirebaseFirestore _db;

  /// Returns: true if purchase succeeded (aiLevel deducted), false if insufficient balance
  Future<bool> buyForecastWithAiLevel({
    required String uid,
    int cost = 2,
  }) async {
    final userRef = _db.collection('users').doc(uid);

    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(userRef);
      if (!snap.exists) {
        // If user doc missing, treat as insufficient (or initialize elsewhere)
        return false;
      }

      final data = snap.data() as Map<String, dynamic>? ?? {};
      final current = (data['aiLevel'] as num?)?.toInt() ?? 0;

      if (current < cost) {
        return false;
      }

      tx.update(userRef, {
        'aiLevel': current - cost,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    });
  }
}
