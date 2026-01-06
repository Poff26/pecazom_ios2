import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class SubmittedRecordsScreen extends StatefulWidget {
  final String? userId;
  const SubmittedRecordsScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<SubmittedRecordsScreen> createState() => _SubmittedRecordsScreenState();
}

class _SubmittedRecordsScreenState extends State<SubmittedRecordsScreen> {
  late Future<List<QueryDocumentSnapshot>> _recordsFuture;

  @override
  void initState() {
    super.initState();
    if (widget.userId != null && widget.userId!.isNotEmpty) {
      _loadRecords();
    }
  }

  void _loadRecords() {
    _recordsFuture = FirebaseFirestore.instance
        .collection('record_reviews')
        .where('userId', isEqualTo: widget.userId)
        .orderBy('submittedAt', descending: true)
        .get()
        .then((snap) => snap.docs);
  }

  String _translateStatus(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'approved':
        return 'Elfogadva';
      case 'rejected':
        return 'Elutasítva';
      case 'pending':
        return 'Függőben';
      default:
        return '-';
    }
  }

  Color _statusColor(BuildContext context, String? raw) {
    final scheme = Theme.of(context).colorScheme;
    switch (raw?.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
        return scheme.primary;
      default:
        return scheme.onSurfaceVariant;
    }
  }

  IconData _statusIcon(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'pending':
        return Icons.hourglass_top;
      default:
        return Icons.help_outline;
    }
  }

  Future<void> _deleteRecord(QueryDocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      final imageUrl = data['imageUrl'] as String?;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        final ref = FirebaseStorage.instance.refFromURL(imageUrl);
        await ref.delete();
      }
      await doc.reference.delete();

      if (widget.userId != null && widget.userId!.isNotEmpty) {
        setState(() => _loadRecords());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rekord törölve.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba törlés közben: $e')),
        );
      }
    }
  }

  Future<bool> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Rekord törlése'),
        content: const Text('Biztosan törölni szeretnéd ezt a rekordot? A művelet nem visszavonható.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Mégse'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: const Text('Törlés'),
          ),
        ],
      ),
    ) ??
        false;
    return result;
  }

  Widget _glassCard(BuildContext context, {required Widget child, EdgeInsets? padding}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
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

  Widget _statusPill(BuildContext context, String? rawStatus) {
    final scheme = Theme.of(context).colorScheme;
    final color = _statusColor(context, rawStatus);
    final label = _translateStatus(rawStatus);
    final icon = _statusIcon(rawStatus);

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
            label,
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

  void _openImagePreview(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (widget.userId == null || widget.userId!.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Beküldött rekordok'),
          backgroundColor: scheme.surface,
          surfaceTintColor: scheme.surface,
        ),
        body: const Center(
          child: Text('Jelentkezz be, hogy megtekinthesd a beküldött rekordjaidat.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Beküldött rekordok'),
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        actions: [
          IconButton(
            tooltip: 'Frissítés',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _loadRecords()),
          ),
        ],
      ),
      body: FutureBuilder<List<QueryDocumentSnapshot>>(
        future: _recordsFuture,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Hiba: ${snap.error}'));
          }

          final docs = snap.data ?? [];
          if (docs.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: _glassCard(
                context,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined, size: 46, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 10),
                    Text(
                      'Még nem küldtél be rekordot.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ha beküldesz egy halat, itt követheted a státuszát (függőben / elfogadva / elutasítva).',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Summary header
          final approved = docs.where((d) => ((d.data() as Map<String, dynamic>)['status'] as String?) == 'approved').length;
          final pending = docs.where((d) => ((d.data() as Map<String, dynamic>)['status'] as String?) == 'pending').length;
          final rejected = docs.where((d) => ((d.data() as Map<String, dynamic>)['status'] as String?) == 'rejected').length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              _glassCard(
                context,
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: scheme.primary.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.timeline_outlined, color: scheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Összes beküldés: ${docs.length}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Függőben: $pending • Elfogadva: $approved • Elutasítva: $rejected',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              ...docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final rawStatus = data['status'] as String?;
                final species = (data['fishSpecies'] as String?)?.trim().isNotEmpty == true ? data['fishSpecies'] as String : '-';
                final weightNum = data['fishWeight'] as num?;
                final weightStr = weightNum != null ? weightNum.toStringAsFixed(1) : '-';
                final sizeNum = data['fishSize'] as num?;
                final sizeStr = sizeNum != null ? '${sizeNum.toStringAsFixed(0)} cm' : null;

                final dateTs = data['date'] as Timestamp?;
                final dateStr = dateTs != null ? dateTs.toDate().toIso8601String().split('T').first : '-';

                final location = (data['location'] as String?)?.trim();
                final bait = (data['bait'] as String?)?.trim();
                final imageUrl = (data['imageUrl'] as String?)?.trim();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _glassCard(
                    context,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Image
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            onTap: (imageUrl != null && imageUrl.isNotEmpty)
                                ? () => _openImagePreview(context, imageUrl)
                                : null,
                            child: Container(
                              width: 88,
                              height: 88,
                              color: scheme.surface.withOpacity(0.7),
                              child: (imageUrl != null && imageUrl.isNotEmpty)
                                  ? Image.network(
                                imageUrl,
                                width: 88,
                                height: 88,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(Icons.broken_image, color: scheme.onSurfaceVariant),
                              )
                                  : Icon(Icons.image_not_supported, color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Content
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$species • $weightStr kg',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  _statusPill(context, rawStatus),
                                ],
                              ),
                              const SizedBox(height: 8),

                              _metaRow(context, icon: Icons.calendar_today_outlined, text: dateStr),
                              if (sizeStr != null) ...[
                                const SizedBox(height: 6),
                                _metaRow(context, icon: Icons.straighten_outlined, text: sizeStr),
                              ],
                              if (location != null && location.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _metaRow(context, icon: Icons.place_outlined, text: location),
                              ],
                              if (bait != null && bait.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _metaRow(context, icon: Icons.bug_report_outlined, text: bait),
                              ],

                              const SizedBox(height: 10),

                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final confirm = await _confirmDelete();
                                      if (confirm) await _deleteRecord(doc);
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Törlés'),
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _metaRow(BuildContext context, {required IconData icon, required String text}) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}
