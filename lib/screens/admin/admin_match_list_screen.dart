import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/app_spacing.dart';
import '../../core/utils/match_grouping.dart';
import '../../models/match.dart';
import '../../services/firestore_service.dart';
import '../../widgets/match_card.dart';
import '../../widgets/match_section_header.dart';
import '../../widgets/shimmer_loading.dart';

class AdminMatchListScreen extends StatelessWidget {
  final String sport;
  final String category;
  final String season;
  final _firestoreService = FirestoreService();
  late final _matchesStream =
      _firestoreService.watchMatches(sport: sport, category: category, season: season);

  AdminMatchListScreen({super.key, required this.sport, required this.category, required this.season});

  Future<void> _confirmDelete(BuildContext context, Match match) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete match?'),
        content: Text('Remove ${match.label}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _firestoreService.deleteMatch(match.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matches')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/matches/new?sport=$sport&category=$category'),
        icon: const Icon(Icons.add),
        label: const Text('New match'),
      ),
      body: StreamBuilder<List<Match>>(
        stream: _matchesStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const ShimmerList();
          }
          final matches = snapshot.data!;
          if (matches.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text('No matches yet — generate a schedule from the dashboard first.'),
              ),
            );
          }
          final sections = groupMatchesForDisplay(matches);
          return ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            children: [
              for (final section in sections) ...[
                MatchSectionHeader(section: section),
                for (final m in section.matches)
                  MatchCard(
                    match: m,
                    onTap: () => context.push('/admin/matches/${m.id}/edit'),
                    showReactions: false,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(context, m),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
