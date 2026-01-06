// lib/widgets/post_list.dart

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/post.dart';
import '../services/like_service.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';

class PostList extends StatefulWidget {
  const PostList({super.key});

  @override
  State<PostList> createState() => _PostListState();
}

class _PostListState extends State<PostList> with AutomaticKeepAliveClientMixin {
  final _userCache = <String, _UserMeta>{}; // userId -> meta cache

  @override
  bool get wantKeepAlive => true;

  Future<_UserMeta> _getUserMeta(String userId, String fallbackName) async {
    final cached = _userCache[userId];
    if (cached != null) return cached;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final data = doc.data() ?? <String, dynamic>{};
      final name = (data['name'] as String?)?.trim();
      final role = (data['role'] as String?)?.trim() ?? 'user';

      final meta = _UserMeta(
        displayName: (name == null || name.isEmpty) ? fallbackName : name,
        role: role,
      );
      _userCache[userId] = meta;
      return meta;
    } catch (_) {
      final meta = _UserMeta(displayName: fallbackName, role: 'user');
      _userCache[userId] = meta;
      return meta;
    }
  }

  Future<void> _deletePost(BuildContext context, Post post) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Törlés megerősítése'),
        content: const Text('A poszt végleg törlésre kerül.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégsem')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Törlés')),
        ],
      ),
    );

    if (confirm == true) {
      await PostService().deletePost(post.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Poszt törölve.')),
        );
      }
    }
  }

  Future<void> _showReportSheet(BuildContext context, Post post) async {
    final scheme = Theme.of(context).colorScheme;
    String? reason;
    String customReason = '';
    String urgency = 'normál';

    final okList = ['Sértő tartalom', 'Spam', 'Hamis információ', 'Egyéb'];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            final disableUrgent =
                (reason == null) || (reason == 'Egyéb' && customReason.trim().isEmpty);

            Future<void> submit() async {
              if (reason == null) return;
              final fullReason = (reason == 'Egyéb') ? customReason.trim() : reason!.trim();
              if (fullReason.isEmpty) return;

              await FirebaseFirestore.instance.collection('reports').add({
                'postId': post.id,
                'postText': post.text,
                'reason': fullReason,
                'urgency': urgency,
                'timestamp': DateTime.now(),
              });

              if (urgency == 'sürgős') {
                await http.post(
                  Uri.parse('https://catchsense-backend.onrender.com/send-admin-push'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'title': 'Sürgős jelentés érkezett',
                    'body': 'Jelentett poszt: ${post.text}',
                  }),
                );
              }

              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Jelentés elküldve.')),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 6,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Poszt jelentése',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Válaszd ki az okot és a típust. Sürgős jelentés esetén az admin azonnali értesítést kap.',
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Jelentés oka',
                      border: OutlineInputBorder(),
                    ),
                    items: okList.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (value) => setState(() => reason = value),
                  ),
                  const SizedBox(height: 12),
                  if (reason == 'Egyéb') ...[
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Részletek',
                        hintText: 'Írd le röviden a problémát',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => setState(() => customReason = val),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<String>(
                    value: urgency,
                    decoration: const InputDecoration(
                      labelText: 'Típus',
                      border: OutlineInputBorder(),
                    ),
                    items: ['normál', 'sürgős'].map((e) {
                      final enabled = (e == 'normál') || !disableUrgent;
                      return DropdownMenuItem(
                        value: e,
                        enabled: enabled,
                        child: Text(e),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => urgency = value ?? 'normál'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Mégsem'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: (reason == null ||
                              (reason == 'Egyéb' && customReason.trim().isEmpty))
                              ? null
                              : submit,
                          child: const Text('Jelentés küldése'),
                        ),
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
  }

  String _formatTs(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final yyyy = dt.year.toString().padLeft(4, '0');
    final mon = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    return '$hh:$mm • $yyyy.$mon.$dd';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final currentUser = FirebaseAuth.instance.currentUser;
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<List<Post>>(
      stream: PostService().getPosts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return _Notice(
            icon: Icons.cloud_off_outlined,
            title: 'A posztok nem érhetők el',
            message: 'Hiba történt az adatok betöltése közben. Próbáld újra később.',
          );
        }

        final posts = snapshot.data ?? [];
        if (posts.isEmpty) {
          return _Notice(
            icon: Icons.forum_outlined,
            title: 'Még nincs bejegyzés',
            message: 'Légy te az első: ossz meg fogást, tippet vagy kérdést.',
          );
        }

        return FutureBuilder<bool>(
          future: UserService.isCurrentUserAdmin(),
          builder: (context, adminSnap) {
            final isAdmin = adminSnap.data ?? false;

            // ✅ FIX: SliverToBoxAdapter-ben fut (MainHomeContent), ezért a belső lista NEM scrollolhat.
            // Ezzel megszűnik az "unbounded height / RenderViewport hasSize" hiba görgetéskor.
            return ListView.separated(
              shrinkWrap: true,
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: posts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final post = posts[index];
                final isOwner = currentUser != null && currentUser.uid == post.userId;

                return FutureBuilder<_UserMeta>(
                  future: _getUserMeta(post.userId, post.username),
                  builder: (context, metaSnap) {
                    final meta = metaSnap.data ?? _UserMeta(displayName: post.username, role: 'user');

                    return Container(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: scheme.outlineVariant.withOpacity(0.28)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              children: [
                                _Avatar(name: meta.displayName),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              meta.displayName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (meta.role == 'admin')
                                            _Chip(
                                              label: 'ADMIN',
                                              bg: Colors.red.withOpacity(0.14),
                                              fg: Colors.redAccent,
                                            ),
                                          if (post.pinned) const SizedBox(width: 6),
                                          if (post.pinned)
                                            _Chip(
                                              label: 'KITŰZVE',
                                              bg: Colors.orange.withOpacity(0.14),
                                              fg: Colors.orange,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatTs(post.timestamp),
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isOwner || isAdmin)
                                  PopupMenuButton<String>(
                                    tooltip: 'Műveletek',
                                    onSelected: (value) async {
                                      if (value == 'delete') {
                                        await _deletePost(context, post);
                                      } else if (value == 'report') {
                                        await _showReportSheet(context, post);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'delete', child: Text('Törlés')),
                                      PopupMenuItem(value: 'report', child: Text('Jelentés')),
                                    ],
                                  )
                                else
                                  IconButton(
                                    tooltip: 'Jelentés',
                                    onPressed: () => _showReportSheet(context, post),
                                    icon: const Icon(Icons.flag_outlined),
                                  ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            if (post.text.trim().isNotEmpty)
                              Text(
                                post.text.trim(),
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.35),
                              ),

                            if (post.imageUrl.trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Image.network(
                                    post.imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: scheme.surfaceContainerHighest,
                                      child: Center(
                                        child: Text(
                                          'A kép nem tölthető be',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(color: scheme.onSurfaceVariant),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 12),
                            Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.35)),
                            const SizedBox(height: 8),

                            // Actions
                            Row(
                              children: [
                                if (currentUser != null)
                                  StreamBuilder<bool>(
                                    stream: LikeService().isLiked(post.id, currentUser.uid),
                                    builder: (context, likeSnap) {
                                      final liked = likeSnap.data ?? false;
                                      return IconButton(
                                        tooltip: liked ? 'Kedvelés visszavonása' : 'Kedvelés',
                                        icon: Icon(
                                          liked ? Icons.favorite : Icons.favorite_border,
                                          color: liked ? Colors.red : scheme.onSurfaceVariant,
                                        ),
                                        onPressed: () =>
                                            LikeService().toggleLike(post.id, currentUser.uid),
                                      );
                                    },
                                  )
                                else
                                  IconButton(
                                    tooltip: 'Jelentkezz be a kedveléshez',
                                    onPressed: null,
                                    icon: Icon(Icons.favorite_border, color: scheme.onSurfaceVariant),
                                  ),
                                StreamBuilder<int>(
                                  stream: LikeService().getLikeCount(post.id),
                                  builder: (context, cntSnap) {
                                    final c = cntSnap.data ?? 0;
                                    return Text(
                                      '$c kedvelés',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    );
                                  },
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: () => _showReportSheet(context, post),
                                  icon: const Icon(Icons.flag_outlined, size: 18),
                                  label: const Text('Jelentés'),
                                ),
                              ],
                            ),
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

class _UserMeta {
  final String displayName;
  final String role;

  const _UserMeta({
    required this.displayName,
    required this.role,
  });
}

class _Chip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _Chip({
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = name.trim().isEmpty
        ? 'U'
        : name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((p) => p.characters.first.toUpperCase())
        .join();

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: scheme.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
      ),
      child: Center(
        child: Text(
          initials,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _Notice({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
