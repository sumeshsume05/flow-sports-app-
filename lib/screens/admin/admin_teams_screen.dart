import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../models/team.dart';
import '../../services/firestore_service.dart';
import '../../widgets/shimmer_loading.dart';

class AdminTeamsScreen extends StatefulWidget {
  final String category;
  final String season;

  const AdminTeamsScreen({super.key, required this.category, required this.season});

  @override
  State<AdminTeamsScreen> createState() => _AdminTeamsScreenState();
}

class _AdminTeamsScreenState extends State<AdminTeamsScreen> {
  final _firestoreService = FirestoreService();
  late final _teamsStream = _firestoreService.watchTeams(
      sport: Sport.badminton, category: widget.category, season: widget.season);

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
          decoration: const InputDecoration(hintText: 'e.g. Firstname & Firstname'),
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
        sport: Sport.badminton,
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
            itemCount: teams.length,
            itemBuilder: (context, i) {
              final team = teams[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: ListTile(
                    title: Text(team.name),
                    subtitle: team.seed != null ? Text('Seed ${team.seed}') : null,
                    onTap: () => _editTeamDialog(team),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(team),
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
