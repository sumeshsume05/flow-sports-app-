import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/utils/match_export.dart';
import '../../models/match.dart';
import '../../services/firestore_service.dart';
import '../../state/announcement_state.dart';
import '../../state/auth_state.dart';
import '../../state/chat_settings_state.dart';
import '../../state/season_state.dart';
import '../../models/team.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _firestoreService = FirestoreService();
  bool _seeding = false;
  String? _seedMessage;
  String? _busySport;

  bool _loadingUsage = false;
  int? _installCount;
  int? _activeCount;
  String? _usageError;

  @override
  void initState() {
    super.initState();
    _refreshUsageStats();
  }

  Future<void> _refreshUsageStats() async {
    setState(() {
      _loadingUsage = true;
      _usageError = null;
    });
    try {
      final installs = await _firestoreService.fetchInstallCount();
      final active = await _firestoreService.fetchActiveCount();
      if (mounted) {
        setState(() {
          _installCount = installs;
          _activeCount = active;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _usageError = '$e');
    } finally {
      if (mounted) setState(() => _loadingUsage = false);
    }
  }

  Future<void> _seedInitialData(String season) async {
    setState(() {
      _seeding = true;
      _seedMessage = null;
    });
    try {
      final boysExisting = await _firestoreService.fetchTeams(
          sport: Sport.badminton, category: Category.boys, season: season);
      final girlsExisting = await _firestoreService.fetchTeams(
          sport: Sport.badminton, category: Category.girls, season: season);
      if (boysExisting.isNotEmpty || girlsExisting.isNotEmpty) {
        setState(() => _seedMessage = 'Teams already exist — skipped to avoid duplicates.');
        return;
      }

      const boysPairs = [
        'Stephin & Karthick',
        'Subramaniyam & Velayutham',
        'Naveen & David',
        'Bino & Akash',
        'Udhay & Sakthi',
        'Siva Gokul & Ramji',
        'Rahul Dev & Sivanesh',
        'Varun & Steve',
      ];
      const girlsPairs = [
        'Devi & Shiny',
        'Christina & Nathika',
        'Elain & Rajasree',
        'Jisha & Sowmiya',
        'Rebisha & Shalini',
        'Renosha & Karthika',
      ];

      for (final name in boysPairs) {
        await _firestoreService.addTeam(Team(
          id: '',
          sport: Sport.badminton,
          category: Category.boys,
          name: name,
          season: season,
        ));
      }
      for (final name in girlsPairs) {
        await _firestoreService.addTeam(Team(
          id: '',
          sport: Sport.badminton,
          category: Category.girls,
          name: name,
          season: season,
        ));
      }

      setState(() => _seedMessage =
          'Seeded ${boysPairs.length} boys + ${girlsPairs.length} girls teams. '
          'Now use "Generate Schedule" on each category to create league matches.');
    } catch (e) {
      setState(() => _seedMessage = 'Seeding failed: $e');
    } finally {
      setState(() => _seeding = false);
    }
  }

  Future<void> _downloadCsv(String sport, String season) async {
    setState(() => _busySport = sport);
    try {
      final matches = <Match>[];
      for (final category in Category.all) {
        matches.addAll(
          await _firestoreService.fetchMatches(sport: sport, category: category, season: season),
        );
      }
      final csv = buildMatchesCsv(matches);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${sport}_matches.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path)], text: '$sport matches');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not export: $e')));
      }
    } finally {
      if (mounted) setState(() => _busySport = null);
    }
  }

  Future<void> _confirmReset(String sport, String season) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset $sport?'),
        content: const Text(
          'Deletes every match and result for this sport this season — league, '
          'knockout and any tie-breakers. Teams are kept. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busySport = sport);
    try {
      await _firestoreService.resetSportMatches(sport: sport, season: season);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$sport matches reset — teams kept.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busySport = null);
    }
  }

  Future<void> _setChatEnabled(bool enabled) async {
    try {
      await _firestoreService.setChatEnabled(enabled);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _showAnnouncementDialog(String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Home Screen Announcement'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'e.g. Matches start at 9am tomorrow, Court 2',
          ),
          maxLines: 4,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (result != true) return;
    try {
      await _firestoreService.setAnnouncement(controller.text.trim());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final seasonState = context.watch<SeasonState>();
    final season = seasonState.activeSeasonId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.event_outlined),
            tooltip: 'Seasons',
            onPressed: () => context.push('/admin/seasons'),
          ),
          IconButton(
            icon: const Icon(Icons.visibility_outlined),
            tooltip: 'View live app',
            // Deliberately context.go, not signOut — lets the admin check
            // what viewers see without ending their admin session. The
            // Home screen's own admin icon (Icons.admin_panel_settings_outlined)
            // routes back to /admin and, since still signed in, lands
            // straight on this dashboard with no login prompt.
            onPressed: () => context.go('/'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await context.read<AuthState>().signOut();
              if (context.mounted) context.go('/');
            },
          ),
        ],
      ),
      body: season == null
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_outlined, size: 40, color: scheme.outline),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'No season set up yet. Create one to start managing teams and matches.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Set up a season'),
                    onPressed: () => context.push('/admin/seasons'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.forum_outlined),
                    title: const Text('Chat'),
                    subtitle: Text(
                      context.watch<ChatSettingsState>().chatEnabled
                          ? 'Open — anyone can post'
                          : 'Closed — hidden from every viewer, no new messages accepted',
                    ),
                    value: context.watch<ChatSettingsState>().chatEnabled,
                    onChanged: _setChatEnabled,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Builder(builder: (context) {
                  final announcement = context.watch<AnnouncementState>().text;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.campaign_outlined),
                      title: const Text('Home Screen Announcement'),
                      subtitle: Text(
                        announcement.isEmpty ? 'None set' : announcement,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: TextButton(
                        onPressed: () => _showAnnouncementDialog(announcement),
                        child: Text(announcement.isEmpty ? 'Set' : 'Edit'),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.insights_outlined),
                            const SizedBox(width: AppSpacing.sm),
                            Text('App Usage', style: textTheme.titleMedium),
                            const Spacer(),
                            IconButton(
                              icon: _loadingUsage
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.refresh),
                              onPressed: _loadingUsage ? null : _refreshUsageStats,
                              tooltip: 'Refresh',
                            ),
                          ],
                        ),
                        if (_usageError != null)
                          Text(_usageError!, style: TextStyle(color: scheme.error))
                        else ...[
                          Text(
                            '${_installCount ?? "—"} installs (all-time) '
                            '· ${_activeCount ?? "—"} active in the last 5 minutes',
                            style: textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Installs = unique devices that have ever opened the app at least '
                            "once (this can only grow — there's no way to detect an uninstall). "
                            'Includes your own admin/test devices.',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final sport in Sport.all) ...[
                  Text(sport[0].toUpperCase() + sport.substring(1), style: textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  for (final category in Category.all) ...[
                    Text(categoryLabel(category), style: textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    _CategoryActions(category: category),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.download_outlined),
                        label: Text(_busySport == sport ? 'Preparing…' : 'Download CSV'),
                        onPressed: _busySport == sport ? null : () => _downloadCsv(sport, season),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.liveRed.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.liveRed.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Danger zone', style: textTheme.labelLarge?.copyWith(color: AppColors.liveRed)),
                        const SizedBox(height: 2),
                        Text(
                          'For re-testing the live flow before the real event.',
                          style: textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.liveRed),
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: Text(_busySport == sport ? 'Working…' : 'Reset $sport Data'),
                          onPressed: _busySport == sport ? null : () => _confirmReset(sport, season),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: AppSpacing.xl * 1.5),
                ],
                Text('One-time setup', style: textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Seeds the 8 boys + 6 girls team names for this season. Safe to tap only '
                  'once — it checks for existing teams first and does nothing if they '
                  'already exist.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(_seeding ? 'Seeding...' : 'Seed Initial Data'),
                  onPressed: _seeding ? null : () => _seedInitialData(season),
                ),
                if (_seedMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(_seedMessage!),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _CategoryActions extends StatelessWidget {
  final String category;

  const _CategoryActions({required this.category});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.people_outline),
          label: const Text('Teams'),
          onPressed: () => context.push('/admin/teams?category=$category'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.list_alt),
          label: const Text('Matches'),
          onPressed: () => context.push('/admin/matches?category=$category'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Generate Schedule'),
          onPressed: () => context.push('/admin/schedule/generate?category=$category'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.account_tree_outlined),
          label: const Text('Generate Bracket'),
          onPressed: () => context.push('/admin/bracket/generate?category=$category'),
        ),
      ],
    );
  }
}
