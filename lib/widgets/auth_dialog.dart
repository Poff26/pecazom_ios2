import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthDialog extends StatefulWidget {
  final VoidCallback onSuccess;

  /// Ha true, akkor a dialog alapból Regisztráció módban indul.
  final bool startWithRegister;

  const AuthDialog({
    super.key,
    required this.onSuccess,
    this.startWithRegister = true,
  });

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLogin = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _isLogin = !widget.startWithRegister; // default: register first
    _maybeShowRegisterHintOnce();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // ------------------------------ UX helpers ------------------------------

  void _setBusy(bool v) {
    if (!mounted) return;
    setState(() => _busy = v);
  }

  void _setError(String? msg) {
    if (!mounted) return;
    setState(() => _error = msg);
  }

  void _clearError() => _setError(null);

  String _friendlyAuthError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'Az email cím formátuma nem megfelelő.';
        case 'user-disabled':
          return 'Ez a fiók le van tiltva.';
        case 'user-not-found':
          return 'Nincs ilyen felhasználó ezzel az email címmel.';
        case 'wrong-password':
          return 'Hibás jelszó.';
        case 'invalid-credential':
          return 'Hibás belépési adatok.';
        case 'email-already-in-use':
          return 'Ezzel az email címmel már létezik fiók.';
        case 'weak-password':
          return 'A jelszó túl gyenge. Használj legalább 6 karaktert.';
        case 'network-request-failed':
          return 'Hálózati hiba. Ellenőrizd az internetkapcsolatot.';
        case 'too-many-requests':
          return 'Túl sok próbálkozás. Kérlek várj egy kicsit, majd próbáld újra.';
        case 'operation-not-allowed':
          return 'Ez a bejelentkezési mód jelenleg nincs engedélyezve.';
        default:
        // e.message gyakran túl technikai, ezért marad a barátibb szöveg
          return 'Sikertelen művelet. Kérlek próbáld újra.';
      }
    }

    if (e is FirebaseException) {
      return 'Adatbázis hiba. Kérlek próbáld újra.';
    }

    return 'Ismeretlen hiba történt. Kérlek próbáld újra.';
  }

  Future<void> _maybeShowRegisterHintOnce() async {
    // opcionális finomítás: ha szeretnéd, hogy a felhasználó értse miért regisztráció az alap
    try {
      final prefs = await SharedPreferences.getInstance();
      const key = 'auth_dialog_register_default_hint_shown';
      final shown = prefs.getBool(key) ?? false;
      if (shown) return;
      await prefs.setBool(key, true);
    } catch (_) {
      // no-op
    }
  }

  // ------------------------------ Firestore user defaults ------------------------------

  Future<void> _ensureUserFields() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();
    final data = snap.data() ?? {};
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final updates = <String, dynamic>{};
    if (!data.containsKey('role')) updates['role'] = 'user';
    if (!data.containsKey('aiForecastRequestsToday')) updates['aiForecastRequestsToday'] = 0;
    if (!data.containsKey('lastForecastRequestDate')) updates['lastForecastRequestDate'] = today;

    if (updates.isNotEmpty) {
      await ref.set(updates, SetOptions(merge: true));
    }
  }

  Future<void> _saveFcmTokenForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await ref.set({'fcmToken': token}, SetOptions(merge: true));

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        ref.set({'fcmToken': newToken}, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('FCM token mentése sikertelen: $e');
      // ezt nem kell a usernek hibaként kiírni
    }
  }

  // ------------------------------ Password reset ------------------------------

  Future<void> _requestPasswordReset() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _setError('Add meg az email címedet a jelszó-visszaállításhoz.');
      return;
    }

    _clearError();
    _setBusy(true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elküldtük a jelszó-visszaállító levelet az email címedre.')),
      );
    } catch (e) {
      _setError(_friendlyAuthError(e));
    } finally {
      _setBusy(false);
    }
  }

  // ------------------------------ Submit (login/register) ------------------------------

  Future<void> _submit() async {
    if (_busy) return;
    _clearError();

    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    _setBusy(true);

    try {
      if (_isLogin) {
        // BEJELENTKEZÉS
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Email megerősítés ellenőrzése
        if (!(cred.user?.emailVerified ?? false)) {
          await FirebaseAuth.instance.signOut();
          _setError('Kérlek, erősítsd meg az emailedet! Küldtünk egy levelet a regisztrációnál.');
          return;
        }

        await _ensureUserFields();
        await _saveFcmTokenForCurrentUser();

        widget.onSuccess();
        if (!mounted) return;

        Navigator.of(context, rootNavigator: true).pop();
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sikeres bejelentkezés!')),
        );
      } else {
        // REGISZTRÁCIÓ
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        final uid = cred.user?.uid;
        if (uid == null) {
          throw FirebaseAuthException(code: 'unknown', message: 'UID hiányzik.');
        }

        final today = DateTime.now().toIso8601String().substring(0, 10);

        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'email': email,
          'name': name,
          'role': 'user',
          'aiForecastRequestsToday': 0,
          'lastForecastRequestDate': today,
        }, SetOptions(merge: true));

        await _saveFcmTokenForCurrentUser();

        // EMAIL MEGERŐSÍTŐ KÜLDÉSE
        await cred.user?.sendEmailVerification();

        // Kijelentkeztetjük, így nem lép be automatikusan
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sikeres regisztráció! Nézd meg az emailedet és erősítsd meg a fiókot.'),
          ),
        );
      }
    } catch (e) {
      _setError(_friendlyAuthError(e));
    } finally {
      _setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      child: _GlassPanel(
        borderRadius: 26,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row: title + close
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isLogin ? 'Bejelentkezés' : 'Regisztráció',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isLogin
                                    ? 'Lépj be, hogy menthess és szinkronizálhass.'
                                    : 'Hozz létre fiókot és erősítsd meg emailben.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _IconCircleButton(
                          icon: Icons.close_rounded,
                          onTap: _busy
                              ? null
                              : () => Navigator.of(context, rootNavigator: true).pop(),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    if (!_isLogin) ...[
                      _ModernField(
                        controller: _nameController,
                        label: 'Név',
                        hint: 'Pl. Péter',
                        icon: Icons.person_rounded,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Add meg a neved' : null,
                      ),
                      const SizedBox(height: 10),
                    ],

                    _ModernField(
                      controller: _emailController,
                      label: 'Email',
                      hint: 'pelda@email.com',
                      icon: Icons.mail_rounded,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !_busy,
                      validator: (v) => (v == null || !v.contains('@')) ? 'Érvényes email kell' : null,
                    ),
                    const SizedBox(height: 10),

                    _ModernField(
                      controller: _passwordController,
                      label: 'Jelszó',
                      hint: 'Legalább 6 karakter',
                      icon: Icons.lock_rounded,
                      obscureText: true,
                      enabled: !_busy,
                      validator: (v) => (v == null || v.length < 6)
                          ? 'Legalább 6 karakter hosszú jelszó kell'
                          : null,
                    ),

                    // Forgot password (only on login)
                    if (_isLogin) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _requestPasswordReset,
                          child: const Text('Elfelejtett jelszó?'),
                        ),
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(text: _error!),
                    ],

                    const SizedBox(height: 10),

                    if (_busy) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Folyamatban...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.72),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],

                    const SizedBox(height: 10),

                    // Primary button
                    SizedBox(
                      width: double.infinity,
                      child: _GradientButton(
                        label: _isLogin ? 'Belépés' : 'Regisztráció',
                        icon: _isLogin ? Icons.login_rounded : Icons.person_add_alt_1_rounded,
                        onTap: _busy ? null : _submit,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Switch mode
                    Center(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: _busy
                            ? null
                            : () {
                          setState(() {
                            _isLogin = !_isLogin;
                            _error = null;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Text(
                            _isLogin ? 'Regisztráció' : 'Már van fiókom',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1B86B2),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 2),

                    // Footnote (subtle)
                    Text(
                      _isLogin
                          ? 'Belépés után elérhető a mentés és a személyre szabott funkciók.'
                          : 'Regisztráció után emailben megerősítés szükséges a belépéshez.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.62),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ------------------------------ UI parts ------------------------------ */

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final double borderRadius;

  const _GlassPanel({
    required this.child,
    this.borderRadius = 24,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final base = isDark ? const Color(0xFF0F2236) : Colors.white;
    final border = isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.06);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: base.withOpacity(isDark ? 0.62 : 0.86),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                blurRadius: 28,
                offset: const Offset(0, 16),
                color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _IconCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _IconCircleButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bg = isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.06);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.06),
            ),
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

class _ModernField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool enabled;

  const _ModernField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final fieldBg = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: fieldBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.06),
            ),
          ),
          child: TextFormField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            validator: validator,
            enabled: enabled,
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.55),
                fontWeight: FontWeight.w600,
              ),
              prefixIcon: Icon(icon),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E5E86), Color(0xFF1B86B2)],
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.18),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String text;
  const _ErrorBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFB42318).withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFB42318).withOpacity(0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFB42318)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFB42318),
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
