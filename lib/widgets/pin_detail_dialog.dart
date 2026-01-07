// lib/widgets/pin_detail_dialog.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import '../models/fishing_pin.dart';

class PinDetailDialog extends StatelessWidget {
  final FishingPin pin;
  const PinDetailDialog({Key? key, required this.pin}) : super(key: key);

  Color _safeParseColor(String input) {
    var hex = input.trim().replaceAll('#', '');
    // ha valaki már FF-fel tárolta
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length > 8) hex = hex.substring(hex.length - 8);
    if (hex.length != 8) return const Color(0xFF00C853);
    return Color(int.parse('0x$hex'));
  }

  Widget _specRow(BuildContext context, {required String label, required String value, IconData? icon}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassCard(BuildContext context, {required Widget child, EdgeInsets? padding}) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding ?? const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surface.withOpacity(0.80),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.14),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _safeParseColor(pin.pinColor ?? '');

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: _glassCard(
          context,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 10),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 10, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (pin.name ?? '').trim().isEmpty ? 'Mentett hely' : pin.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: 'Bezár',
                    ),
                  ],
                ),
              ),

              // Image (optional)
              if ((pin.imageUrl ?? '').isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(0)),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      pin.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: scheme.surfaceVariant.withOpacity(0.35),
                        child: Icon(Icons.broken_image, color: scheme.onSurfaceVariant, size: 32),
                      ),
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: scheme.surfaceVariant.withOpacity(0.35),
                          child: const Center(child: CircularProgressIndicator()),
                        );
                      },
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                child: Column(
                  children: [
                    _specRow(
                      context,
                      label: 'Halfaj',
                      value: (pin.fishSpecies ?? '').trim().isEmpty ? '—' : pin.fishSpecies!,
                      icon: Icons.set_meal_outlined,
                    ),
                    _specRow(
                      context,
                      label: 'Súly',
                      value: '${(pin.fishWeight ?? 0).toStringAsFixed(2)} kg',
                      icon: Icons.fitness_center_outlined,
                    ),
                    _specRow(
                      context,
                      label: 'Méret',
                      value: '${(pin.fishSize ?? 0).toStringAsFixed(1)} cm',
                      icon: Icons.straighten_outlined,
                    ),

                    const Divider(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Jelölőszín',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          (pin.pinColor ?? '—'),
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
