import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/utils/round_robin.dart';
import '../../models/team.dart';
import '../../services/firestore_service.dart';

class GenerateScheduleScreen extends StatefulWidget {
  final String sport;
  final String category;
  final String season;

  const GenerateScheduleScreen({super.key, required this.sport, required this.category, required this.season});

  @override
  State<GenerateScheduleScreen> createState() => _GenerateScheduleScreenState();
}

class _GenerateScheduleScreenState extends State<GenerateScheduleScreen> {
  final _firestoreService = FirestoreService();
  late final _teamsStream = _firestoreService.watchTeams(
      sport: widget.sport, category: widget.category, season: widget.season);
  bool _generating = false;
  String? _message;

  /// null = no team has a section (single round-robin); a sorted list of
  /// section names = every team has one (sectioned round-robin). Mixed —
  /// some teams sectioned, some not — is its own state so the UI can block
  /// generation with a clear message instead of guessing what was meant.
  ({List<String>? sections, bool mixed}) _sectionState(List<Team> teams) {
    final withSection = teams.where((t) => t.section != null).length;
    if (withSection == 0) return (sections: null, mixed: false);
    if (withSection < teams.length) return (sections: null, mixed: true);
    final sections = teams.map((t) => t.section!).toSet().toList()..sort();
    return (sections: sections, mixed: false);
  }

  Future<void> _generate(List<Team> teams, List<String>? sections) async {
    setState(() {
      _generating = true;
      _message = null;
    });

    try {
      final existing = await _firestoreService.fetchMatches(
        sport: widget.sport,
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

      final matches = sections == null
          ? generateLeagueMatches(
              teams: teams,
              sport: widget.sport,
              category: widget.category,
              season: widget.season,
            )
          : generateSectionedLeagueMatches(
              teams: teams,
              sport: widget.sport,
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
          final sectionState = _sectionState(teams);
          final sections = sectionState.sections;

          String pairCountText(int n) => n < 2 ? '0' : '${n * (n - 1) ~/ 2}';

          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${teams.length} teams found for this category.', style: textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                if (sectionState.mixed)
                  Text(
                    'Some teams have a league section set and some don\'t. Assign every team to a '
                    'section (or clear all of them) in Admin > Teams before generating.',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.warningAmber),
                  )
                else if (sections != null)
                  Text(
                    'Sectioned round-robin detected: ${sections.map((s) {
                      final n = teams.where((t) => t.section == s).length;
                      return 'Section $s ($n teams, ${pairCountText(n)} matches)';
                    }).join(' · ')}. Teams only play others in their own section.',
                    style: textTheme.bodySmall,
                  )
                else
                  Text(
                    'This creates ${pairCountText(teams.length)} '
                    'league matches — everyone plays everyone once, round-robin style.',
                    style: textTheme.bodySmall,
                  ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(_generating
                      ? 'Generating...'
                      : sections != null
                          ? 'Generate Sectioned Schedule'
                          : 'Generate League Schedule'),
                  onPressed: teams.length < 2 || _generating || sectionState.mixed
                      ? null
                      : () => _generate(teams, sections),
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
                  onPressed: () => context.push('/admin/matches?sport=${widget.sport}&category=${widget.category}'),
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
