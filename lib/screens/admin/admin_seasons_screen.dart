import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../models/season.dart';
import '../../services/firestore_service.dart';
import '../../state/season_state.dart';

/// Lets an admin maintain one Firestore doc per tournament run — this event
/// is conducted multiple times a year, so each run gets its own dated,
/// editable "Season" instead of colliding with the previous run's data.
class AdminSeasonsScreen extends StatefulWidget {
  const AdminSeasonsScreen({super.key});

  @override
  State<AdminSeasonsScreen> createState() => _AdminSeasonsScreenState();
}

class _AdminSeasonsScreenState extends State<AdminSeasonsScreen> {
  final _firestoreService = FirestoreService();
  final _dateFormat = DateFormat('d MMM yyyy');
  String? _message;

  Future<void> _showSeasonDialog({Season? existing}) async {
    final labelController = TextEditingController(text: existing?.label ?? '');
    var date = existing?.date ?? DateTime.now();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'New Season' : 'Edit Season'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(labelText: 'e.g. March 2026 Sports Meet'),
                autofocus: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(_dateFormat.format(date)),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setDialogState(() => date = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(existing == null ? 'Create & Make Current' : 'Save'),
            ),
          ],
        ),
      ),
    );

    final label = labelController.text.trim();
    if (result != true || label.isEmpty) return;

    try {
      if (existing == null) {
        final id = _firestoreService.newSeasonId();
        await _firestoreService.createSeason(
          Season(id: id, label: label, date: date, createdAt: DateTime.now()),
        );
        await _firestoreService.setActiveSeason(id);
        setState(() => _message = 'Season created and set as current.');
      } else {
        await _firestoreService.updateSeason(existing.id, {
          'label': label,
          'date': Timestamp.fromDate(date),
        });
        setState(() => _message = 'Season updated.');
      }
    } catch (e) {
      setState(() => _message = '$e');
    }
  }

  Future<void> _confirmSetActive(Season season) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch current season?'),
        content: Text(
          'Every screen will start showing "${season.label}"\'s teams and matches '
          'instead of the current one. Nothing is deleted — you can switch back anytime.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _firestoreService.setActiveSeason(season.id);
      setState(() => _message = '"${season.label}" is now the current season.');
    } catch (e) {
      setState(() => _message = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeSeasonId = context.watch<SeasonState>().activeSeasonId;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Seasons')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSeasonDialog(),
        icon: const Icon(Icons.add),
        label: const Text('New Season'),
      ),
      body: StreamBuilder<List<Season>>(
        stream: _firestoreService.watchSeasons(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final seasons = snapshot.data!;
          if (seasons.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No seasons yet — create one to start this run\'s tournament.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Already have a "$legacySeasonId" tournament running? Create a season '
                      'labeled "$legacySeasonId" to pick it back up with all its existing data.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(_message!),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  itemCount: seasons.length,
                  itemBuilder: (context, i) {
                    final season = seasons[i];
                    final isActive = season.id == activeSeasonId;
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isActive
                              ? scheme.primary.withValues(alpha: 0.1)
                              : scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: isActive ? Border.all(color: scheme.primary) : null,
                        ),
                        child: ListTile(
                          title: Text(season.label),
                          subtitle: Text(_dateFormat.format(season.date)),
                          trailing: isActive
                              ? Chip(label: const Text('Current'), backgroundColor: scheme.primary.withValues(alpha: 0.15))
                              : TextButton(
                                  onPressed: () => _confirmSetActive(season),
                                  child: const Text('Set as current'),
                                ),
                          onTap: () => _showSeasonDialog(existing: season),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
