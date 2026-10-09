import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/app_spacing.dart';
import '../../models/match.dart';
import '../../models/team.dart';
import '../../services/firestore_service.dart';

/// Manual ad-hoc match creation — rarely used, since bulk creation normally
/// happens via "Generate Schedule". Useful for a one-off replay/tiebreaker
/// match the admin needs to add by hand.
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
  Team? _teamA;
  Team? _teamB;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _submit(List<Team> teams) async {
    if (_teamA == null || _teamB == null || _teamA!.id == _teamB!.id) {
      setState(() => _error = 'Choose two different teams.');
      return;
    }
    final label = _labelController.text.trim().isEmpty ? 'Extra Match' : _labelController.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final existing = await _firestoreService.fetchMatches(
        sport: widget.sport,
        category: widget.category,
        season: widget.season,
        stage: 'league',
      );
      final nextNumber = existing.isEmpty
          ? 1
          : existing.map((m) => m.matchNumber).reduce((a, b) => a > b ? a : b) + 1;

      await _firestoreService.addMatch(Match(
        id: '',
        sport: widget.sport,
        category: widget.category,
        season: widget.season,
        stage: MatchStage.league,
        matchNumber: nextNumber,
        label: label,
        matchCode: 'L$nextNumber',
        teamA: TeamRef(teamId: _teamA!.id, name: _teamA!.name),
        teamB: TeamRef(teamId: _teamB!.id, name: _teamB!.name),
        status: MatchStatus.upcoming,
        notifyTopic: '${widget.sport}_${widget.category}',
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
    return Scaffold(
      appBar: AppBar(title: const Text('New Match')),
      body: StreamBuilder<List<Team>>(
        stream: _teamsStream,
        builder: (context, snapshot) {
          final teams = snapshot.data ?? [];
          if (teams.isEmpty) {
            return const Center(child: Text('Add teams first, from the Teams screen.'));
          }
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _labelController,
                  decoration: const InputDecoration(labelText: 'Label (optional)'),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<Team>(
                  initialValue: _teamA,
                  decoration: const InputDecoration(labelText: 'Team A'),
                  items: [
                    for (final t in teams) DropdownMenuItem(value: t, child: Text(t.name)),
                  ],
                  onChanged: (v) => setState(() => _teamA = v),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<Team>(
                  initialValue: _teamB,
                  decoration: const InputDecoration(labelText: 'Team B'),
                  items: [
                    for (final t in teams) DropdownMenuItem(value: t, child: Text(t.name)),
                  ],
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
