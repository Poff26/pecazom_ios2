// lib/screens/achievements_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'submitted_records_screen.dart';

class Achievement {
  final String id;
  final String title;
  final String description;
  final bool unlocked;

  Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.unlocked,
  });

  Achievement copyWith({bool? unlocked}) {
    return Achievement(
      id: id,
      title: title,
      description: description,
      unlocked: unlocked ?? this.unlocked,
    );
  }
}

final List<Achievement> allAchievements = [
  Achievement(id: 'firstCatch', title: 'Első fogás', description: 'Naplózz legalább egy fogást.', unlocked: false),
  Achievement(id: 'catch5kg', title: '5 kilós hal', description: 'Fogj legalább 5 kg-os halat.', unlocked: false),
  Achievement(id: 'catch10kg', title: '10 kilós hal', description: 'Fogj legalább 10 kg-os halat.', unlocked: false),
  Achievement(id: 'catch13kg', title: '13 kilós hal', description: 'Fogj legalább 13 kg-os halat.', unlocked: false),
  Achievement(id: 'catch15kg', title: '15 kilós hal', description: 'Fogj legalább 15 kg-os halat.', unlocked: false),
  Achievement(id: 'catch17kg', title: '17 kilós hal', description: 'Fogj legalább 17 kg-os halat.', unlocked: false),
  Achievement(id: 'catch20kg', title: '20 kilós hal', description: 'Fogj legalább 20 kg-os halat.', unlocked: false),
  Achievement(id: 'catch23kg', title: '23 kilós hal', description: 'Fogj legalább 23 kg-os halat.', unlocked: false),
  Achievement(id: 'catch25kg', title: '25 kilós hal', description: 'Fogj legalább 25 kg-os halat.', unlocked: false),
  Achievement(id: 'catch27kg', title: '27 kilós hal', description: 'Fogj legalább 27 kg-os halat.', unlocked: false),
  Achievement(id: 'catch30kg', title: '30 kilós hal', description: 'Fogj legalább 30 kg-os halat.', unlocked: false),
  Achievement(id: 'catch33kg', title: '33 kilós hal', description: 'Fogj legalább 33 kg-os halat.', unlocked: false),
  Achievement(id: 'catch35kg', title: '35 kilós hal', description: 'Fogj legalább 35 kg-os halat.', unlocked: false),
  Achievement(id: 'catch37kg', title: '37 kilós hal', description: 'Fogj legalább 37 kg-os halat.', unlocked: false),
  Achievement(id: 'catch40kg', title: '40 kilós hal', description: 'Fogj legalább 40 kg-os halat.', unlocked: false),
];

List<Achievement> buildAchievementsFromMap(
    Map<String, dynamic>? unlockedMap, {
      required bool signedIn,
    }) {
  final map = unlockedMap ?? <String, dynamic>{};
  return allAchievements.map((a) {
    if (!signedIn) return a.copyWith(unlocked: false);
    return a.copyWith(unlocked: map[a.id] == true);
  }).toList();
}

class AchievementsScreen extends StatefulWidget {
  // Meghagyjuk kompatibilitás miatt, de a képernyő nem erre támaszkodik.
  final String? userId;
  const AchievementsScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fishController = TextEditingController();
  final _weightController = TextEditingController();
  final _sizeController = TextEditingController();
  final _locationController = TextEditingController();
  final _baitController = TextEditingController();
  final _weatherController = TextEditingController();

  DateTime? _selectedDate;
  File? _selectedImage;

  @override
  void dispose() {
    _fishController.dispose();
    _weightController.dispose();
    _sizeController.dispose();
    _locationController.dispose();
    _baitController.dispose();
    _weatherController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _fishController.clear();
    _weightController.clear();
    _sizeController.clear();
    _locationController.clear();
    _baitController.clear();
    _weatherController.clear();
    _selectedDate = null;
    _selectedImage = null;
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
    );
    if (picked != null && mounted) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  String _friendlyError(Object e) {
    if (e is FirebaseException) {
      // Ne írjunk ki raw firebase errort a usernek.
      return 'Hiba történt. Kérlek próbáld újra.';
    }
    return 'Ismeretlen hiba történt. Kérlek próbáld újra.';
  }

  Future<bool> _submitRecord({required String uid}) async {
    if (!_formKey.currentState!.validate() || _selectedImage == null || _selectedDate == null) {
      return false;
    }

    try {
      final imageName = 'record_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child('records/$imageName');
      await ref.putFile(_selectedImage!);
      final imageUrl = await ref.getDownloadURL();

      final doc = FirebaseFirestore.instance.collection('record_reviews').doc();
      await doc.set({
        'userId': uid,
        'fishSpecies': _fishController.text.trim(),
        'fishWeight': double.parse(_weightController.text.trim().replaceAll(',', '.')),
        'fishSize': double.tryParse(_sizeController.text.trim().replaceAll(',', '.')),
        'location': _locationController.text.trim(),
        'bait': _baitController.text.trim(),
        'weather': _weatherController.text.trim(),
        'date': Timestamp.fromDate(_selectedDate!),
        'status': 'pending',
        'submittedAt': Timestamp.now(),
        'imageUrl': imageUrl,
      });

      // admin push (nem kritikus)
      try {
        await http.post(
          Uri.parse('https://catchsense-backend.onrender.com/send-push'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'title': 'Új rekord vár ellenőrzésre',
            'body': 'Egy új halrekord került beküldésre.',
            'role': 'admin',
          }),
        );
      } catch (_) {}

      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(e))),
        );
      }
      return false;
    }
  }

  void _showSignInRequired() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bejelentkezés szükséges'),
        content: const Text('Jelentkezz be, hogy rekordot küldhess be és lásd a feloldott eredményeidet.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showAddRecordModal({required String uid}) {
    _resetForm();

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        bool isSubmitting = false;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final scheme = Theme.of(context).colorScheme;

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: scheme.surface.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(Icons.add_photo_alternate_outlined, color: scheme.primary),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Új halrekord',
                                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Beküldés moderálásra. Kép és dátum kötelező.',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          height: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            _buildField(_fishController, 'Halfajta'),
                            _buildField(_weightController, 'Súly (kg)', isNumber: true),
                            _buildField(_sizeController, 'Méret (cm)', isNumber: true),
                            _buildField(_locationController, 'Helyszín'),
                            _buildField(_baitController, 'Csali'),
                            _buildField(_weatherController, 'Időjárás (opcionális)', requiredField: false),

                            const SizedBox(height: 10),
                            _inlinePickers(context),

                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: FilledButton(
                                onPressed: isSubmitting
                                    ? null
                                    : () async {
                                  if (_selectedDate == null || _selectedImage == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Kép és dátum megadása kötelező.')),
                                    );
                                    return;
                                  }

                                  setModalState(() => isSubmitting = true);
                                  final ok = await _submitRecord(uid: uid);
                                  setModalState(() => isSubmitting = false);

                                  if (ok && mounted) {
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Rekord beküldve ellenőrzésre.')),
                                    );
                                  } else if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('A beküldés nem sikerült.')),
                                    );
                                  }
                                },
                                child: isSubmitting
                                    ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 3),
                                )
                                    : const Text('Beküldés ellenőrzésre'),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                                child: const Text('Mégsem'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isSubmitting)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _inlinePickers(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final dateText = _selectedDate == null
        ? 'Dátum nincs kiválasztva'
        : 'Dátum: ${_selectedDate!.toIso8601String().split("T").first}';

    final imageText = _selectedImage == null ? 'Kép nincs kiválasztva' : 'Kép kiválasztva';

    Widget chip({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      required bool ok,
    }) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceVariant.withOpacity(0.55),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant.withOpacity(0.30)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: ok ? Colors.green.withOpacity(0.14) : scheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(ok ? Icons.check_circle : icon, color: ok ? Colors.green : scheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant, height: 1.15, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(
          icon: Icons.date_range_outlined,
          title: 'Dátum',
          subtitle: dateText,
          onTap: _pickDate,
          ok: _selectedDate != null,
        ),
        const SizedBox(width: 10),
        chip(
          icon: Icons.image_outlined,
          title: 'Kép',
          subtitle: imageText,
          onTap: _pickImage,
          ok: _selectedImage != null,
        ),
      ],
    );
  }

  Widget _buildField(
      TextEditingController controller,
      String label, {
        bool isNumber = false,
        bool requiredField = true,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        validator: (value) {
          if (!requiredField) return null;
          return value == null || value.trim().isEmpty ? 'Kötelező mező' : null;
        },
      ),
    );
  }

  // ---------------------------
  // UI
  // ---------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data;
        final signedIn = user != null;

        // KIJELENTKEZVE: NEM olvasunk Firestore-t.
        if (!signedIn) {
          final achievements = buildAchievementsFromMap(null, signedIn: false);
          return _buildScaffold(
            context,
            scheme,
            achievements: achievements,
            unlockedMap: null,
            signedIn: false,
            uid: null,
          );
        }

        // BEJELENTKEZVE: biztos uid
        final uid = user.uid;

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(
                backgroundColor: scheme.surface,
                appBar: AppBar(
                  title: const Text('Eredmények'),
                  elevation: 0,
                  backgroundColor: scheme.surface,
                  surfaceTintColor: scheme.surface,
                ),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return Scaffold(
                backgroundColor: scheme.surface,
                appBar: AppBar(
                  title: const Text('Eredmények'),
                  elevation: 0,
                  backgroundColor: scheme.surface,
                  surfaceTintColor: scheme.surface,
                ),
                body: _errorState(
                  context,
                  message: 'Nem sikerült betölteni az eredményeket.',
                  details: 'Kérlek próbáld újra.',
                  onRetry: () => setState(() {}),
                ),
              );
            }

            final data = snapshot.data?.data();
            final unlockedMap = (data?['achievements'] as Map<String, dynamic>?) ?? <String, dynamic>{};
            final achievements = buildAchievementsFromMap(unlockedMap, signedIn: true);

            return _buildScaffold(
              context,
              scheme,
              achievements: achievements,
              unlockedMap: unlockedMap,
              signedIn: true,
              uid: uid,
            );
          },
        );
      },
    );
  }

  Widget _buildScaffold(
      BuildContext context,
      ColorScheme scheme, {
        required List<Achievement> achievements,
        required Map<String, dynamic>? unlockedMap,
        required bool signedIn,
        required String? uid,
      }) {
    final unlockedCount = achievements.where((a) => a.unlocked).length;
    final total = achievements.length;
    final progress = total == 0 ? 0.0 : unlockedCount / total;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Eredmények'),
        elevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: _headerCard(
                context,
                unlockedCount: unlockedCount,
                total: total,
                progress: progress,
                signedIn: signedIn,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: _actionsCard(context, signedIn: signedIn, uid: uid),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                    (ctx, index) => _achievementTile(context, achievements[index], signedIn: signedIn),
                childCount: achievements.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.05,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState(
      BuildContext context, {
        required String message,
        required String details,
        required VoidCallback onRetry,
      }) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceVariant.withOpacity(0.45),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, color: scheme.primary, size: 30),
              const SizedBox(height: 10),
              Text(message, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                details,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.2),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Újrapróbálás'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCard(
      BuildContext context, {
        required int unlockedCount,
        required int total,
        required double progress,
        required bool signedIn,
      }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withOpacity(0.20),
            scheme.tertiary.withOpacity(0.12),
            scheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Haladás',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            signedIn ? '$unlockedCount / $total feloldva' : 'Jelentkezz be a feloldott eredményekhez.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: signedIn ? progress : 0.0,
              minHeight: 10,
              backgroundColor: scheme.surfaceVariant.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statPill(context, icon: Icons.emoji_events_outlined, label: 'Jutalmak', value: '$total'),
              const SizedBox(width: 10),
              _statPill(context, icon: Icons.check_circle_outline, label: 'Feloldva', value: signedIn ? '$unlockedCount' : '—'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statPill(BuildContext context, {required IconData icon, required String label, required String value}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _actionsCard(BuildContext context, {required bool signedIn, required String? uid}) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(0.45),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: signedIn && uid != null ? () => _showAddRecordModal(uid: uid) : _showSignInRequired,
                  icon: const Icon(Icons.add),
                  label: const Text('Új rekord'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: signedIn && uid != null
                      ? () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => SubmittedRecordsScreen(userId: uid)),
                  )
                      : _showSignInRequired,
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('Beküldések'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    side: BorderSide(color: scheme.outlineVariant.withOpacity(0.5)),
                  ),
                ),
              ),
            ],
          ),
          if (!signedIn) ...[
            const SizedBox(height: 10),
            Text(
              'Bejelentkezés nélkül a jutalmak megtekinthetők, de rekord beküldéséhez és a beküldések listájához be kell jelentkezned.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.25),
            ),
          ],
        ],
      ),
    );
  }

  Widget _achievementTile(BuildContext context, Achievement a, {required bool signedIn}) {
    final scheme = Theme.of(context).colorScheme;

    final effectiveUnlocked = signedIn ? a.unlocked : false;
    final lockedBecauseSignedOut = !signedIn;

    return Container(
      decoration: BoxDecoration(
        color: effectiveUnlocked ? scheme.secondaryContainer.withOpacity(0.72) : scheme.surfaceVariant.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(effectiveUnlocked ? 0.10 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          if (lockedBecauseSignedOut) {
            _showSignInRequired();
            return;
          }
          _showAchievementDetails(context, a);
        },
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Opacity(
                opacity: lockedBecauseSignedOut ? 0.78 : 1.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: effectiveUnlocked ? Colors.amber.withOpacity(0.16) : scheme.primary.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            effectiveUnlocked ? Icons.emoji_events : Icons.lock_outline,
                            color: effectiveUnlocked ? Colors.amber[800] : scheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                        const Spacer(),
                        if (effectiveUnlocked)
                          const Icon(Icons.check_circle, color: Colors.green, size: 20)
                        else
                          Icon(Icons.circle_outlined, color: scheme.onSurfaceVariant.withOpacity(0.35), size: 18),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      a.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      a.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.2),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.surface.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: scheme.outlineVariant.withOpacity(0.22)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline, size: 16, color: scheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            lockedBecauseSignedOut ? 'Jelentkezz be' : (effectiveUnlocked ? 'Feloldva' : 'Zárolva'),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (lockedBecauseSignedOut)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.06),
                          Colors.black.withOpacity(0.12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAchievementDetails(BuildContext context, Achievement a) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a.title),
        content: Text(a.description),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Bezár')),
        ],
      ),
    );
  }
}
