import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/sports.dart';
import '../../core/test_lab/test_scenarios.dart';
import '../../services/test_lab_service.dart';
import '../../state/connectivity_state.dart';
import '../../state/season_state.dart';

/// Admin Test Lab: ready-made test teams (and cricket players) for every
/// sport, kept in a separate "Test" category that viewers never see, with a
/// one-tap reset so a test can be repeated from a clean slate. Test data runs
/// through exactly the same screens and logic as real data.
class AdminTestLabScreen extends StatelessWidget {
  /// Tests pass one backed by a fake Firestore.
  final TestLabService? service;

  const AdminTestLabScreen({super.key, this.service});

  @override
  Widget build(BuildContext context) {
    final season = context.watch<SeasonState>().activeSeasonId;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Test Lab')),
      body: season == null
          ? const Center(child: Text('Set up a season first.'))
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.warningAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Safe to experiment', style: textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Test data lives in its own "Test" category. Viewers never see it, it is not in the '
                        'CSV export, and your real Boys and Girls teams and matches are never touched. '
                        'Create test teams, try anything, then Reset and start again.',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final sport in Sport.all) _SportLab(sport: sport, season: season, service: service),
              ],
            ),
    );
  }
}

class _SportLab extends StatefulWidget {
  final String sport;
  final String season;
  final TestLabService? service;

  const _SportLab({required this.sport, required this.season, this.service});

  @override
  State<_SportLab> createState() => _SportLabState();
}

class _SportLabState extends State<_SportLab> {
  late final _service = widget.service ?? TestLabService();
  late final _scenarios = testScenariosFor(widget.sport);
  late TestScenario _scenario = _scenarios.first;
  late Future<({int teams, int matches, bool fromCache})> _counts = _loadCounts();
  bool _busy = false;
  bool? _wasOffline;
  String? _message;

  bool get _offline => Provider.of<ConnectivityState?>(context, listen: false)?.isOffline ?? false;

  Future<({int teams, int matches, bool fromCache})> _loadCounts() =>
      _service.counts(widget.sport, widget.season, offline: _offline);

  void _refresh() {
    // Start the query first; setState's callback must not be async or return a Future.
    final next = _loadCounts();
    setState(() {
      _counts = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // When the network comes back (or goes away) re-read the numbers, so the
    // card never keeps showing a saved copy after the phone is online again.
    final offline = context.watch<ConnectivityState?>()?.isOffline ?? false;
    if (_wasOffline != null && _wasOffline != offline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
    _wasOffline = offline;
  }

  /// Opens another admin screen and, when the admin comes back, re-reads the
  /// counts — so e.g. generating a schedule there immediately shows the
  /// auto-play buttons here without reopening the Test Lab.
  Future<void> _open(String path) async {
    await context.push(path);
    if (mounted) _refresh();
  }

  Future<void> _run(String working, Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _message = working;
    });
    try {
      final done = await action();
      if (mounted) setState(() => _message = done);
    } catch (e) {
      if (mounted) setState(() => _message = 'Something went wrong: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
  }

  Future<bool> _confirm(String title, String body, String action, {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _create(({int teams, int matches, bool fromCache}) existing) async {
    if (existing.teams + existing.matches > 0) {
      final ok = await _confirm(
        'Replace test data?',
        'This clears the current ${sportConfig(widget.sport).label} test teams and matches '
            '(${existing.teams} teams, ${existing.matches} matches) and creates the new set. '
            'Real data is not touched.',
        'Replace',
      );
      if (!ok) return;
    }
    await _run('Creating test teams…', () async {
      final n = await _service.createScenario(widget.sport, widget.season, _scenario);
      return 'Created $n test teams. Next: Generate Schedule below.';
    });
  }

  Future<void> _reset(({int teams, int matches, bool fromCache}) existing) async {
    final ok = await _confirm(
      'Reset ${sportConfig(widget.sport).label} test data?',
      'Deletes all ${existing.teams} test teams and ${existing.matches} test matches. '
          'Your real Boys and Girls data is not touched.',
      'Reset',
      danger: true,
    );
    if (!ok) return;
    await _run('Resetting…', () async {
      await _service.reset(widget.sport, widget.season);
      return 'Test data cleared. You can create a new set.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final config = sportConfig(widget.sport);
    final q = 'sport=${widget.sport}&category=${Category.test}';

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: FutureBuilder<({int teams, int matches, bool fromCache})>(
          future: _counts,
          builder: (context, snapshot) {
            final counts = snapshot.data ?? (teams: 0, matches: 0, fromCache: false);
            final hasData = counts.teams + counts.matches > 0;
            // Changing test data (create / replace / play / reset) needs the
            // real numbers and a connection: those writes wait for the server.
            final canChange = snapshot.hasData && !counts.fromCache && !_offline;
            final locked = _busy || !canChange;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(config.icon),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(config.label, style: textTheme.titleLarge)),
                    Text(
                      snapshot.hasData
                          ? '${counts.teams} teams · ${counts.matches} matches'
                          : snapshot.hasError
                              ? '?'
                              : '…',
                      style: textTheme.bodySmall,
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: 'Refresh counts',
                      onPressed: _busy ? null : _refresh,
                    ),
                  ],
                ),
                if (snapshot.hasData && (counts.fromCache || _offline))
                  _Note(
                    icon: Icons.cloud_off_rounded,
                    text: 'You are offline — this is the copy saved on your phone. Creating, playing and '
                        'resetting test data are paused until the network is back.',
                  )
                else if (snapshot.hasError)
                  _Note(
                    icon: Icons.error_outline,
                    text: 'Could not read the test data (no saved copy yet, and no connection). '
                        'Try again when you are online.',
                  ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<TestScenario>(
                  initialValue: _scenario,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Test scenario'),
                  items: [for (final s in _scenarios) DropdownMenuItem(value: s, child: Text(s.title))],
                  onChanged: _busy ? null : (s) => setState(() => _scenario = s ?? _scenario),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: AppSpacing.sm),
                  child: Text(_scenario.description, style: textTheme.bodySmall),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.group_add_outlined),
                  label: Text(hasData ? 'Replace with this scenario' : 'Create test teams'),
                  onPressed: locked ? null : () => _create(counts),
                ),
                if (hasData) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('Work with the test tournament', style: textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (widget.sport == Sport.cricket)
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.account_tree_outlined),
                          label: const Text('Plan & sections'),
                          onPressed: () => _open('/admin/plan?$q'),
                        ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.people_outline),
                        label: const Text('Teams'),
                        onPressed: () => _open('/admin/teams?$q'),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Generate Schedule'),
                        onPressed: () => _open('/admin/schedule/generate?$q'),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.list_alt),
                        label: const Text('Matches'),
                        onPressed: () => _open('/admin/matches?$q'),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.account_tree_outlined),
                        label: const Text('Generate Bracket'),
                        onPressed: () => _open('/admin/bracket/generate?$q'),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('See it as a viewer'),
                        // go (not push): the viewer screens live in a different part of the app's
                        // navigation, and pushing into it from the admin area is a known go_router crash.
                        onPressed: () => context.go('/'),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'See it as a viewer opens Home. As admin you will see an extra "Test" card under each sport — '
                      'tap it for the viewer screens. Use the admin icon on Home to come back.',
                      style: textTheme.bodySmall,
                    ),
                  ),
                ],
                if (widget.sport == Sport.badminton && counts.matches > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('Play matches automatically', style: textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    'Skip entering scores by hand. Random = clear winners and losers. All ties = every match 21–21, '
                    'so teams stay level. Each button only plays matches that have no result yet: league first, '
                    'then tie-breakers (after you schedule them in Generate Bracket), then the knockout.',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton(
                        onPressed: locked
                            ? null
                            : () => _run('Playing league…', () async {
                                  final n = await _service.playLeague(widget.sport, widget.season,
                                      allTies: false);
                                  return n == 0
                                      ? 'Nothing to play — every league match already has a result. '
                                          'Use Reset test data to start over, or play the tie-breakers below.'
                                      : 'Played $n league matches with random scores.';
                                }),
                        child: const Text('Play league (random)'),
                      ),
                      OutlinedButton(
                        onPressed: locked
                            ? null
                            : () => _run('Playing league…', () async {
                                  final n = await _service.playLeague(widget.sport, widget.season,
                                      allTies: true);
                                  return n == 0
                                      ? 'Nothing to play — every league match already has a result.'
                                      : 'Played $n league matches, all 21–21 — every team is level, '
                                          'so the tie-breaker flow will be needed.';
                                }),
                        child: const Text('Play league (all ties)'),
                      ),
                      OutlinedButton(
                        onPressed: locked
                            ? null
                            : () => _run('Playing tie-breakers…', () async {
                                  final n = await _service.playTiebreakers(widget.sport, widget.season,
                                      allTies: false);
                                  return n == 0
                                      ? 'No tie-breaker matches are waiting. Schedule them in Generate Bracket first.'
                                      : 'Played $n tie-breaker matches with random scores. Open Generate Bracket '
                                          'again — if teams are still level it will ask for another round.';
                                }),
                        child: const Text('Play tie-breakers (random)'),
                      ),
                      OutlinedButton(
                        onPressed: locked
                            ? null
                            : () => _run('Playing tie-breakers…', () async {
                                  final n = await _service.playTiebreakers(widget.sport, widget.season,
                                      allTies: true);
                                  return n == 0
                                      ? 'No tie-breaker matches are waiting. Schedule them in Generate Bracket first.'
                                      : 'Played $n tie-breaker matches, all 21–21 — the tie stays, so '
                                          'Generate Bracket will ask for another round.';
                                }),
                        child: const Text('Play tie-breakers (all ties)'),
                      ),
                      OutlinedButton(
                        onPressed: locked
                            ? null
                            : () => _run('Playing knockout…', () async {
                                  final r = await _service.playKnockout(widget.sport, widget.season);
                                  return 'Played ${r.played} knockout match${r.played == 1 ? '' : 'es'}.'
                                      '${r.note == null ? '' : ' ${r.note}'}';
                                }),
                        child: const Text('Play knockout'),
                      ),
                    ],
                  ),
                ] else if (widget.sport == Sport.cricket && counts.matches > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('Play matches automatically', style: textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    'Plays whole matches ball by ball with the real scoring engine (squads, toss, both innings, '
                    'result) — then open any match to see its balls, edit one, or reopen it. Each button only '
                    'plays matches that have no result yet: league first, then tie-breakers, then the knockout. '
                    'To try scoring by hand instead, open a match from Matches and tap Start scoring.',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton(
                        onPressed: locked
                            ? null
                            : () => _run('Playing league…', () async {
                                  final r = await _service.playCricketStage(widget.sport, widget.season,
                                      stage: 'league');
                                  return r.played == 0 && r.note == null
                                      ? 'Nothing to play — every league match already has a result.'
                                      : 'Played ${r.played} league matches.${r.note == null ? '' : ' ${r.note}'}';
                                }),
                        child: const Text('Play league (random)'),
                      ),
                      OutlinedButton(
                        onPressed: locked
                            ? null
                            : () => _run('Playing knockout…', () async {
                                  final r = await _service.playCricketKnockout(widget.sport, widget.season);
                                  return 'Played ${r.played} knockout match${r.played == 1 ? '' : 'es'}.'
                                      '${r.note == null ? '' : ' ${r.note}'}';
                                }),
                        child: const Text('Play knockout'),
                      ),
                    ],
                  ),
                ],
                if (hasData) ...[
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.liveRed),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Reset test data'),
                    onPressed: locked ? null : () => _reset(counts),
                  ),
                ],
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        children: [
                          if (_busy)
                            const Padding(
                              padding: EdgeInsets.only(right: AppSpacing.sm),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          Expanded(child: Text(_message!)),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Note({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warningAmber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.warningAmber),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
