import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/design/app_colors.dart';
import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../core/utils/podium_resolver.dart';

/// Final-placement summary shown once a bracket's Final is complete — makes
/// the champion/runner-up/semifinalists visible at a glance for both
/// viewers and admins, instead of only a small trophy icon buried inside the
/// Final's match box.
class PodiumCard extends StatelessWidget {
  final Podium podium;

  const PodiumCard({super.key, required this.podium});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.orange, AppColors.pink],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🏆  Champion', style: textTheme.labelLarge?.copyWith(color: Colors.white70)),
          const SizedBox(height: 2),
          Text(
            podium.champion.name ?? 'TBD',
            style: textTheme.headlineMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('🥈  Runner-up', style: textTheme.labelLarge?.copyWith(color: Colors.white70)),
          const SizedBox(height: 2),
          Text(
            podium.runnerUp.name ?? 'TBD',
            style: textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          if (podium.semifinalists.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              podium.semifinalists.length == 1 ? '🥉  3rd place' : '🥉  Semifinalists',
              style: textTheme.labelLarge?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 2),
            Text(
              podium.semifinalists.map((t) => t.name ?? 'TBD').join('  ·  '),
              style: textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0);
  }
}
