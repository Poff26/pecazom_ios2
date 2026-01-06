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
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      setState(() {
        userRole = doc.data()?['role'] ?? 'user';
      });
    }
  }

  void _signOut() async {
    await FirebaseAuth.instance.signOut();
    // Navigáció vissza főképernyőre vagy snackbar
  }

  void _goToAdminPanel() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
    );
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
          value: 'logout',
          child: Text('Kijelentkezés'),
        ),
      ],
    );
  }
}
