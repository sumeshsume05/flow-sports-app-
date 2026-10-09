import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/app_spacing.dart';
import '../../core/utils/manual_match.dart';
import '../../core/utils/sections.dart';
import '../../models/match.dart';
import '../../models/team.dart';
import '../../services/firestore_service.dart';

/// Manual match creation. Normally matches come from "Generate Schedule" and
/// "Generate Bracket"; this is for the cases those don't cover:
///  * League match — a real tournament match the generated schedule missed
///    (or a replacement). It counts in the points table, so in a sectioned
///    league both teams must be in the same section.
///  * Friendly — a practice/exhibition match that is shown in the lists but
///    never counted in standings, qualification or the bracket.
/// Tie-breakers and the Final's decider are created by Generate Bracket, not
/// here.
class AdminMatchFormScreen extends StatefulWidget {
  final String sport;
  final String category;
  final String season;

  const AdminMatchFormScreen({super.key, required this.sport, required this.category, required this.season});

  @override
  State<AdminMatchFormScreen> createState() => _AdminMatchFormScreenState();
}

class _AdminMatchFormScreenState extends State<AdminMatchFormScreen> {
  final _firestoreService = FirestoreService();
  late final _teamsStream = _firestoreService.watchTeams(
      sport: widget.sport, category: widget.category, season: widget.season);
  final _labelController = TextEditingController();
  ManualMatchType _type = ManualMatchType.league;
  Team? _teamA;
  Team? _teamB;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<bool> _confirmDuplicate(Match existing) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('These teams already play each other'),
        content: Text('"${existing.label}" is already a league match between ${existing.teamA.name} and '
            '${existing.teamB.name}. A second league match counts again in the points table. '
            'Add it anyway?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add anyway')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _submit(List<Team> teams) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Fetch every match of this category so numbering and the duplicate
      // check see friendlies and league matches alike.
      final existing = await _firestoreService.fetchMatches(
        sport: widget.sport,
        category: widget.category,
        season: widget.season,
      );
      final check = checkManualMatch(
        type: _type,
        teamA: _teamA,
        teamB: _teamB,
        teams: teams,
        existing: existing,
      );
      if (!check.ok) {
        setState(() => _error = check.error);
        return;
      }
      if (check.duplicateOf != null && !await _confirmDuplicate(check.duplicateOf!)) return;

      await _firestoreService.addMatch(buildManualMatch(
        type: _type,
        teamA: _teamA!,
        teamB: _teamB!,
        label: _labelController.text,
        sport: widget.sport,
        category: widget.category,
        season: widget.season,
        existing: existing,
        section: check.section,
      ));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New Match')),
      body: StreamBuilder<List<Team>>(
        stream: _teamsStream,
        builder: (context, snapshot) {
          final teams = snapshot.data ?? [];
          if (teams.isEmpty) {
            return const Center(child: Text('Add teams first, from the Teams screen.'));
          }
          final sectioned = isSectionedCategory(teams);
          String teamLabel(Team t) => sectioned && t.section != null ? '${t.name}  (Section ${t.section})' : t.name;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Match type', style: textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                SegmentedButton<ManualMatchType>(
                  segments: const [
                    ButtonSegment(value: ManualMatchType.league, label: Text('League match')),
                    ButtonSegment(value: ManualMatchType.friendly, label: Text('Friendly')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() {
                    _type = s.first;
                    _error = null;
                  }),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _type == ManualMatchType.league
                      ? 'Counts in the points table and qualification, like any generated league match.'
                          '${sectioned ? ' Both teams must be in the same section.' : ''} '
                          'Use this for a match the schedule missed or a replacement.'
                      : 'A practice or exhibition match. It is listed with the other matches but never '
                          'counts in standings, qualification or the bracket.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _labelController,
                  decoration: InputDecoration(
                    labelText: 'Label (optional)',
                    hintText: _type == ManualMatchType.league ? 'Extra Match' : 'Friendly',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<Team>(
                  initialValue: _teamA,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Team A'),
                  items: [for (final t in teams) DropdownMenuItem(value: t, child: Text(teamLabel(t)))],
                  onChanged: (v) => setState(() => _teamA = v),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<Team>(
                  initialValue: _teamB,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Team B'),
                  items: [for (final t in teams) DropdownMenuItem(value: t, child: Text(teamLabel(t)))],
                  onChanged: (v) => setState(() => _teamB = v),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton(
                  onPressed: _saving ? null : () => _submit(teams),
                  child: Text(_saving ? 'Creating...' : 'Create match'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
