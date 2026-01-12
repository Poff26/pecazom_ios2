import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../screens/admin_panel_screen.dart'; // majd ezt létrehozzuk

class UserMenuButton extends StatefulWidget {
  const UserMenuButton({super.key});

  @override
  State<UserMenuButton> createState() => _UserMenuButtonState();
}

class _UserMenuButtonState extends State<UserMenuButton> {
  String? userRole;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!mounted) return;
      setState(() {
        userRole = (doc.data()?['role'] as String?) ?? 'user';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => userRole = 'user');
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sikeres kijelentkezés')),
    );
  }

  void _goToAdminPanel() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
    );
  }

  // -----------------------------
  // ✅ Account & privacy sheet (contains delete)
  // -----------------------------
  void _openAccountSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text(
                    'Fiók és adatvédelem',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 6),

                // Ide később betehetsz Adatkezelési tájékoztatót / supportot stb.
                // ListTile(
                //   leading: const Icon(Icons.privacy_tip_outlined),
                //   title: const Text('Adatkezelési tájékoztató'),
                //   onTap: () {
                //     Navigator.pop(ctx);
                //     // TODO: open URL / screen
                //   },
                // ),

                const Divider(),

                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text(
                    'Fiók törlése',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: const Text('Végleges művelet, nem visszavonható.'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _confirmAndDeleteAccount();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -----------------------------
  // ✅ Delete flow (confirm + best-effort cleanup)
  // Notes:
  // - Firebase gyakran reauth-ot kér: ezt kezeljük.
  // - Minimum: users/{uid} törlés + auth user törlés.
  // - (Később) posztok/anonymizálás, képek, stb.
  // -----------------------------
  Future<void> _confirmAndDeleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1) confirm dialog
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fiók törlése'),
        content: const Text(
          'A fiók törlése végleges. A művelet nem visszavonható.\n\n'
          'Biztosan törlöd a fiókodat?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Mégse'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Törlés'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    // 2) progress
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            SizedBox(width: 14),
            Expanded(child: Text('Fiók törlése folyamatban...')),
          ],
        ),
      ),
    );

    try {
      final uid = user.uid;

      // A) töröld a Firestore user doc-ot (best effort)
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      // B) töröld az auth usert
      await user.delete();

      if (!mounted) return;
      Navigator.of(context).pop(); // progress
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A fiók törlése sikeres.')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // progress

      // Firebase: recent-login required
      if (e.code == 'requires-recent-login') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A fiók törléséhez újra be kell jelentkezned (biztonsági ok). '
              'Jelentkezz ki-be, majd próbáld újra.',
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hiba a törlés során: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // progress
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hiba a törlés során: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.account_circle),
      onSelected: (value) {
        switch (value) {
          case 'admin':
            _goToAdminPanel();
            break;
          case 'account':
            _openAccountSheet();
            break;
          case 'logout':
            _signOut();
            break;
        }
      },
      itemBuilder: (context) => [
        if (userRole == 'admin')
          const PopupMenuItem(
            value: 'admin',
            child: Text('Admin panel'),
          ),
        const PopupMenuItem(
          value: 'account',
          child: Text('Fiók és adatvédelem'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: Text('Kijelentkezés'),
        ),
      ],
    );
  }
}
