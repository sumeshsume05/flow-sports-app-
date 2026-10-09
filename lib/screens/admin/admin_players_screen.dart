import 'package:flutter/material.dart';

import '../../core/cricket/player_names.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../services/firestore_service.dart';
import '../../widgets/shimmer_loading.dart';

/// A cricket team's roster. Players are only added, renamed, re-ordered or
/// switched off — never deleted — because match lineups and ball events refer
/// to a player by id, and a switched-off player still shows their name on old
/// scorecards. Renaming a player here is the only place a name lives, so
/// every scorecard picks the change up with nothing to sync.
class AdminPlayersScreen extends StatefulWidget {
  final String teamId;

  const AdminPlayersScreen({super.key, required this.teamId});

  @override
  State<AdminPlayersScreen> createState() => _AdminPlayersScreenState();
}

class _AdminPlayersScreenState extends State<AdminPlayersScreen> {
  final _firestoreService = FirestoreService();
  late final _teamStream = _firestoreService.watchTeam(widget.teamId);

  Future<void> _save(List<Player> players) async {
    try {
      await _firestoreService.updateTeamPlayers(widget.teamId, players);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _say(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pasteNames(Team team) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add players'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Paste or type one name per line. Numbers and bullets are ignored.'),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 5,
                maxLines: 10,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(hintText: 'Ravi\nSam\nAnil'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (text == null) return;
    final parsed = parsePlayerNames(text, existing: team.players.map((p) => p.name));
    if (parsed.names.isEmpty) {
      _say(parsed.duplicates.isEmpty
          ? 'No names found.'
          : 'Those names are already on the team.');
      return;
    }
    await _save([
      ...team.players,
      for (final n in parsed.names) Player(id: Player.newId(), name: n),
    ]);
    _say('Added ${parsed.names.length}'
        '${parsed.duplicates.isEmpty ? '' : ' (skipped ${parsed.duplicates.length} already on the team)'}.');
  }

  Future<void> _editPlayer(Team team, Player player) async {
    final controller = TextEditingController(text: player.name);
    PlayerRole? role = player.role;
    final result = await showDialog<({String name, PlayerRole? role})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Edit player'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: AppSpacing.md),
              const Text('Role (optional)'),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (final r in PlayerRole.values)
                    ChoiceChip(
                      label: Text(r.label),
                      selected: role == r,
                      onSelected: (on) => setLocal(() => role = on ? r : null),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, (name: controller.text.trim(), role: role)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.name.isEmpty) return;
    final duplicate = team.players.any(
      (p) => p.id != player.id && p.name.toLowerCase() == result.name.toLowerCase(),
    );
    if (duplicate) {
      _say('Another player is already called "${result.name}".');
      return;
    }
    await _save([
      for (final p in team.players)
        if (p.id == player.id)
          p.copyWith(name: result.name, role: result.role, clearRole: result.role == null)
        else
          p,
    ]);
  }

  Future<void> _toggleActive(Team team, Player player, bool active) => _save([
        for (final p in team.players) p.id == player.id ? p.copyWith(active: active) : p,
      ]);

  Future<void> _reorder(Team team, int oldIndex, int newIndex) {
    // onReorderItem already accounts for the removed item.
    final players = [...team.players];
    players.insert(newIndex, players.removeAt(oldIndex));
    return _save(players);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Team?>(
      stream: _teamStream,
      builder: (context, snapshot) {
        final team = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(team?.name ?? 'Players'),
            actions: [
              if (team != null)
                IconButton(
                  icon: const Icon(Icons.playlist_add),
                  tooltip: 'Add players',
                  onPressed: () => _pasteNames(team),
                ),
            ],
          ),
          floatingActionButton: team == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _pasteNames(team),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add players'),
                ),
          body: Builder(builder: (context) {
            if (!snapshot.hasData) {
              return snapshot.connectionState == ConnectionState.active
                  ? const Center(child: Text('This team no longer exists.'))
                  : const ShimmerList(itemHeight: 56);
            }
            final t = team!;
            if (t.players.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text('No players yet — tap "Add players" and paste the squad, one name per line.'),
                ),
              );
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                  child: Text(
                    '${t.activePlayers.length} active of ${t.players.length}. Players are never deleted: '
                    'switch one off to hide them from new line-ups while old scorecards keep their name. '
                    'Drag to re-order.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    itemCount: t.players.length,
                    onReorderItem: (a, b) => _reorder(t, a, b),
                    itemBuilder: (context, i) {
                      final p = t.players[i];
                      return Padding(
                        key: ValueKey(p.id),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: ListTile(
                            title: Text(
                              p.name,
                              style: p.active
                                  ? null
                                  : TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                            ),
                            subtitle: Text([
                              if (p.role != null) p.role!.label,
                              if (!p.active) 'Switched off',
                            ].join(' · ')),
                            onTap: () => _editPlayer(t, p),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(value: p.active, onChanged: (v) => _toggleActive(t, p, v)),
                                const SizedBox(width: 28), // room for the drag handle
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 72), // keep the last row clear of the FAB
              ],
            );
          }),
        );
      },
    );
  }
}
