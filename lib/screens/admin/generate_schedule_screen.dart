import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/utils/round_robin.dart';
import '../../models/team.dart';
import '../../services/firestore_service.dart';

class GenerateScheduleScreen extends StatefulWidget {
  final String category;
  final String season;

  const GenerateScheduleScreen({super.key, required this.category, required this.season});

  @override
  State<GenerateScheduleScreen> createState() => _GenerateScheduleScreenState();
}

class _GenerateScheduleScreenState extends State<GenerateScheduleScreen> {
  final _firestoreService = FirestoreService();
  late final _teamsStream = _firestoreService.watchTeams(
      sport: Sport.badminton, category: widget.category, season: widget.season);
  bool _generating = false;
  String? _message;

  Future<void> _generate(List<Team> teams) async {
    setState(() {
      _generating = true;
      _message = null;
    });

    try {
      final existing = await _firestoreService.fetchMatches(
        sport: Sport.badminton,
        category: widget.category,
        season: widget.season,
        stage: 'league',
      );
      if (existing.isNotEmpty) {
        setState(() {
          _message = 'League matches already exist for this category (${existing.length} found) — '
              'delete them first from Admin > Matches if you want to regenerate.';
        });
        return;
      }

      final matches = generateLeagueMatches(
        teams: teams,
        sport: Sport.badminton,
        category: widget.category,
        season: widget.season,
      );
      await _firestoreService.addMatchesBatch(matches);

      setState(() => _message = 'Generated ${matches.length} league matches. Good luck out there!');
    } catch (e) {
      setState(() => _message = '$e');
    } finally {
      setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Generate Schedule')),
      body: StreamBuilder<List<Team>>(
        stream: _teamsStream,
        builder: (context, snapshot) {
          final teams = snapshot.data ?? [];
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${teams.length} teams found for this category.', style: textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'This creates ${teams.length < 2 ? 0 : teams.length * (teams.length - 1) ~/ 2} '
                  'league matches — everyone plays everyone once, round-robin style.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(_generating ? 'Generating...' : 'Generate League Schedule'),
                  onPressed: teams.length < 2 || _generating ? null : () => _generate(teams),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(_message!),
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.push('/admin/matches?category=${widget.category}'),
                  child: const Text('View matches'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
