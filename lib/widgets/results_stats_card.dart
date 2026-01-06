import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ResultsStatsCard extends StatelessWidget {
  final String userId;

  const ResultsStatsCard({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('record_reviews')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Notice(
            icon: Icons.warning_amber_rounded,
            title: 'A statisztikák nem érhetők el',
            message: 'Hiba történt az adatok betöltése közben. Próbáld újra később.',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _StatsSkeleton();
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _Notice(
            icon: Icons.insights_outlined,
            title: 'Még nincs elfogadott rekord',
            message: 'Amint elfogadnak egy feltöltést, itt megjelennek a statisztikák.',
          );
        }

        final totalApproved = docs.length;

        // Most used bait
        final baitCounts = <String, int>{};
        for (final doc in docs) {
          final data = (doc.data() as Map<String, dynamic>);
          final bait = (data['bait'] as String?)?.trim() ?? '';
          if (bait.isNotEmpty) baitCounts[bait] = (baitCounts[bait] ?? 0) + 1;
        }
        String? mostUsedBait;
        if (baitCounts.isNotEmpty) {
          mostUsedBait = baitCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
        }

        // Avg size
        final sizes = docs
            .map((doc) => (doc.data() as Map<String, dynamic>)['fishSize'] as num?)
            .whereType<num>()
            .map((n) => n.toDouble())
            .toList();
        final avgSize = sizes.isNotEmpty ? sizes.reduce((a, b) => a + b) / sizes.length : 0.0;

        // Latest date
        final dates = docs
            .map((doc) => (doc.data() as Map<String, dynamic>)['date'] as Timestamp?)
            .whereType<Timestamp>()
            .map((t) => t.toDate())
            .toList()
          ..sort((a, b) => b.compareTo(a));
        final latestDate = dates.isNotEmpty ? dates.first : null;
        final formattedDate = latestDate == null
            ? null
            : '${latestDate.year}. ${latestDate.month.toString().padLeft(2, '0')}. ${latestDate.day.toString().padLeft(2, '0')}.';

        // Top 3 by weight (defensive: fishWeight may be missing)
        final sortedByWeight = docs.toList()
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aWeight = (aData['fishWeight'] as num?)?.toDouble() ?? -1;
            final bWeight = (bData['fishWeight'] as num?)?.toDouble() ?? -1;
            return bWeight.compareTo(aWeight);
          });
        final top3 = sortedByWeight.take(3).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Összefoglaló', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),

            // KPI grid
            LayoutBuilder(
              builder: (context, c) {
                final isWide = c.maxWidth >= 560;
                final crossAxisCount = isWide ? 4 : 2;

                final tiles = <Widget>[
                  _KpiTile(
                    label: 'Elfogadott rekord',
                    value: '$totalApproved',
                    icon: Icons.verified_outlined,
                  ),
                  _KpiTile(
                    label: 'Átlagos méret',
                    value: '${avgSize.toStringAsFixed(1)} cm',
                    icon: Icons.straighten_outlined,
                  ),
                  _KpiTile(
                    label: 'Legutóbbi rögzítés',
                    value: formattedDate ?? '—',
                    icon: Icons.event_outlined,
                  ),
                  _KpiTile(
                    label: 'Top csali',
                    value: mostUsedBait ?? '—',
                    icon: Icons.sell_outlined,
                  ),
                ];

                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: isWide ? 2.6 : 2.2,
                  children: tiles,
                );
              },
            ),

            const SizedBox(height: 16),
            Divider(color: scheme.outlineVariant.withOpacity(0.35)),
            const SizedBox(height: 12),

            Text('Top fogások', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),

            _Top3Grid(top3: top3),
          ],
        );
      },
    );
  }
}

// ---------------------------
// UI Components (private)
// ---------------------------

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Top3Grid extends StatelessWidget {
  final List<QueryDocumentSnapshot> top3;

  const _Top3Grid({required this.top3});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (top3.isEmpty) {
      return _Notice(
        icon: Icons.photo_outlined,
        title: 'Nincs megjeleníthető kép',
        message: 'A top fogások akkor jelennek meg, ha van feltöltött kép a rekordhoz.',
      );
    }

    return Row(
      children: top3.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final imageUrl = data['imageUrl'] as String?;
        final weight = (data['fishWeight'] as num?)?.toDouble();

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl != null && imageUrl.trim().isNotEmpty)
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
                        ),
                      )
                    else
                      Container(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(Icons.image_not_supported_outlined, color: scheme.onSurfaceVariant),
                      ),

                    // subtle overlay for label
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.40),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          weight == null ? '— kg' : '${weight.toStringAsFixed(2)} kg',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
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

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget line(double w) => FractionallySizedBox(
      widthFactor: w,
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withOpacity(0.65),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );

    Widget tile() => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                line(0.7),
                const SizedBox(height: 8),
                line(0.45),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line(0.35),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [tile(), tile(), tile(), tile()],
        ),
        const SizedBox(height: 16),
        line(0.25),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _squareSkeleton(context)),
            const SizedBox(width: 8),
            Expanded(child: _squareSkeleton(context)),
            const SizedBox(width: 8),
            Expanded(child: _squareSkeleton(context)),
          ],
        ),
      ],
    );
  }

  Widget _squareSkeleton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: scheme.surfaceContainerHighest.withOpacity(0.55),
        ),
      ),
    );
  }
}
