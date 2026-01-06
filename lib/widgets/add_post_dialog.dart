// lib/widgets/add_post_dialog.dart

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/post.dart';
import '../services/post_service.dart';

class AddPostDialog extends StatefulWidget {
  final VoidCallback onPostAdded;

  const AddPostDialog({super.key, required this.onPostAdded});

  /// Preferred: call this instead of showDialog(AlertDialog)
  static Future<void> show(BuildContext context, {required VoidCallback onPostAdded}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AddPostDialog(onPostAdded: onPostAdded),
    );
  }

  @override
  State<AddPostDialog> createState() => _AddPostDialogState();
}

class _AddPostDialogState extends State<AddPostDialog> {
  final _formKey = GlobalKey<FormState>();
  final _textController = TextEditingController();

  final _picker = ImagePicker();
  File? _imageFile;

  String _displayName = 'Felhasználó';
  String _role = 'user';
  bool _loadingUser = true;

  bool _uploading = false;
  bool _pinned = false;
  bool _sendPush = false;

  bool _acceptedRules = false;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _displayName = 'Felhasználó';
        _role = 'user';
        _loadingUser = false;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? <String, dynamic>{};

      setState(() {
        _displayName = (data['name'] as String?)?.trim().isNotEmpty == true
            ? (data['name'] as String).trim()
            : (user.email ?? 'Felhasználó');
        _role = (data['role'] as String?) ?? 'user';
        _acceptedRules = data['acceptedPostRules'] == true;
        _loadingUser = false;
      });
    } catch (_) {
      setState(() {
        _displayName = user.email ?? 'Felhasználó';
        _role = 'user';
        _loadingUser = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2000,
    );
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<String?> _uploadImage(File imageFile) async {
    final fileName = 'post_${const Uuid().v4()}.jpg';
    final ref = FirebaseStorage.instance.ref().child('post_images').child(fileName);
    await ref.putFile(imageFile);
    return await ref.getDownloadURL();
  }

  Future<void> _sendPushToAll(String title, String body) async {
    final response = await http.post(
      Uri.parse('https://catchsense-backend.onrender.com/send-push-all'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'title': title, 'body': body}),
    );

    if (response.statusCode != 200 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Push küldése sikertelen: ${response.body}')),
      );
    }
  }

  Future<bool> _showRules() async {
    final scheme = Theme.of(context).colorScheme;

    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Posztolási szabályzat',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                'A közösség minősége érdekében kérjük, tartsd be az alábbi irányelveket.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 14),
              _RulesBlock(
                title: 'Tiltott',
                bullets: const [
                  'Trágár vagy sértő nyelvezet',
                  'Erőszakos vagy szexuális tartalom',
                  'Zaklatás, személyeskedés',
                  'Spam és megtévesztő információk',
                ],
              ),
              const SizedBox(height: 10),
              _RulesBlock(
                title: 'Ajánlott',
                bullets: const [
                  'Saját, hiteles tartalom (fogás, tapasztalat, tipp)',
                  'Tiszteletteljes kommunikáció',
                  'Jó minőségű, releváns képek',
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Nem fogadom el'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Elfogadom'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    return accepted ?? false;
  }

  Future<void> _submit() async {
    if (_uploading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _uploading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _uploading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? <String, dynamic>{};
      final username = (data['name'] as String?)?.trim().isNotEmpty == true
          ? (data['name'] as String).trim()
          : (user.email ?? 'Felhasználó');

      // Ban handling
      final isBanned = data['banned'] == true;
      final bannedUntil = data['bannedUntil'] as Timestamp?;
      final now = DateTime.now();
      final isTemporarilyBanned = bannedUntil != null && bannedUntil.toDate().isAfter(now);

      if (isBanned || isTemporarilyBanned) {
        String banMsg = 'A fiók jelenleg tiltva van posztolástól. Kérdés esetén: info@pecazom.hu';
        if (isTemporarilyBanned) {
          final until = bannedUntil!.toDate().toLocal().toString().split('.').first;
          banMsg += '\nTiltás lejárata: $until';
        } else {
          banMsg += '\nTiltás típusa: végleges';
        }

        if (mounted) {
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Hozzáférés korlátozott'),
              content: Text(banMsg),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Rendben')),
              ],
            ),
          );
        }

        setState(() => _uploading = false);
        return;
      }

      // Rules gating
      if (!_acceptedRules) {
        final accepted = await _showRules();
        if (!accepted) {
          setState(() => _uploading = false);
          return;
        }

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {'acceptedPostRules': true},
          SetOptions(merge: true),
        );

        setState(() => _acceptedRules = true);
      }

      String imageUrl = '';
      if (_imageFile != null) {
        imageUrl = await _uploadImage(_imageFile!) ?? '';
      }

      final post = Post(
        id: const Uuid().v4(),
        userId: user.uid,
        username: username,
        imageUrl: imageUrl,
        text: _textController.text.trim(),
        timestamp: DateTime.now(),
        pinned: _role == 'admin' ? _pinned : false,
      );

      await PostService().addPost(post);

      if (_role == 'admin' && _sendPush) {
        await _sendPushToAll('Új admin poszt: $username', post.text);
      }

      widget.onPostAdded();

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba történt: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Új bejegyzés',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (_loadingUser)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                Text(
                  _loadingUser ? 'Felhasználói adatok betöltése…' : _displayName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _textController,
                        maxLines: 5,
                        minLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Szöveg',
                          hintText: 'Fogás, tipp, kérdés vagy rövid beszámoló…',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) return 'Írj be legalább egy rövid szöveget.';
                          if (value.length < 3) return 'A szöveg túl rövid.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.image_outlined),
                              label: Text(_imageFile == null ? 'Kép hozzáadása' : 'Kép cseréje'),
                            ),
                          ),
                          if (_imageFile != null) ...[
                            const SizedBox(width: 10),
                            IconButton(
                              tooltip: 'Kép eltávolítása',
                              onPressed: () => setState(() => _imageFile = null),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ],
                      ),

                      if (_imageFile != null) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.file(_imageFile!, fit: BoxFit.cover),
                          ),
                        ),
                      ],

                      if (_role == 'admin') ...[
                        const SizedBox(height: 12),
                        SwitchListTile.adaptive(
                          value: _pinned,
                          onChanged: (v) => setState(() => _pinned = v),
                          title: const Text('Kitűzés'),
                          subtitle: const Text('A poszt a feed elején jelenik meg.'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile.adaptive(
                          value: _sendPush,
                          onChanged: (v) => setState(() => _sendPush = v),
                          title: const Text('Push értesítés'),
                          subtitle: const Text('Értesítés küldése minden felhasználónak.'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _uploading ? null : () => Navigator.pop(context),
                        child: const Text('Mégsem'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _uploading ? null : _submit,
                        child: const Text('Közzététel'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_uploading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.25),
                child: const Center(
                  child: SizedBox(width: 36, height: 36, child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RulesBlock extends StatelessWidget {
  final String title;
  final List<String> bullets;

  const _RulesBlock({required this.title, required this.bullets});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...bullets.map(
                (b) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(b, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.25))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
