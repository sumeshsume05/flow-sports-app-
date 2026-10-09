import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/cricket/cricket_rules.dart';
import '../../core/cricket/tournament_plan.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../models/team.dart';
import '../../services/firestore_service.dart';

/// Plan a category's cricket tournament: how many sections (and which team is
/// in which), how many qualify for the knockout, and how many overs each
/// stage gets — with a live match-count preview before anything is
/// generated. Saving writes each team's section and the plan; the existing
/// Generate Schedule screen then builds the league from those sections.
class CricketPlanScreen extends StatefulWidget {
  final String category;
  final String season;

  const CricketPlanScreen({super.key, required this.category, required this.season});

  @override
  State<CricketPlanScreen> createState() => _CricketPlanScreenState();
}

class _PlanData {
  final List<Team> teams;
  final CricketTournamentConfig config;
  final CricketRules defaults;
  final int existingLeagueMatches;

  const _PlanData(this.teams, this.config, this.defaults, this.existingLeagueMatches);
}

class _CricketPlanScreenState extends State<CricketPlanScreen> {
  final _firestoreService = FirestoreService();
  late final Future<_PlanData> _load = _loadData();

  CricketTournamentConfig _config = const CricketTournamentConfig();
  // Draft assignment: team id -> section letter (null = none). Only written on Save.
  final Map<String, String?> _draft = {};
  Map<String, String?> _saved = {};
  CricketTournamentConfig _savedConfig = const CricketTournamentConfig();
  List<Team> _teams = [];
  CricketRules _defaults = const CricketRules();
  int _existingLeague = 0;
  bool _initialised = false;
  bool _saving = false;

  Future<_PlanData> _loadData() async {
    final results = await Future.wait([
      _firestoreService.fetchTeams(sport: Sport.cricket, category: widget.category, season: widget.season),
      _firestoreService.watchCricketPlan(widget.category, widget.season).first,
      _firestoreService.watchCricketRules().first,
      _firestoreService.fetchMatches(
          sport: Sport.cricket, category: widget.category, season: widget.season, stage: 'league'),
    ]);
    return _PlanData(
      results[0] as List<Team>,
      results[1] as CricketTournamentConfig,
      results[2] as CricketRules,
      (results[3] as List).length,
    );
  }

  void _init(_PlanData d) {
    if (_initialised) return;
    _initialised = true;
    _teams = [...d.teams]..sort((a, b) {
        final sa = a.seed ?? 1 << 30;
        final sb = b.seed ?? 1 << 30;
        return sa != sb ? sa.compareTo(sb) : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    _defaults = d.defaults;
    _existingLeague = d.existingLeagueMatches;
    for (final t in _teams) {
      _draft[t.id] = t.section;
    }
    _saved = Map.of(_draft);
    // What the teams actually carry wins over the stored count.
    final letters = _teams.map((t) => t.section).whereType<String>().toSet();
    var sections = d.config.sections;
    if (letters.isNotEmpty) {
      final highest = letters.map((l) => l.codeUnitAt(0) - 0x41 + 1).reduce((a, b) => a > b ? a : b);
      sections = highest < 2 ? 2 : highest;
    } else if (sections > 1) {
      sections = 1;
    }
    _config = d.config.copyWith(sections: sections);
    _normalise();
    _savedConfig = _config;
  }

  /// Smallest/largest sensible qualifier count for the current layout.
  (int, int) get _qualifiersRange {
    if (_config.sectioned) {
      final sizes = _sectionSizes;
      final smallest = sizes.isEmpty ? 1 : sizes.reduce((a, b) => a < b ? a : b);
      return (1, smallest.clamp(1, 8));
    }
    return (2, _teams.length.clamp(2, 8));
  }

  /// Keeps qualifiers and wildcards inside what the current sections allow, so
  /// what the steppers show is always what gets saved.
  void _normalise() {
    final (lo, hi) = _qualifiersRange;
    _config = _config.copyWith(
      qualifiers: _config.qualifiers.clamp(lo, hi),
      wildcards: _config.sectioned ? _config.wildcards.clamp(0, (_config.sections - 1).clamp(0, 7)) : 0,
    );
  }

  bool get _dirty =>
      _config.toMap().toString() != _savedConfig.toMap().toString() ||
      _draft.toString() != _saved.toString();

  void _say(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- sections --------------------------------------------------------

  void _setSectioned(bool on) {
    setState(() {
      if (on) {
        final k = _config.sections > 1 ? _config.sections : 2;
        _config = _config.copyWith(
          sections: k,
          qualifiers: _config.qualifiers > 2 ? 2 : _config.qualifiers,
        );
        _draft
          ..clear()
          ..addAll(autoBalanceSections([for (final t in _teams) t.id], k));
      } else {
        _config = _config.copyWith(sections: 1, wildcards: 0, qualifiers: 4);
        for (final t in _teams) {
          _draft[t.id] = null;
        }
      }
      _normalise();
    });
  }

  int get _maxSectionCount {
    final cap = _teams.length ~/ 2;
    return cap.clamp(2, maxSections);
  }

  void _setSectionCount(int k) {
    setState(() {
      _config = _config.copyWith(sections: k);
      for (final t in _teams) {
        final l = _draft[t.id];
        if (l != null && l.codeUnitAt(0) - 0x41 >= k) _draft[t.id] = null;
      }
      _normalise();
    });
  }

  void _autoBalance() {
    setState(() {
      _draft
        ..clear()
        ..addAll(autoBalanceSections([for (final t in _teams) t.id], _config.sections));
      _normalise();
    });
  }

  Future<void> _moveTeam(Team team) async {
    final options = ['None', for (var i = 0; i < _config.sections; i++) sectionLetter(i)];
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Section for ${team.name}'),
        children: [
          for (final o in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, o),
              child: Row(
                children: [
                  if ((_draft[team.id] ?? 'None') == o)
                    const Padding(padding: EdgeInsets.only(right: AppSpacing.sm), child: Icon(Icons.check, size: 18)),
                  Text(o == 'None' ? 'No section' : 'Section $o'),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      _draft[team.id] = picked == 'None' ? null : picked;
      _normalise();
    });
  }

  // ---- derived ---------------------------------------------------------

  List<int> get _sectionSizes => [
        for (var i = 0; i < _config.sections; i++)
          _teams.where((t) => _draft[t.id] == sectionLetter(i)).length,
      ];

  int get _unassigned => _teams.where((t) => _draft[t.id] == null).length;

  TournamentPreview get _preview => previewTournament(
        teamCount: _teams.length,
        sectionSizes: _sectionSizes,
        unassigned: _config.sectioned ? _unassigned : 0,
        config: _config,
        defaultOvers: _defaults.overs,
      );

  // ---- save ------------------------------------------------------------

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final changed = <String, String?>{
        for (final t in _teams)
          if (_draft[t.id] != _saved[t.id]) t.id: _draft[t.id],
      };
      // A match remembers its league section, so moving teams between sections
      // once the schedule exists would leave their matches in the old section's
      // table. Refuse (nothing is saved) and say how to proceed.
      if (changed.isNotEmpty && _existingLeague > 0) {
        _say('League matches already exist ($_existingLeague), so sections can\'t change — each match '
            'belongs to a section. Delete the league matches in Admin > Matches first if you really '
            'need to re-arrange.');
        return;
      }
      if (changed.isNotEmpty) await _firestoreService.saveTeamSections(changed);
      await _firestoreService.saveCricketPlan(widget.category, widget.season, _config);
      if (!mounted) return;
      setState(() {
        _saved = Map.of(_draft);
        _savedConfig = _config;
      });
      _say('Plan saved.');
    } catch (e) {
      _say('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- UI --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${categoryLabel(widget.category)} Cricket — Plan')),
      body: FutureBuilder<_PlanData>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          _init(snapshot.data!);
          return _buildBody(context);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final preview = _preview;
    final sectioned = _config.sectioned;

    Widget card(String title, List<Widget> children, {String? help}) => Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleMedium),
                if (help != null) ...[
                  const SizedBox(height: 2),
                  Text(help, style: textTheme.bodySmall),
                ],
                const SizedBox(height: AppSpacing.sm),
                ...children,
              ],
            ),
          ),
        );

    final (qualifiersMin, qualifiersMax) = _qualifiersRange;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('${_teams.length} teams in ${categoryLabel(widget.category)} Cricket.', style: textTheme.titleMedium),
        if (_teams.length < 2)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text('Add at least 2 teams first (Admin > Teams).', style: textTheme.bodySmall),
          ),
        if (_existingLeague > 0)
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.warningAmber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text('$_existingLeague league matches already exist. Changing sections here does not '
                'change them, and the sections can no longer be changed — delete them in Admin > Matches first '
                'if you want to re-arrange or regenerate.'),
          ),
        const SizedBox(height: AppSpacing.md),
        card(
          'League',
          [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('One league')),
                ButtonSegment(value: true, label: Text('Sections')),
              ],
              selected: {sectioned},
              onSelectionChanged: (s) => _setSectioned(s.first),
            ),
            if (sectioned) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Expanded(child: Text('Number of sections')),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _config.sections > 2 ? () => _setSectionCount(_config.sections - 1) : null,
                  ),
                  Text('${_config.sections}', style: textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _config.sections < _maxSectionCount
                        ? () => _setSectionCount(_config.sections + 1)
                        : null,
                  ),
                ],
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Auto-balance teams'),
                onPressed: _teams.isEmpty ? null : _autoBalance,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Spreads teams evenly (A, B, C, then back C, B, A…) using team seeds if set, otherwise '
                  'alphabetical. Tap any team below to move it by hand.',
                  style: textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (var i = 0; i < _config.sections; i++) _sectionBox(i),
              if (_unassigned > 0) _unassignedBox(),
            ],
          ],
          help: sectioned
              ? 'Teams only play others in their own section.'
              : 'Everyone plays everyone once.',
        ),
        card(
          'Knockout',
          [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Knockout after the league'),
              value: _config.knockout,
              onChanged: (v) => setState(() => _config = _config.copyWith(knockout: v)),
            ),
            if (_config.knockout) ...[
              _Stepper(
                label: sectioned ? 'Qualifiers from each section' : 'Teams that qualify',
                value: _config.qualifiers,
                min: qualifiersMin,
                max: qualifiersMax,
                onChanged: (v) => setState(() => _config = _config.copyWith(qualifiers: v)),
              ),
              if (sectioned)
                _Stepper(
                  label: 'Wildcards (best runners-up)',
                  value: _config.wildcards,
                  min: 0,
                  max: (_config.sections - 1).clamp(0, 7),
                  onChanged: (v) => setState(() => _config = _config.copyWith(wildcards: v)),
                ),
              const SizedBox(height: AppSpacing.xs),
              Text('Final', style: textTheme.bodySmall),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Single match')),
                  ButtonSegment(value: true, label: Text('Best of 3')),
                ],
                selected: {_config.bestOfThreeFinal},
                onSelectionChanged: (s) =>
                    setState(() => _config = _config.copyWith(bestOfThreeFinal: s.first)),
              ),
              if (sectioned && preview.qualifiers >= 2)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'Seeding: each section\'s winner is ranked first, then runners-up, and so on, by '
                    'points then net run rate. Teams from the same section are kept apart in the first '
                    'knockout round where possible.',
                    style: textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
        card(
          'Overs per stage',
          [
            Text('Default: ${_defaults.overs} overs (change it in Cricket rules).', style: textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            for (final stage in preview.overs.keys) _stageRow(stage, preview.overs[stage]!),
          ],
          help: 'Each match takes its overs when it is generated; after that only its own setup page changes it.',
        ),
        card('Preview', _previewLines(context, preview)),
        FilledButton.icon(
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving…' : 'Save plan'),
          onPressed: _dirty && !_saving ? _save : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Generate league schedule'),
          onPressed: _dirty || !preview.canGenerate || _existingLeague > 0
              ? null
              : () => context.push('/admin/schedule/generate?sport=${Sport.cricket}&category=${widget.category}'),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _dirty
                ? 'Save the plan first — the schedule is built from the saved sections.'
                : !preview.canGenerate
                    ? 'Fix the problems in the preview to generate.'
                    : _existingLeague > 0
                        ? 'League matches already exist.'
                        : 'Ready.',
            style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _sectionBox(int index) {
    final letter = sectionLetter(index);
    final members = _teams.where((t) => _draft[t.id] == letter).toList();
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Section $letter · ${members.length} teams · ${roundRobinMatches(members.length)} matches',
              style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          if (members.isEmpty)
            Text('No teams yet.', style: textTheme.bodySmall)
          else
            Wrap(
              spacing: AppSpacing.xs,
              children: [for (final t in members) ActionChip(label: Text(t.name), onPressed: () => _moveTeam(t))],
            ),
        ],
      ),
    );
  }

  Widget _unassignedBox() {
    final members = _teams.where((t) => _draft[t.id] == null).toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warningAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No section yet · ${members.length}', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: [for (final t in members) ActionChip(label: Text(t.name), onPressed: () => _moveTeam(t))],
          ),
        ],
      ),
    );
  }

  Widget _stageRow(CricketStage stage, int overs) {
    final overridden = _config.stageOvers.containsKey(stage);
    final rules = rulesForStage(_defaults, _config, stage);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(stage.label),
              Text(
                rules.maxOversPerBowler == null ? 'No bowler limit' : 'Max ${rules.maxOversPerBowler} per bowler',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (overridden)
          TextButton(
            onPressed: () => setState(() {
              final next = {..._config.stageOvers}..remove(stage);
              _config = _config.copyWith(stageOvers: next);
            }),
            child: const Text('Default'),
          ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: overs > 1 ? () => _setStageOvers(stage, overs - 1) : null,
        ),
        SizedBox(
          width: 28,
          child: Text('$overs',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: overridden ? FontWeight.w800 : FontWeight.w400,
                  )),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: overs < 50 ? () => _setStageOvers(stage, overs + 1) : null,
        ),
      ],
    );
  }

  void _setStageOvers(CricketStage stage, int overs) {
    setState(() {
      final next = {..._config.stageOvers};
      if (overs == _defaults.overs) {
        next.remove(stage);
      } else {
        next[stage] = overs;
      }
      _config = _config.copyWith(stageOvers: next);
    });
  }

  List<Widget> _previewLines(BuildContext context, TournamentPreview p) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    String range(int a, int b) => a == b ? '$a' : '$a–$b';
    Widget line(String text, {Color? color, FontWeight? weight}) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(text, style: textTheme.bodyMedium?.copyWith(color: color, fontWeight: weight)),
        );
    return [
      line('Teams: ${p.teamCount}${_config.sectioned ? ' · Sections: ${_config.sections}' : ''}'),
      if (_config.sectioned)
        for (final s in p.sections)
          line('Section ${s.label}: ${s.teams} teams → ${s.leagueMatches} league matches'),
      line('League matches: ${p.leagueMatches}', weight: FontWeight.w600),
      if (_config.knockout && p.qualifiers >= 2) ...[
        line('Qualifying teams: ${p.qualifiers}'
            '${_config.sectioned ? ' (${_config.qualifiers} per section${_config.wildcards > 0 ? ' + ${_config.wildcards} wildcard' : ''})' : ''}'),
        line('Knockout matches: ${range(p.knockoutMin, p.knockoutMax)}'
            '${_config.bestOfThreeFinal ? ' (Best-of-3 Final)' : ''}'),
      ] else
        line('No knockout stage.'),
      line('Total matches: ${range(p.totalMin, p.totalMax)}', weight: FontWeight.w800),
      line('Overs — ${p.overs.entries.map((e) => '${e.key.label} ${e.value}').join(' · ')}'),
      for (final b in p.blockers) line('⛔ $b', color: scheme.error),
      for (final w in p.warnings) line('⚠ $w', color: AppColors.warningAmber),
    ];
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Text('$value', style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}
