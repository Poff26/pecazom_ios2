// lib/services/pin_services.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';

import '../models/fishing_pin.dart';

class PinService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------------------------
  // LOCAL IMAGE STORAGE
  // ---------------------------

  /// Lokális képmentés az app dokumentum könyvtárába: /fishing_pins/<pinId>.jpg
  Future<String> saveImageLocally(File imageFile, String pinId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${appDir.path}/fishing_pins');
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    final saved = await imageFile.copy('${imageDir.path}/$pinId.jpg');
    return saved.path;
  }

  // ---------------------------
  // CREATE
  // ---------------------------

  /// Új pin mentése Firestore-ba + opcionális lokális kép
  Future<void> addPin(FishingPin pin, File? imageFile) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw Exception('Nincs bejelentkezett felhasználó.');
    }

    String? localPath;
    if (imageFile != null) {
      localPath = await saveImageLocally(imageFile, pin.id);
    }

    final data = pin.toJson()
      ..['userId'] = uid
      ..['imageUrl'] = localPath;

    // Ha nálad a docId = pin.id, akkor így jó:
    await _db.collection('fishing_pins').doc(pin.id).set(data);
  }

  // ---------------------------
  // READ (ONE-TIME)
  // ---------------------------

  /// Jelenlegi felhasználóhoz tartozó pinek egyszeri lekérése
  Future<List<FishingPin>> fetchPins(String uid, {int limit = 300}) async {
    final snap = await _db
        .collection('fishing_pins')
        .where('userId', isEqualTo: uid)
        .limit(limit)
        .get();

    return snap.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return FishingPin.fromJson(data);
    }).toList();
  }

  // ---------------------------
  // READ (REAL-TIME STREAM)  ✅ watchPins
  // ---------------------------

  /// Pinek streamelése (MapScreen gyorsításához)
  Stream<List<FishingPin>> watchPins(String uid, {int limit = 300}) {
    return _db
        .collection('fishing_pins')
        .where('userId', isEqualTo: uid)
        .limit(limit)
        .snapshots()
        .map((snap) {
      return snap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return FishingPin.fromJson(data);
      }).toList();
    });
  }

  // ---------------------------
  // UPDATE  ✅ updatePin
  // ---------------------------

  Future<void> updatePin(
      FishingPin pin, {
        File? newImage,
        bool deleteExistingImageIfAny = false,
      }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Nincs bejelentkezett felhasználó.');

    if (pin.userId.isNotEmpty && pin.userId != uid) {
      throw Exception('Nincs jogosultság a pin módosításához.');
    }

    String? imagePath = pin.imageUrl;

    // régi kép törlése (ha kért)
    if (deleteExistingImageIfAny && imagePath != null && imagePath.isNotEmpty) {
      final old = File(imagePath);
      if (await old.exists()) {
        try {
          await old.delete();
        } catch (_) {}
      }
      imagePath = null;
    }

    // új kép mentése (ha van)
    if (newImage != null) {
      if (imagePath != null && imagePath.isNotEmpty) {
        final old = File(imagePath);
        if (await old.exists()) {
          try {
            await old.delete();
          } catch (_) {}
        }
      }
      imagePath = await saveImageLocally(newImage, pin.id);
    }

    final data = pin.toJson()
      ..['userId'] = uid
      ..['imageUrl'] = imagePath;

    await _db.collection('fishing_pins').doc(pin.id).set(
      data,
      SetOptions(merge: true),
    );
  }

  // ---------------------------
  // DELETE  ✅ deletePin
  // ---------------------------

  Future<void> deletePin(FishingPin pin) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Nincs bejelentkezett felhasználó.');

    if (pin.userId.isNotEmpty && pin.userId != uid) {
      throw Exception('Nincs jogosultság a pin törléséhez.');
    }

    await _db.collection('fishing_pins').doc(pin.id).delete();

    final path = pin.imageUrl;
    if (path != null && path.isNotEmpty) {
      final f = File(path);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }
}
