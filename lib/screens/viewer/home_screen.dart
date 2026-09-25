import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../models/match.dart';
import '../../services/firestore_service.dart';

class HomeScreen extends StatelessWidget {
  final String season;

  const HomeScreen({super.key, required this.season});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('FLOW Arena'),
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_outlined),
            tooltip: 'Admin',
            onPressed: () => context.push('/admin'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, AppColors.pink],
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FLOW ARENA',
                  style: textTheme.headlineLarge?.copyWith(
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Every Match. Every Point. Live.',
                  style: textTheme.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05, end: 0),
          const SizedBox(height: AppSpacing.lg),
          Text('Badminton', style: textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < Category.all.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            _CategoryCard(
              title: '${categoryLabel(Category.all[i])} Doubles',
              subtitle: 'Standings, live scores & the knockout bracket',
              icon: Icons.sports_tennis,
              accent: i.isEven ? AppColors.boysAccent : AppColors.girlsAccent,
              category: Category.all[i],
              season: season,
              onTap: () => context.push('/matches?category=${Category.all[i]}'),
            ).animate(delay: (80 * (i + 1)).ms).fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0),
          ],
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final String category;
  final String season;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.category,
    required this.season,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 28, color: accent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: textTheme.titleMedium),
                        const SizedBox(width: AppSpacing.xs),
                        _LiveCountBadge(category: category, season: season),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small "🔴 N live now" teaser sourced from the existing matches stream —
/// no new data model needed, just a client-side count of live matches.
class _LiveCountBadge extends StatelessWidget {
  final String category;
  final String season;
  final _firestoreService = FirestoreService();

  _LiveCountBadge({required this.category, required this.season});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Match>>(
      stream: _firestoreService.watchMatches(
          sport: Sport.badminton, category: category, season: season),
      builder: (context, snapshot) {
        final liveCount =
            (snapshot.data ?? []).where((m) => m.status == MatchStatus.live).length;
        if (liveCount == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs + 2, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.liveRed.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            '🔴 $liveCount live now',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.liveRed, fontWeight: FontWeight.w700),
          ),
        );
      },
    );
  }
}
