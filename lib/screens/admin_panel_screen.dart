import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text("Admin panel"),
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Áttekintés'),
            Tab(text: 'Jóváhagyás'),
            Tab(text: 'Jelentések'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: const [
            AdminOverviewTab(),
            RecordReviewTab(),
            ReportReviewTab(),
          ],
        ),
      ),
    );
  }
}

/* ---------------- UI helpers ---------------- */

class _Ui {
  static Widget glassCard(
      BuildContext context, {
        required Widget child,
        EdgeInsets padding = const EdgeInsets.all(14),
      }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(0.45),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  static Widget sectionHeader(
      BuildContext context, {
        required String title,
        String? subtitle,
        Widget? trailing,
      }) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: t.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  static Widget pill(
      BuildContext context, {
        required IconData icon,
        required String text,
        required Color color,
      }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.70),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/* ---------------- Admin overview ---------------- */

class AdminOverviewTab extends StatefulWidget {
  const AdminOverviewTab({super.key});

  @override
  State<AdminOverviewTab> createState() => _AdminOverviewTabState();
}

class _AdminOverviewTabState extends State<AdminOverviewTab> {
  bool loading = true;

  int userCount = 0;
  int postCount = 0;
  int reportOpenCount = 0;
  int recordPendingCount = 0;

  int totalLikes = 0;

  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => loading = true);
    try {
      final usersSnap =
      await FirebaseFirestore.instance.collection('users').get();
      final postsSnap =
      await FirebaseFirestore.instance.collection('posts').get();

      QuerySnapshot? reportsSnap;
      QuerySnapshot? pendingRecordsSnap;

      try {
        reportsSnap = await FirebaseFirestore.instance
            .collection('reports')
            .where('status', isNotEqualTo: 'closed')
            .get();
      } catch (_) {
        reportsSnap = null;
      }

      try {
        pendingRecordsSnap = await FirebaseFirestore.instance
            .collection('record_reviews')
            .where('status', isEqualTo: 'pending')
            .get();
      } catch (_) {
        pendingRecordsSnap = null;
      }

      int likes = 0;
      for (final doc in postsSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final v = data['likes'];
        if (v is num) likes += v.toInt();
      }

      setState(() {
        userCount = usersSnap.size;
        postCount = postsSnap.size;
        totalLikes = likes;
        reportOpenCount = reportsSnap?.size ?? 0;
        recordPendingCount = pendingRecordsSnap?.size ?? 0;
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Hiba az adatok betöltésekor: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    if (loading) return const Center(child: CircularProgressIndicator());

    Widget kpi({
      required IconData icon,
      required String title,
      required String value,
      required Color tint,
    }) {
      return _Ui.glassCard(
        context,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tint.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Ui.sectionHeader(
            context,
            title: 'Áttekintés',
            subtitle: 'Kulcs metrikák és gyors admin műveletek.',
            trailing: IconButton(
              tooltip: 'Frissítés',
              icon: const Icon(Icons.refresh),
              onPressed: _loadStats,
            ),
          ),
          const SizedBox(height: 8),

          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.2,
            children: [
              kpi(
                icon: Icons.people_outline,
                title: 'Felhasználók',
                value: userCount.toString(),
                tint: scheme.primary,
              ),
              kpi(
                icon: Icons.article_outlined,
                title: 'Posztok',
                value: postCount.toString(),
                tint: Colors.green,
              ),
              kpi(
                icon: Icons.favorite_outline,
                title: 'Like-ok',
                value: totalLikes.toString(),
                tint: Colors.red,
              ),
              kpi(
                icon: Icons.report_outlined,
                title: 'Nyitott jelentések',
                value: reportOpenCount.toString(),
                tint: Colors.orange,
              ),
            ],
          ),

          const SizedBox(height: 14),
          _Ui.glassCard(
            context,
            child: Row(
              children: [
                Icon(Icons.pending_actions_outlined,
                    color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Függőben lévő rekord jóváhagyások: $recordPendingCount',
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),
          _Ui.sectionHeader(context, title: 'Diagram'),

          // ✅ FIX: RenderFlex overflow megszüntetése (bottomTitles + reservedSize + SideTitleWidget)
          // ---------------- Diagram ----------------

          _Ui.glassCard(
            context,
            child: SizedBox(
              height: 285,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        getTitlesWidget: (value, meta) {
                          final label = switch (value.toInt()) {
                            0 => 'User',
                            1 => 'Poszt',
                            2 => 'Like',
                            3 => 'Jel.',
                            _ => '',
                          };

                          if (label.isEmpty) return const SizedBox.shrink();

                          return SideTitleWidget(
                            meta: meta, // ✅ fl_chart 1.1.1-ben kötelező
                            space: 8,
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        interval: 20,
                        getTitlesWidget: (v, meta) {
                          return SideTitleWidget(
                            meta: meta, // ✅ fl_chart 1.1.1-ben kötelező
                            space: 8,
                            child: Text(
                              v.toInt().toString(),
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [BarChartRodData(toY: userCount.toDouble())],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [BarChartRodData(toY: postCount.toDouble())],
                    ),
                    BarChartGroupData(
                      x: 2,
                      barRods: [BarChartRodData(toY: totalLikes.toDouble())],
                    ),
                    BarChartGroupData(
                      x: 3,
                      barRods: [BarChartRodData(toY: reportOpenCount.toDouble())],
                    ),
                  ],
                ),
              ),
            ),
          ),


          const SizedBox(height: 22),
          _Ui.sectionHeader(
            context,
            title: 'Felhasználók',
            subtitle: 'Keresés név alapján és role módosítás.',
          ),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Keresés név alapján...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) =>
                setState(() => searchQuery = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .orderBy('name')
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: _Ui.glassCard(
                    context,
                    child: Text(
                      'Hiba a felhasználók betöltésekor:\n${snap.error}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                );
              }

              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(18.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final docs = snap.data!.docs.where((d) {
                final name = (d.data()['name'] ?? '').toString().toLowerCase();
                return searchQuery.isEmpty || name.contains(searchQuery);
              }).toList();

              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(18.0),
                  child: Center(child: Text('Nincs találat.')),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final d = docs[i];
                  final data = d.data();
                  final userId = d.id;

                  final name = (data['name'] ?? 'Névtelen').toString();
                  final email = (data['email'] ?? '').toString();
                  final role = (data['role'] ?? 'user').toString();

                  return _Ui.glassCard(
                    context,
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: scheme.primary.withOpacity(0.15),
                          child: Icon(Icons.person_outline, color: scheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              if (email.isNotEmpty)
                                Text(
                                  email,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        DropdownButton<String>(
                          value: role,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(value: 'user', child: Text('user')),
                            DropdownMenuItem(value: 'admin', child: Text('admin')),
                          ],
                          onChanged: (newRole) async {
                            if (newRole == null) return;
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(userId)
                                .update({'role': newRole});
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/* ---------------- Record review ---------------- */

class RecordReviewTab extends StatelessWidget {
  const RecordReviewTab({super.key});

  Future<void> _sendPushToUser(String userId, String title, String body) async {
    try {
      final response = await http.post(
        Uri.parse('https://catchsense-backend.onrender.com/send-push'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'body': body,
          'user_ids': [userId],
        }),
      );
      if (response.statusCode != 200) {
        debugPrint('Push küldése sikertelen: ${response.body}');
      }
    } catch (e) {
      debugPrint('Push hibája: $e');
    }
  }

  Future<void> approveRecord(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final String userId = (data['userId'] ?? '').toString();
    final double weight = (data['fishWeight'] as num?)?.toDouble() ?? 0.0;

    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final userSnap = await userRef.get();
    final achievements =
    Map<String, dynamic>.from(userSnap.data()?['achievements'] ?? {});

    final thresholds = {
      'catch5kg': 5.0,
      'catch10kg': 10.0,
      'catch13kg': 13.0,
      'catch15kg': 15.0,
      'catch17kg': 17.0,
      'catch20kg': 20.0,
      'catch23kg': 23.0,
      'catch25kg': 25.0,
      'catch27kg': 27.0,
      'catch28kg': 28.0,
      'catch30kg': 30.0,
      'catch33kg': 33.0,
      'catch35kg': 35.0,
      'catch37kg': 37.0,
      'catch40kg': 40.0,
    };

    for (final entry in thresholds.entries) {
      if (weight >= entry.value) {
        achievements[entry.key] = true;
      }
    }

    achievements['firstCatch'] = true;

    await userRef.set({'achievements': achievements}, SetOptions(merge: true));
    await doc.reference.update({'status': 'approved'});

    await _sendPushToUser(
      userId,
      "A rekordod jóvá lett hagyva",
      "Gratulálunk, a(z) ${data['fishSpecies']} (${data['fishWeight']} kg) fogásod jóváhagyásra került!",
    );
  }

  Future<void> rejectRecord(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final String userId = (data['userId'] ?? '').toString();

    await doc.reference.update({'status': 'rejected'});

    await _sendPushToUser(
      userId,
      "A rekordod elutasításra került",
      "Sajnáljuk, de a(z) ${data['fishSpecies']} (${data['fishWeight']} kg) fogásod nem került jóváhagyásra.",
    );
  }

  void _previewImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('A kép nem tölthető be.')),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Timestamp? _tsFrom(dynamic v) {
    if (v is Timestamp) return v;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('record_reviews')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: _Ui.glassCard(
              context,
              child: Text(
                'Hiba a rekordok betöltésekor:\n${snapshot.error}\n\n'
                    'Tipp: ellenőrizd, hogy a record_reviews dokumentumokban létezik-e a "status" mező, és hogy van-e jogosultság olvasásra.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs.toList();

        docs.sort((a, b) {
          final ta =
              _tsFrom(a.data()['submittedAt'])?.millisecondsSinceEpoch ?? 0;
          final tb =
              _tsFrom(b.data()['submittedAt'])?.millisecondsSinceEpoch ?? 0;
          return tb.compareTo(ta);
        });

        if (docs.isEmpty) {
          return const Center(child: Text('Nincs függőben lévő rekordfogás.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();

            final imageUrl = (data['imageUrl'] ?? '').toString();
            final fish = (data['fishSpecies'] ?? '-').toString();
            final weight = (data['fishWeight'] ?? '-').toString();

            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc((data['userId'] ?? '').toString())
                  .get(),
              builder: (context, userSnap) {
                final userData = userSnap.data?.data();
                final name = (userData?['name'] ?? 'Ismeretlen').toString();
                final email = (userData?['email'] ?? '').toString();

                return _Ui.glassCard(
                  context,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$fish • $weight kg',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          _Ui.pill(
                            context,
                            icon: Icons.hourglass_top,
                            text: 'Függőben',
                            color: scheme.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$name${email.isNotEmpty ? ' • $email' : ''}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      if (imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            onTap: () => _previewImage(context, imageUrl),
                            child: Image.network(
                              imageUrl,
                              height: 210,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 210,
                                alignment: Alignment.center,
                                child: const Text('Kép nem tölthető be.'),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => rejectRecord(doc),
                            icon: const Icon(Icons.close),
                            label: const Text('Elutasít'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: () => approveRecord(doc),
                            icon: const Icon(Icons.check),
                            label: const Text('Jóváhagy'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/* ---------------- Report review (optimized) ---------------- */

class ReportReviewTab extends StatefulWidget {
  const ReportReviewTab({super.key});

  @override
  State<ReportReviewTab> createState() => _ReportReviewTabState();
}

class _ReportReviewTabState extends State<ReportReviewTab> {
  final Map<String, Map<String, dynamic>?> _userCache = {};

  Future<Map<String, dynamic>?> _getUser(String? userId) async {
    if (userId == null || userId.isEmpty) return null;
    if (_userCache.containsKey(userId)) return _userCache[userId];

    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(userId).get();
    final data = userDoc.exists ? userDoc.data() : null;
    _userCache[userId] = data;
    return data;
  }

  Future<void> closeReport(String reportId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final userData = userDoc.data();

    await FirebaseFirestore.instance.collection('reports').doc(reportId).update({
      'status': 'closed',
      'closedBy': {
        'uid': user.uid,
        'name': userData?['name'] ?? 'Ismeretlen',
        'email': userData?['email'] ?? '',
      },
      'closedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendPushToUser(String userId, String title, String body) async {
    try {
      await http.post(
        Uri.parse('https://catchsense-backend.onrender.com/send-push'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_ids': [userId],
          'title': title,
          'body': body,
        }),
      );
    } catch (e) {
      debugPrint('Push error: $e');
    }
  }

  Future<void> banUser(String userId, {bool permanent = false}) async {
    final data = permanent
        ? {'banned': true}
        : {
      'bannedUntil':
      Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
    };

    await FirebaseFirestore.instance.collection('users').doc(userId).update(data);

    await sendPushToUser(
      userId,
      permanent ? "Kitiltás" : "Eltiltás",
      permanent
          ? "A fiókod véglegesen kitiltásra került szabálysértés miatt."
          : "A fiókod ideiglenesen el lett tiltva 7 napra.",
    );
  }

  Future<void> unbanUser(String userId) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'banned': FieldValue.delete(),
      'bannedUntil': FieldValue.delete(),
    });

    await sendPushToUser(
      userId,
      "Tiltás visszavonva",
      "A fiókodra vonatkozó tiltást visszavontuk. Ismét használhatod az alkalmazást.",
    );
  }

  Color _statusColor(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'closed':
        return Colors.green;
      case 'open':
      default:
        return scheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('reports')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: _Ui.glassCard(
              context,
              child: Text(
                'Hiba a jelentések betöltésekor:\n${snapshot.error}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final reports = snapshot.data!.docs;
        if (reports.isEmpty) {
          return const Center(child: Text('Nincs jelentett poszt.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: reports.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = reports[index];
            final data = doc.data();
            final reportId = doc.id;

            final postId = (data['postId'] ?? '').toString();
            final status = (data['status'] ?? 'open').toString();
            final reason =
            (data['reason'] ?? data['urgency_reason'] ?? 'N/A').toString();
            final extra = (data['extra'] ?? '').toString();
            final type = (data['type'] ?? data['urgency'] ?? 'N/A').toString();

            final reporterId =
            (data['reporterId'] ?? data['userId'] ?? '').toString();
            final postAuthorId = (data['postAuthorId'] ?? '').toString();

            final ts = data['timestamp'];
            final timeStr = (ts is Timestamp)
                ? ts.toDate().toLocal().toString().split('.')[0]
                : '';

            return FutureBuilder<Map<String, dynamic>?>(
              future: _getUser(reporterId),
              builder: (context, reporterSnap) {
                final reporterData = reporterSnap.data;
                final reporterName =
                (reporterData?['name'] ?? 'Ismeretlen').toString();
                final reporterEmail =
                (reporterData?['email'] ?? '').toString();

                return FutureBuilder<Map<String, dynamic>?>(
                  future: _getUser(postAuthorId.isNotEmpty ? postAuthorId : null),
                  builder: (context, authorSnap) {
                    final authorData = authorSnap.data;
                    final authorName =
                    (authorData?['name'] ?? 'Ismeretlen').toString();
                    final authorEmail = (authorData?['email'] ?? '').toString();
                    final isBanned = authorData?['banned'] == true;
                    final bannedUntil = authorData?['bannedUntil'] as Timestamp?;

                    return InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () {
                        if (postId.isEmpty) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PostDetailScreen(postId: postId),
                          ),
                        );
                      },
                      child: _Ui.glassCard(
                        context,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Jelentés • Poszt: ${postId.isEmpty ? '-' : postId}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                ),
                                _Ui.pill(
                                  context,
                                  icon: status == 'closed'
                                      ? Icons.check_circle
                                      : Icons.report_outlined,
                                  text: status == 'closed' ? 'Lezárva' : 'Nyitott',
                                  color: _statusColor(context, status),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text('Ok: $reason',
                                style: Theme.of(context).textTheme.bodyMedium),
                            if (extra.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Egyéb: $extra',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Text(
                              'Jelentette: $reporterName${reporterEmail.isNotEmpty ? ' • $reporterEmail' : ''}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            if (postAuthorId.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Posztoló: $authorName${authorEmail.isNotEmpty ? ' • $authorEmail' : ''}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.label_outline,
                                    size: 16, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text(
                                  'Típus: $type',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                                const Spacer(),
                                if (timeStr.isNotEmpty)
                                  Text(
                                    timeStr,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: scheme.onSurfaceVariant),
                                  ),
                              ],
                            ),
                            if (isBanned || bannedUntil != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                bannedUntil != null
                                    ? "Eltiltva eddig: ${bannedUntil.toDate().toLocal().toString().split('.')[0]}"
                                    : "Véglegesen kitiltva",
                                style: TextStyle(
                                  color: bannedUntil != null
                                      ? Colors.orange
                                      : Colors.red,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            if (status == 'closed') ...[
                              if (data['closedBy'] != null) ...[
                                Text(
                                  "Admin: ${(data['closedBy']['name'] ?? 'Ismeretlen').toString()}",
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ] else ...[
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  FilledButton.icon(
                                    onPressed: () => closeReport(reportId),
                                    icon: const Icon(Icons.check),
                                    label: const Text("Lezárás"),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: postAuthorId.isEmpty
                                        ? null
                                        : () => banUser(postAuthorId,
                                        permanent: false),
                                    icon: const Icon(Icons.timer_off),
                                    label: const Text("7 nap tiltás"),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: postAuthorId.isEmpty
                                        ? null
                                        : () => banUser(postAuthorId,
                                        permanent: true),
                                    icon: const Icon(Icons.block),
                                    label: const Text("Végleges ban"),
                                  ),
                                  if (isBanned || bannedUntil != null)
                                    OutlinedButton.icon(
                                      onPressed: postAuthorId.isEmpty
                                          ? null
                                          : () => unbanUser(postAuthorId),
                                      icon: const Icon(Icons.undo),
                                      label:
                                      const Text("Tiltás visszavonása"),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/* ---------------- Post detail ---------------- */

class PostDetailScreen extends StatelessWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text("Poszt megtekintése"),
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('posts').doc(postId).get(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Hiba: ${snapshot.error}'),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data();
          if (data == null) {
            return const Center(child: Text("A poszt nem található."));
          }

          final text = (data['text'] ?? '').toString();
          final imageUrl = (data['imageUrl'] ?? '').toString();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _Ui.glassCard(
                context,
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const SizedBox(height: 12),
              if (imageUrl.isNotEmpty)
                _Ui.glassCard(
                  context,
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.network(
                      imageUrl,
                      height: 260,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        height: 260,
                        child: Center(child: Text('A kép nem tölthető be.')),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
