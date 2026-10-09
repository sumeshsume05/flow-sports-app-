import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../models/team.dart';
import '../../services/firestore_service.dart';
import '../../widgets/shimmer_loading.dart';

class AdminTeamsScreen extends StatefulWidget {
  final String sport;
  final String category;
  final String season;

  const AdminTeamsScreen({super.key, required this.sport, required this.category, required this.season});

  @override
  State<AdminTeamsScreen> createState() => _AdminTeamsScreenState();
}

class _AdminTeamsScreenState extends State<AdminTeamsScreen> {
  final _firestoreService = FirestoreService();
  late final _teamsStream = _firestoreService.watchTeams(
      sport: widget.sport, category: widget.category, season: widget.season);

  void _showWriteError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }

  Future<void> _addTeamDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Team'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
              hintText: widget.sport == Sport.cricket ? 'e.g. FLOW Strikers' : 'e.g. Firstname & Firstname'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await _firestoreService.addTeam(Team(
        id: '',
        sport: widget.sport,
        category: widget.category,
        name: name,
        season: widget.season,
      ));
    } catch (e) {
      _showWriteError(e);
    }
  }

  Future<void> _editTeamDialog(Team team) async {
    final controller = TextEditingController(text: team.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Team'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e.g. Firstname & Firstname'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == team.name) return;
    try {
      await _firestoreService.updateTeam(team.id, name: name);
    } catch (e) {
      _showWriteError(e);
    }
  }

  /// Badminton shows only the seed; cricket also shows how many players the
  /// team has so a missing roster is obvious before match day.
  Widget? _subtitleFor(Team team) {
    final parts = <String>[
      if (team.seed != null) 'Seed ${team.seed}',
      if (widget.sport == Sport.cricket)
        team.activePlayers.isEmpty ? 'No players yet' : '${team.activePlayers.length} players',
    ];
    return parts.isEmpty ? null : Text(parts.join(' · '));
  }

  static const _sectionOptions = ['None', 'A', 'B'];

  /// Suggests a balanced 2-way split, alternating teams (in their current
  /// list order) A, B, A, B, ... — a starting point, not a final decision:
  /// the admin can still tap any team's chip afterward to move it to a
  /// different section by hand. Fixed at exactly 2 sections because that's
  /// all Generate Bracket currently supports (it feeds each section's top
  /// 2 into the existing 4-team knockout) — see CLAUDE.md's "Planned
  /// changes" for lifting that fixed shape.
  Future<void> _autoArrangeDialog(List<Team> teams) async {
    const letters = ['A', 'B'];
    try {
      await Future.wait([
        for (var i = 0; i < teams.length; i++)
          _firestoreService.updateTeamSection(teams[i].id, letters[i % letters.length]),
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Arranged ${teams.length} teams into 2 sections — tap any team to move it.'),
        ));
      }
    } catch (e) {
      _showWriteError(e);
    }
  }

  Future<void> _pickSectionDialog(Team team) async {
    final section = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('League Section'),
        children: [
          for (final option in _sectionOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option == 'None' ? '' : option),
              child: Row(
                children: [
                  if ((team.section ?? 'None') == option)
                    const Padding(
                      padding: EdgeInsets.only(right: AppSpacing.sm),
                      child: Icon(Icons.check, size: 18),
                    ),
                  Text(option == 'None' ? 'None (single round-robin)' : 'Section $option'),
                ],
              ),
            ),
        ],
      ),
    );
    if (section == null) return;
    try {
      await _firestoreService.updateTeamSection(team.id, section.isEmpty ? null : section);
    } catch (e) {
      _showWriteError(e);
    }
  }

  Future<void> _confirmDelete(Team team) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete team?'),
        content: Text('Remove "${team.name}"? This does not delete any matches already created for them.'),
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
        await _firestoreService.deleteTeam(team.id);
      } catch (e) {
        _showWriteError(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teams')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTeamDialog,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Team>>(
        stream: _teamsStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const ShimmerList(itemHeight: 56);
          }
          final teams = snapshot.data!;
          if (teams.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text('No teams added yet — tap + to add your first team.'),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: teams.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Auto-arrange into sections'),
                    onPressed: () => _autoArrangeDialog(teams),
                  ),
                );
              }
              final team = teams[i - 1];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: ListTile(
                    leading: ActionChip(
                      label: Text(team.section ?? '—'),
                      onPressed: () => _pickSectionDialog(team),
                      tooltip: 'Set league section',
                    ),
                    title: Text(team.name),
                    subtitle: _subtitleFor(team),
                    onTap: () => _editTeamDialog(team),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.sport == Sport.cricket)
                          IconButton(
                            icon: const Icon(Icons.groups_outlined),
                            tooltip: 'Players',
                            onPressed: () => context.push('/admin/teams/${team.id}/players'),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(team),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
