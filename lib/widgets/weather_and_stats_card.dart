import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class WeatherAndStatsCard extends StatelessWidget {
  final String? userId;

  const WeatherAndStatsCard({Key? key, required this.userId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Ha nincs bejelentkezve a user, info card jelenjen meg!
    if (userId == null || userId!.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Csak bejelentkezve láthatod a saját statisztikáidat!',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('fishing_pins')
          .where('userId', isEqualTo: userId)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Text('Hiba történt a statisztikák lekérésekor.');
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Még nincs mentett fogásod.'),
            ),
          );
        }

        final fishWeights = docs.map((d) => (d['fishWeight'] ?? 0).toDouble()).toList();
        final fishSizes = docs.map((d) => (d['fishSize'] ?? 0).toDouble()).toList();
        final fishSpecies = docs.map((d) => (d['fishSpecies'] ?? '') as String).toList();

        final totalCatches = docs.length;
        final biggestFish = fishWeights.isNotEmpty ? fishWeights.reduce((a, b) => a > b ? a : b) : 0.0;
        final averageSize = fishSizes.isNotEmpty
            ? (fishSizes.reduce((a, b) => a + b) / fishSizes.length).toStringAsFixed(1)
            : '0';

        final speciesCount = <String, int>{};
        for (final species in fishSpecies) {
          if (species.isEmpty) continue;
          speciesCount[species] = (speciesCount[species] ?? 0) + 1;
        }
        final favoriteSpecies = speciesCount.entries.isNotEmpty
            ? speciesCount.entries.reduce((a, b) => a.value > b.value ? a : b).key
            : 'Nincs adat';

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("📊 Statisztikáid",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text("🎯 Fogások száma: $totalCatches"),
                Text("🏆 Legnagyobb hal súlya: ${biggestFish.toStringAsFixed(1)} kg"),
                Text("📏 Átlagos méret: $averageSize cm"),
                Text("🐟 Leggyakoribb halfaj: $favoriteSpecies"),
              ],
            ),
          ),
        );
      },
    );
  }
}
