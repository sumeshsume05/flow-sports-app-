import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/cricket/cricket_rules.dart';
import '../../core/cricket/cricket_toss.dart';
import '../../core/cricket/rules_summary.dart';
import '../../core/cricket/tournament_plan.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../models/match.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../services/firestore_service.dart';
import '../../widgets/cricket_rules_form.dart';

/// Admin page for one cricket match. This phase covers match *setup* — the
/// rules this match will use, who is playing for each side, the toss, and the
/// schedule/venue. Live scoring is added on top of this screen next.
class AdminCricketMatchScreen extends StatefulWidget {
  final String matchId;

  const AdminCricketMatchScreen({super.key, required this.matchId});

  @override
  State<AdminCricketMatchScreen> createState() => _AdminCricketMatchScreenState();
}

class _AdminCricketMatchScreenState extends State<AdminCricketMatchScreen> {
  final _firestoreService = FirestoreService();
  late final _matchStream = _firestoreService.watchMatch(widget.matchId);
  final _venueController = TextEditingController();

  Stream<Team?>? _teamAStream;
  Stream<Team?>? _teamBStream;
  CricketRules? _defaultRules;

  // Working copy of the setup, initialised once from the saved match.
  CricketRules? _rules;
  Set<String>? _selectedA;
  Set<String>? _selectedB;
  CricketToss? _toss;
  bool _initialised = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _firestoreService.watchCricketRules().first.then((r) {
      if (mounted) setState(() => _defaultRules = r);
    });
  }

  @override
  void dispose() {
    _venueController.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Saved lineup if there is one; otherwise the first [limit] active players
  /// so the common case (everyone turns up) is a single tap on Save.
  Set<String> _initialSelection(List<String> saved, Team team, int limit) {
    final active = team.activePlayers.map((p) => p.id).toSet();
    if (saved.isNotEmpty) return saved.where(active.contains).toSet();
    return team.activePlayers.take(limit).map((p) => p.id).toSet();
  }

  Future<void> _editRules() async {
    var draft = _rules!;
    final picked = await showModalBottomSheet<CricketRules>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                children: [
                  Text('Rules for this match', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Only this match changes — the tournament default stays as it is.',
                      style: Theme.of(context).textTheme.bodySmall),
                  CricketRulesForm(initial: draft, onChanged: (r) => draft = r),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, draft),
                    child: const Text('Use these rules'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _rules = picked);
  }

  Future<void> _save(Match match, Team? teamA, Team? teamB) async {
    final rules = _rules!;
    List<String> ordered(Team? t, Set<String>? sel) =>
        t == null || sel == null ? const [] : [for (final p in t.players) if (sel.contains(p.id)) p.id];
    setState(() => _saving = true);
    try {
      await _firestoreService.saveCricketSetup(
        match.id,
        rules: rules,
        lineupA: ordered(teamA, _selectedA),
        lineupB: ordered(teamB, _selectedB),
        toss: _toss,
      );
      _say('Match setup saved.');
    } catch (e) {
      _say('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickSchedule(Match match) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: match.scheduledAt ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(match.scheduledAt ?? now),
    );
    if (time == null) return;
    try {
      await _firestoreService.setMatchSchedule(
          widget.matchId, DateTime(date.year, date.month, date.day, time.hour, time.minute));
    } catch (e) {
      _say('$e');
    }
  }

  Future<void> _saveVenue() async {
    final v = _venueController.text.trim();
    try {
      await _firestoreService.updateMatch(widget.matchId, {'venue': v.isEmpty ? null : v});
      _say('Venue saved.');
    } catch (e) {
      _say('$e');
    }
  }

  static String? _withName(String team, String? warning) => warning == null ? null : '$team: $warning';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Match?>(
      stream: _matchStream,
      builder: (context, snapshot) {
        final match = snapshot.data;
        if (match == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Cricket match')),
            body: Center(
              child: snapshot.connectionState == ConnectionState.active
                  ? const Text('This match no longer exists.')
                  : const CircularProgressIndicator(),
            ),
          );
        }
        _teamAStream ??= match.teamA.teamId == null ? null : _firestoreService.watchTeam(match.teamA.teamId!);
        _teamBStream ??= match.teamB.teamId == null ? null : _firestoreService.watchTeam(match.teamB.teamId!);

        if (!_initialised && _defaultRules != null) {
          _initialised = true;
          _rules = match.rules ?? _defaultRules;
          _toss = match.toss;
          _venueController.text = match.venue ?? '';
        }

        return StreamBuilder<Team?>(
          stream: _teamAStream,
          builder: (context, aSnap) => StreamBuilder<Team?>(
            stream: _teamBStream,
            builder: (context, bSnap) => _buildPage(context, match, aSnap.data, bSnap.data),
          ),
        );
      },
    );
  }

  Widget _buildPage(BuildContext context, Match match, Team? teamA, Team? teamB) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rules = _rules;

    if (rules == null) {
      return Scaffold(
        appBar: AppBar(title: Text(match.label)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (teamA != null) _selectedA ??= _initialSelection(match.lineupA, teamA, rules.squadSize);
    if (teamB != null) _selectedB ??= _initialSelection(match.lineupB, teamB, rules.squadSize);

    final nameA = match.teamA.name ?? 'Team A';
    final nameB = match.teamB.name ?? 'Team B';
    final problems = [
      if (teamA != null && _selectedA != null)
        ...squadProblems(selectedCount: _selectedA!.length, rules: rules, teamName: nameA),
      if (teamB != null && _selectedB != null)
        ...squadProblems(selectedCount: _selectedB!.length, rules: rules, teamName: nameB),
    ];
    // Heads-up only — never blocks saving.
    final warnings = <String>[
      if (teamA != null && teamB != null && _selectedA != null && _selectedB != null &&
          _selectedA!.length >= 2 && _selectedB!.length >= 2)
        ?unequalSquadsWarning(
          nameA: nameA,
          countA: _selectedA!.length,
          nameB: nameB,
          countB: _selectedB!.length,
        ),
      if (teamA != null && _selectedA != null && _selectedA!.length >= 2)
        ?_withName(nameA, bowlerSupplyWarning(squadCount: _selectedA!.length, rules: rules)),
      if (teamB != null && _selectedB != null && _selectedB!.length >= 2)
        ?_withName(nameB, bowlerSupplyWarning(squadCount: _selectedB!.length, rules: rules)),
    ];
    final teamsKnown = teamA != null && teamB != null;
    final canSave = teamsKnown && problems.isEmpty && !_saving;
    final saved = match.rules != null && match.toss != null && match.lineupA.isNotEmpty && match.lineupB.isNotEmpty;

    Widget card(String title, List<Widget> children) => Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                ...children,
              ],
            ),
          ),
        );

    Widget squad(String title, Team? team, Set<String>? selected, void Function(Set<String>) onChange) {
      if (team == null) {
        return Text('$title: team not decided yet.', style: textTheme.bodySmall);
      }
      final players = team.activePlayers;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: textTheme.titleSmall)),
              Text('${selected?.length ?? 0} of ${rules.squadSize}', style: textTheme.bodySmall),
            ],
          ),
          if (players.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  const Expanded(child: Text('No players on this team yet.')),
                  TextButton(
                    onPressed: () => context.push('/admin/teams/${team.id}/players'),
                    child: const Text('Add players'),
                  ),
                ],
              ),
            )
          else
            for (final Player p in players)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(p.name),
                subtitle: p.role == null ? null : Text(p.role!.label),
                value: selected?.contains(p.id) ?? false,
                onChanged: (on) {
                  final next = {...?selected};
                  on == true ? next.add(p.id) : next.remove(p.id);
                  onChange(next);
                },
              ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(match.label)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text('$nameA  vs  $nameB', style: textTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          if (match.status != MatchStatus.upcoming)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warningAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Text('This match has already started — changing rules or squads now '
                  'can change its scorecard.'),
            ),
          card('Rules', [
            Text(rulesSummary(rules), style: textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune),
                  label: const Text('Change for this match'),
                  onPressed: _editRules,
                ),
                if (_defaultRules != null)
                  TextButton(
                    onPressed: () => setState(() => _rules = _defaultRules),
                    child: const Text('Use tournament default'),
                  ),
              ],
            ),
          ]),
          card('Playing squads', [
            if (!teamsKnown)
              Text('Both teams must be decided before you can pick squads.', style: textTheme.bodySmall),
            squad(nameA, teamA, _selectedA, (s) => setState(() => _selectedA = s)),
            const SizedBox(height: AppSpacing.md),
            squad(nameB, teamB, _selectedB, (s) => setState(() => _selectedB = s)),
            for (final p in problems)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(p, style: textTheme.bodySmall?.copyWith(color: scheme.error)),
              ),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text('⚠ $w', style: textTheme.bodySmall?.copyWith(color: AppColors.warningAmber)),
              ),
          ]),
          card('Toss', [
            Text('Toss won by', style: textTheme.bodySmall),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final side in const ['A', 'B'])
                  ChoiceChip(
                    label: Text(side == 'A' ? nameA : nameB),
                    selected: _toss?.winner == side,
                    onSelected: (_) => setState(
                        () => _toss = CricketToss(winner: side, elected: _toss?.elected ?? 'bat')),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Chose to', style: textTheme.bodySmall),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final choice in const ['bat', 'bowl'])
                  ChoiceChip(
                    label: Text(choice == 'bat' ? 'Bat first' : 'Bowl first'),
                    selected: _toss?.elected == choice,
                    onSelected: _toss == null
                        ? null
                        : (_) => setState(
                            () => _toss = CricketToss(winner: _toss!.winner, elected: choice)),
                  ),
              ],
            ),
            if (_toss != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  '${_toss!.battingFirstSide == 'A' ? nameA : nameB} will bat first.',
                  style: textTheme.bodyMedium,
                ),
              ),
          ]),
          card('Schedule & venue', [
            Row(
              children: [
                Expanded(
                  child: Text(match.scheduledAt == null
                      ? 'Not scheduled'
                      : DateFormat('MMM d, y — h:mm a').format(match.scheduledAt!)),
                ),
                OutlinedButton(
                  onPressed: () => _pickSchedule(match),
                  child: Text(match.scheduledAt == null ? 'Set' : 'Change'),
                ),
                if (match.scheduledAt != null)
                  TextButton(
                    onPressed: () => _firestoreService.setMatchSchedule(widget.matchId, null),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _venueController,
              decoration: const InputDecoration(labelText: 'Ground / venue (optional)'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _saveVenue, child: const Text('Save venue')),
            ),
          ]),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: Text(_saving ? 'Saving…' : 'Save match setup'),
            onPressed: canSave ? () => _save(match, teamA, teamB) : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            saved
                ? 'Setup saved. Live ball-by-ball scoring is coming in the next update.'
                : 'Pick rules, both squads and the toss, then save.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
