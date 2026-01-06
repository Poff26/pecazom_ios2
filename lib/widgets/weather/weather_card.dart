import 'package:flutter/material.dart';

class WeatherCard extends StatelessWidget {
  final String location;
  final String temperature;
  final String description;
  final String iconUrl;

  const WeatherCard({
    super.key,
    required this.location,
    required this.temperature,
    required this.description,
    required this.iconUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Image.network(
            iconUrl.startsWith('//') ? 'https:$iconUrl' : iconUrl,
            width: 64,
            height: 64,
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(location, style: Theme.of(context).textTheme.titleMedium),
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
              Text(temperature,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          )
        ],
      ),
    );
  }
}
