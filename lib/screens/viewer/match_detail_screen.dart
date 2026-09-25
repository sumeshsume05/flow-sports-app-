import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../models/match.dart';
import '../../services/firestore_service.dart';
import '../../widgets/status_badge.dart';

class MatchDetailScreen extends StatelessWidget {
  final String matchId;
  final _firestoreService = FirestoreService();
  late final _matchStream = _firestoreService.watchMatch(matchId);

  MatchDetailScreen({super.key, required this.matchId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match Detail')),
      body: StreamBuilder<Match?>(
        stream: _matchStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final match = snapshot.data;
          if (match == null) {
            return const Center(child: Text('Match not found.'));
          }
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(match.label, style: Theme.of(context).textTheme.titleLarge)),
                    StatusBadge(status: match.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Column(
                    children: [
                      _TeamScoreRow(
                          name: match.teamA.name ?? 'TBD',
                          score: match.scoreA,
                          won: match.result == MatchResult.teamA),
                      const Divider(height: AppSpacing.lg),
                      _TeamScoreRow(
                          name: match.teamB.name ?? 'TBD',
                          score: match.scoreB,
                          won: match.result == MatchResult.teamB),
                    ],
                  ),
                ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0),
                const SizedBox(height: AppSpacing.lg),
                if (match.venue != null)
                  _InfoRow(icon: Icons.location_on_outlined, label: match.venue!),
                if (match.court != null)
                  _InfoRow(icon: Icons.sports_tennis, label: 'Court ${match.court}'),
                if (match.notes != null) _InfoRow(icon: Icons.notes, label: match.notes!),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('Share result'),
                  onPressed: () => _share(match),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _share(Match match) {
    final a = match.teamA.name ?? 'TBD';
    final b = match.teamB.name ?? 'TBD';
    final text = match.status == MatchStatus.completed
        ? '${match.label}: $a ${match.scoreA} - ${match.scoreB} $b'
        : '${match.label}: $a vs $b (${match.status.name})';
    Share.share(text);
  }
}

class _TeamScoreRow extends StatelessWidget {
  final String name;
  final int? score;
  final bool won;

  const _TeamScoreRow({required this.name, required this.score, required this.won});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 22,
      fontWeight: won ? FontWeight.w800 : FontWeight.w400,
      color: won ? scheme.primary : null,
    );
    return Row(
      children: [
        if (won) ...[
          const Icon(Icons.emoji_events_rounded, color: AppColors.winGreen),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(child: Text(name, style: style)),
        if (score != null) Text('$score', style: style),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Text(label),
        ],
      ),
    );
  }
}
