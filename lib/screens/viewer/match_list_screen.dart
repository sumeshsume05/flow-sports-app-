import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/sports.dart';
import '../../core/utils/match_grouping.dart';
import '../../models/match.dart';
import '../../services/firestore_service.dart';
import '../../widgets/match_card.dart';
import '../../widgets/match_section_header.dart';
import '../../widgets/shimmer_loading.dart';

enum _Filter { all, upcoming, live, completed }

class MatchListScreen extends StatefulWidget {
  final String sport;
  final String category;
  final String season;

  const MatchListScreen({super.key, required this.sport, required this.category, required this.season});

  @override
  State<MatchListScreen> createState() => _MatchListScreenState();
}

class _MatchListScreenState extends State<MatchListScreen> {
  final _firestoreService = FirestoreService();
  late final _matchesStream = _firestoreService.watchMatches(
      sport: widget.sport, category: widget.category, season: widget.season);
  _Filter _filter = _Filter.all;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${categoryLabel(widget.category)} ${sportConfig(widget.sport).label}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm + 4, AppSpacing.sm + 4, AppSpacing.sm + 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search a team…',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterButton(
                  label: 'Standings',
                  icon: Icons.leaderboard_outlined,
                  onTap: () => context.push('/standings?sport=${widget.sport}&category=${widget.category}'),
                ),
                _FilterButton(
                  label: 'Bracket',
                  icon: Icons.account_tree_outlined,
                  onTap: () => context.push('/bracket?sport=${widget.sport}&category=${widget.category}'),
                ),
              ],
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 4, vertical: AppSpacing.sm),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in _Filter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs + 2),
                      child: ChoiceChip(
                        label: Text(_labelFor(f)),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Match>>(
              stream: _matchesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const ShimmerList();
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Something went wrong: ${snapshot.error}'));
                }
                var matches = snapshot.data ?? [];

                matches = _applyFilter(matches);
                if (_search.isNotEmpty) {
                  matches = matches
                      .where((m) =>
                          (m.teamA.name ?? '').toLowerCase().contains(_search) ||
                          (m.teamB.name ?? '').toLowerCase().contains(_search))
                      .toList();
                }

                if (matches.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text('No matches to show yet — check back once the schedule is out.'),
                    ),
                  );
                }

                final sections = groupMatchesForDisplay(matches);

                return RefreshIndicator(
                  onRefresh: () async {
                    // Firestore streams already push live; this is a reassuring
                    // fallback gesture, not a functional requirement.
                    await Future.delayed(const Duration(milliseconds: 400));
                  },
                  child: ListView(
                    padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.md),
                    children: [
                      for (final section in sections) ...[
                        MatchSectionHeader(section: section),
                        for (final m in _liveFirst(section.matches))
                          MatchCard(
                            match: m,
                            onTap: () => context.push('/matches/${m.id}'),
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _labelFor(_Filter f) => switch (f) {
        _Filter.all => 'All',
        _Filter.upcoming => 'Upcoming',
        _Filter.live => 'Live',
        _Filter.completed => 'Completed',
      };

  List<Match> _applyFilter(List<Match> matches) {
    return switch (_filter) {
      _Filter.all => matches,
      _Filter.upcoming => matches.where((m) => m.status == MatchStatus.upcoming).toList(),
      _Filter.live => matches.where((m) => m.status == MatchStatus.live).toList(),
      _Filter.completed => matches.where((m) => m.status == MatchStatus.completed).toList(),
    };
  }

  /// Live matches surfaced first within a section (matches are already
  /// grouped into rounds/stages by [groupMatchesForDisplay]).
  List<Match> _liveFirst(List<Match> matches) {
    final sorted = List<Match>.of(matches);
    sorted.sort((a, b) {
      int rank(MatchStatus s) => switch (s) {
            MatchStatus.live => 0,
            MatchStatus.upcoming => 1,
            MatchStatus.completed => 2,
          };
      final byStatus = rank(a.status).compareTo(rank(b.status));
      if (byStatus != 0) return byStatus;
      return a.matchNumber.compareTo(b.matchNumber);
    });
    return sorted;
  }
}

class _FilterButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _FilterButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: AppSpacing.xs),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: IconButton(
        icon: Icon(icon),
        tooltip: label,
        onPressed: onTap,
      ),
    );
  }
}
