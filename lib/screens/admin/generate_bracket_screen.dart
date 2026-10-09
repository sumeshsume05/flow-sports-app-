import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/utils/bracket_resolver.dart';
import '../../core/utils/round_robin.dart';
import '../../core/utils/sections.dart';
import '../../core/utils/standings_calculator.dart';
import '../../models/match.dart';
import '../../models/standing_row.dart';
import '../../models/team.dart';
import '../../services/firestore_service.dart';

/// One qualification group feeding the knockout bracket: either the whole
/// category (non-sectioned — [label] is null, [qualifyCount] is whatever
/// the admin picked: 2, 3, or 4 — see [_GenerateBracketScreenState._flatQualifyCount]),
/// or one league section (sectioned — [label] is the section name, e.g.
/// 'A', [qualifyCount] fixed at 2). Mutable so the admin's manual reorder
/// (move up/down) can update it in place with setState, without a full
/// reload.
class _SectionPanel {
  final String? label;
  final String? section;
  final int qualifyCount;
  List<StandingRow> candidates;
  final TieChainResult? chain;

  _SectionPanel({
    required this.label,
    required this.section,
    required this.qualifyCount,
    required this.candidates,
    required this.chain,
  });
}

class GenerateBracketScreen extends StatefulWidget {
  final String sport;
  final String category;
  final String season;

  const GenerateBracketScreen({super.key, required this.sport, required this.category, required this.season});

  @override
  State<GenerateBracketScreen> createState() => _GenerateBracketScreenState();
}

class _GenerateBracketScreenState extends State<GenerateBracketScreen> {
  final _firestoreService = FirestoreService();
  List<_SectionPanel>? _panels;
  final Set<int> _schedulingIndexes = {};
  bool _generating = false;
  String? _message;

  /// Qualifier count for the non-sectioned (flat league table) case only —
  /// admin-chosen (2, 3, or 4), defaulting to 4 so nothing changes unless
  /// they pick differently. Irrelevant once a category is sectioned (that
  /// case stays fixed at 2 sections x 2 qualifiers each).
  int _flatQualifyCount = 4;

  /// Final format — orthogonal to qualifier count/sectioning, applies either
  /// way. Admin-chosen at generation time; baked into which Final matches
  /// get created (see bracket_resolver.dart's _finalGames).
  bool _bestOfThreeFinal = false;

  /// Existing knockout matches for this category/season, refreshed on every
  /// [_load] — used only to detect whether a best-of-3 Final has split 1-1
  /// and needs its decider (Game 3) scheduled (see [_needsFinalGame3]).
  /// Unrelated to [_panels], which drive bracket *generation*, not matches
  /// that already exist.
  List<Match> _knockoutMatches = [];
  bool _schedulingGame3 = false;

  Match? _byCode(String code) {
    for (final m in _knockoutMatches) {
      if (m.matchCode == code) return m;
    }
    return null;
  }

  bool get _needsFinalGame3 {
    final kof1 = _byCode('KOF1');
    final kof2 = _byCode('KOF2');
    if (kof1 == null || kof2 == null || _byCode('KOF3') != null) return false;
    bool decided(Match m) => m.result != null && m.result != MatchResult.tie;
    if (!decided(kof1) || !decided(kof2)) return false;
    final aWins = [kof1, kof2].where((m) => m.result == MatchResult.teamA).length;
    final bWins = [kof1, kof2].where((m) => m.result == MatchResult.teamB).length;
    return aWins == 1 && bWins == 1;
  }

  _SectionPanel _buildPanel({
    required String? label,
    required String? section,
    required int qualifyCount,
    required List<Team> teams,
    required List<Match> leagueMatches,
    required List<Match> tiebreakerMatches,
  }) {
    final standings = computeStandings(teams: teams, leagueMatches: leagueMatches);
    final rawCandidates = candidatesForTopFour(standings, cutoffCount: qualifyCount);
    final cluster = decidingTieCluster(rawCandidates, cutoffCount: qualifyCount);

    TieChainResult? chain;
    var candidates = rawCandidates;
    if (cluster != null) {
      chain = resolveTieChain(originalCluster: cluster, allTiebreakerMatches: tiebreakerMatches);
      candidates = List.of(rawCandidates);
      final startIndex = candidates.indexWhere((r) => r.teamId == cluster.first.teamId);
      for (var k = 0; k < chain.order.length; k++) {
        candidates[startIndex + k] = chain.order[k];
      }
    }
    return _SectionPanel(
      label: label,
      section: section,
      qualifyCount: qualifyCount,
      candidates: candidates,
      chain: chain,
    );
  }

  Future<void> _load() async {
    final teams = await _firestoreService.fetchTeams(
      sport: widget.sport,
      category: widget.category,
      season: widget.season,
    );
    final leagueMatches = await _firestoreService.fetchMatches(
      sport: widget.sport,
      category: widget.category,
      season: widget.season,
      stage: 'league',
    );
    final tiebreakerMatches = await _firestoreService.fetchMatches(
      sport: widget.sport,
      category: widget.category,
      season: widget.season,
      stage: 'tiebreaker',
    );
    final knockoutMatches = await _firestoreService.fetchMatches(
      sport: widget.sport,
      category: widget.category,
      season: widget.season,
      stage: 'knockout',
    );

    final withSection = teams.where((t) => t.section != null).length;
    final sectioned = withSection > 0 && withSection == teams.length;

    List<_SectionPanel> panels;
    if (!sectioned) {
      panels = [
        _buildPanel(
          label: null,
          section: null,
          qualifyCount: _flatQualifyCount,
          teams: teams,
          leagueMatches: leagueMatches,
          tiebreakerMatches: tiebreakerMatches,
        ),
      ];
    } else {
      final sections = teams.map((t) => t.section!).toSet().toList()..sort();
      panels = [
        for (final s in sections)
          _buildPanel(
            label: s,
            section: s,
            qualifyCount: 2,
            teams: teams.where((t) => t.section == s).toList(),
            leagueMatches: leagueMatchesForSection(leagueMatches, teams, s),
            tiebreakerMatches: tiebreakerMatches.where((m) => m.section == s).toList(),
          ),
      ];
    }

    if (mounted) {
      setState(() {
        _panels = panels;
        _knockoutMatches = knockoutMatches;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _setFlatQualifyCount(int n) async {
    if (_flatQualifyCount == n) return;
    setState(() {
      _flatQualifyCount = n;
      _panels = null; // show the loading spinner while candidates recompute
    });
    await _load();
  }

  void _moveUp(int panelIndex, int rowIndex) {
    if (rowIndex == 0) return;
    setState(() {
      final list = _panels![panelIndex].candidates;
      final row = list.removeAt(rowIndex);
      list.insert(rowIndex - 1, row);
    });
  }

  void _moveDown(int panelIndex, int rowIndex) {
    final list = _panels![panelIndex].candidates;
    if (rowIndex == list.length - 1) return;
    setState(() {
      final row = list.removeAt(rowIndex);
      list.insert(rowIndex + 1, row);
    });
  }

  Future<void> _scheduleTiebreaker(int panelIndex, List<StandingRow> group, int round) async {
    setState(() => _schedulingIndexes.add(panelIndex));
    try {
      final section = _panels![panelIndex].section;
      final matches = generateTiebreakerMatches(
        tiedTeams: group,
        sport: widget.sport,
        category: widget.category,
        season: widget.season,
        round: round,
        section: section,
      );
      await _firestoreService.addMatchesBatch(matches);
      _message = round > 1
          ? 'Tie-breaker Round $round scheduled — the previous round ended in another tie for these '
              'teams, so they play again. Enter the result in Admin > Matches, then come back here.'
          : 'Tie-breaker match scheduled — enter its result in Admin > Matches, then come back here.';
      await _load();
    } catch (e) {
      setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _schedulingIndexes.remove(panelIndex));
    }
  }

  /// Schedules the Final's decider (Game 3) once a best-of-3 Final splits
  /// 1-1 — mirrors [_scheduleTiebreaker]'s "admin explicitly schedules one
  /// more match" pattern. Teams are read directly off the already-completed
  /// KOF1 (teamA/teamB are identical across the whole series by
  /// construction — see bracket_resolver.dart's _finalGames).
  Future<void> _scheduleFinalGame3() async {
    final kof1 = _byCode('KOF1');
    if (kof1 == null) return;
    setState(() => _schedulingGame3 = true);
    try {
      final matchNumber =
          _knockoutMatches.map((m) => m.matchNumber).reduce((a, b) => a > b ? a : b) + 1;
      final game3 = generateFinalGame3(
        teamA: kof1.teamA,
        teamB: kof1.teamB,
        sport: widget.sport,
        category: widget.category,
        season: widget.season,
        matchNumber: matchNumber,
      );
      await _firestoreService.addMatchesBatch([game3]);
      _message = 'Decider (Game 3) scheduled — enter its result in Admin > Matches once played.';
      await _load();
    } catch (e) {
      setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _schedulingGame3 = false);
    }
  }

  void _showBlocked(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _panelPrefix(_SectionPanel panel) => panel.label == null ? '' : 'Section ${panel.label}: ';

  Future<void> _generate() async {
    if (_generating) return;
    final panels = _panels;
    if (panels == null) return;

    if (panels.length > 2) {
      _showBlocked(
          'More than 2 league sections isn\'t supported yet — the knockout bracket is fixed at 4 teams.');
      return;
    }

    for (final panel in panels) {
      if (panel.candidates.length < panel.qualifyCount) {
        _showBlocked(
            '${_panelPrefix(panel)}Need at least ${panel.qualifyCount} teams with completed league matches.');
        return;
      }
      final chain = panel.chain;
      if (chain != null && chain.contestedGroup != null && chain.contestedGroupMatches.isNotEmpty) {
        final names = chain.contestedGroup!.map((r) => r.teamName).join(' vs ');
        _showBlocked('${_panelPrefix(panel)}Finish the tie-breaker for $names before generating the bracket.');
        return;
      }
    }

    for (final panel in panels) {
      final chain = panel.chain;
      if (chain != null && chain.contestedGroup != null && chain.contestedGroupMatches.isEmpty) {
        final names = chain.contestedGroup!.map((r) => r.teamName).join(' vs ');
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Teams are still tied'),
            content: Text(
              '${_panelPrefix(panel)}$names are still tied for the last spot and haven\'t played a '
              'tie-breaker. If you continue, the order currently shown above '
              'will decide who gets it.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Generate Anyway'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
    }

    setState(() {
      _generating = true;
      _message = null;
    });

    try {
      final existing = await _firestoreService.fetchMatches(
        sport: widget.sport,
        category: widget.category,
        season: widget.season,
        stage: 'knockout',
      );
      if (existing.isNotEmpty) {
        setState(() =>
            _message = 'Knockout matches already exist — delete them first from Admin > Matches to regenerate.');
        return;
      }

      List<Match> matches;
      if (panels.length == 1) {
        // Non-sectioned: admin-chosen qualifier count decides the shape.
        final seeds = panels[0].candidates.take(panels[0].qualifyCount).toList();
        matches = switch (panels[0].qualifyCount) {
          2 => generateKnockoutMatchesForTwo(
              twoSeeds: seeds,
              sport: widget.sport,
              category: widget.category,
              season: widget.season,
              bestOfThreeFinal: _bestOfThreeFinal),
          3 => generateKnockoutMatchesForThree(
              threeSeeds: seeds,
              sport: widget.sport,
              category: widget.category,
              season: widget.season,
              bestOfThreeFinal: _bestOfThreeFinal),
          _ => generateKnockoutMatches(
              top4Seeds: seeds,
              sport: widget.sport,
              category: widget.category,
              season: widget.season,
              bestOfThreeFinal: _bestOfThreeFinal),
        };
      } else {
        // Sectioned (always exactly 2 sections, 2 qualifiers each, guarded
        // above): seed 1 = Section A's 1st, seed 2 = Section B's 1st, seed 3
        // = Section A's 2nd, seed 4 = Section B's 2nd — so KO1 and KO2 each
        // pit different sections against each other rather than a
        // same-section rematch in the very first knockout round.
        final top4Seeds = [
          panels[0].candidates[0],
          panels[1].candidates[0],
          panels[0].candidates[1],
          panels[1].candidates[1],
        ];
        matches = generateKnockoutMatches(
          top4Seeds: top4Seeds,
          sport: widget.sport,
          category: widget.category,
          season: widget.season,
          bestOfThreeFinal: _bestOfThreeFinal,
        );
      }
      await _firestoreService.addMatchesBatch(matches);

      setState(() => _message = 'Knockout bracket generated! 🏆 On to the playoffs.');
    } catch (e) {
      setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final panels = _panels;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Generate Knockout Bracket')),
      body: panels == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (panels.length == 1 && panels[0].label == null) ...[
                    Text('Teams qualifying to the knockout stage', style: textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Pick how many teams advance — e.g. drop to 2 or 3 if a team withdrew '
                      'and the usual top 4 no longer makes sense.',
                      style: textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 2, label: Text('2')),
                        ButtonSegment(value: 3, label: Text('3')),
                        ButtonSegment(value: 4, label: Text('4')),
                      ],
                      selected: {_flatQualifyCount},
                      onSelectionChanged: (selection) => _setFlatQualifyCount(selection.first),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  Text('Final format', style: textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Best of 3 plays the Final as up to 3 separate matches — whoever wins 2 is champion.',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Single')),
                      ButtonSegment(value: true, label: Text('Best of 3')),
                    ],
                    selected: {_bestOfThreeFinal},
                    onSelectionChanged: (selection) => setState(() => _bestOfThreeFinal = selection.first),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (var p = 0; p < panels.length; p++) ...[
                    _SectionPanelView(
                      panel: panels[p],
                      scheduling: _schedulingIndexes.contains(p),
                      onMoveUp: (row) => _moveUp(p, row),
                      onMoveDown: (row) => _moveDown(p, row),
                      onScheduleTiebreaker: (group, round) => _scheduleTiebreaker(p, group, round),
                    ),
                    if (p < panels.length - 1) const SizedBox(height: AppSpacing.lg),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: _generating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.account_tree_outlined),
                      label: Text(_generating ? 'Generating...' : 'Generate Bracket'),
                      onPressed: _generating ? null : _generate,
                    ),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(_message!),
                      ),
                    ),
                  if (_needsFinalGame3)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: _DeciderActionCard(
                        teamNames: '${_byCode('KOF1')!.teamA.name} vs ${_byCode('KOF1')!.teamB.name}',
                        loading: _schedulingGame3,
                        onTap: _schedulingGame3 ? null : _scheduleFinalGame3,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  TextButton(
                    onPressed: () => context.push('/bracket?sport=${widget.sport}&category=${widget.category}'), // season carried via router's active SeasonState
                    child: const Text('View bracket'),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Renders one [_SectionPanel]'s candidate list — the confirm-seed-order
/// list, tie warnings, and tie-breaker action, unchanged from the original
/// single-table screen except every "4"/"top 4" is now [panel.qualifyCount].
class _SectionPanelView extends StatelessWidget {
  final _SectionPanel panel;
  final bool scheduling;
  final void Function(int rowIndex) onMoveUp;
  final void Function(int rowIndex) onMoveDown;
  final void Function(List<StandingRow> group, int round) onScheduleTiebreaker;

  const _SectionPanelView({
    required this.panel,
    required this.scheduling,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onScheduleTiebreaker,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final candidates = panel.candidates;
    final qualifyCount = panel.qualifyCount;
    final chain = panel.chain;
    final hasExtras = candidates.length > qualifyCount;
    final hasTieWithinCutoff = candidates.take(qualifyCount).any((r) => r.tiedWithAnother);
    final contestedGroup = chain?.contestedGroup;
    final contestedInProgress = contestedGroup != null && chain!.contestedGroupMatches.isNotEmpty;
    final contestStart = contestedGroup == null ? null : candidates.indexOf(contestedGroup.first);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (panel.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text('Section ${panel.label}', style: textTheme.titleMedium),
          ),
        Text('Confirm seed order ${switch (qualifyCount) {
          2 => '(Seed 1 vs 2, straight to the Final)',
          3 => '(Seed 1 gets a bye; Seed 2 vs 3 for the other Final spot)',
          _ => '(Seed 1 vs 2, Seed 3 vs 4)',
        }}:', style: textTheme.titleSmall),
        if (hasExtras)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Several teams are tied for the last spot. Schedule a tie-breaker '
              'match below, or use the arrows to move whichever team should take '
              'the last qualifying spot to the top of the list — anyone left below the line is out.',
              style: TextStyle(color: AppColors.warningAmber, fontWeight: FontWeight.w600),
            ),
          )
        else if (hasTieWithinCutoff)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Two or more teams above (highlighted) are dead level on points and '
              "total score. This doesn't change who qualifies — only who plays whom "
              'in the bracket. Use the arrows if you want to set their order, '
              "otherwise it's fine to generate as-is.",
              style: TextStyle(color: AppColors.warningAmber, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: AppSpacing.sm + 4),
        for (var i = 0; i < candidates.length; i++) ...[
          if (contestStart != null && i == contestStart)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(child: Divider(color: AppColors.warningAmber)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Text(
                      'CONTESTING LAST SPOT',
                      style: textTheme.labelSmall?.copyWith(color: AppColors.warningAmber, letterSpacing: 0.6),
                    ),
                  ),
                  Expanded(child: Divider(color: AppColors.warningAmber)),
                ],
              ),
            )
          else if (contestStart == null && hasExtras && i == qualifyCount)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Divider(thickness: 2),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs + 2),
            child: Card(
              color: contestStart != null && i >= contestStart
                  ? AppColors.warningAmber.withValues(alpha: 0.12)
                  : (i >= qualifyCount
                      ? scheme.surfaceContainerHighest
                      : (candidates[i].tiedWithAnother
                          ? AppColors.warningAmber.withValues(alpha: 0.12)
                          : null)),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    contestStart != null && i >= contestStart
                        ? '—'
                        : (i < qualifyCount ? '${i + 1}' : '—'),
                  ),
                ),
                title: Text(candidates[i].teamName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${candidates[i].points} pts · ${candidates[i].pointsScored} scored (league)'
                      '${contestStart != null && i >= contestStart ? " — contesting" : (contestStart == null && i >= qualifyCount ? " — OUT" : "")}',
                    ),
                    if (chain?.lastRoundStats[candidates[i].teamId] case final tb?)
                      Text(
                        'Tie-breaker: ${tb.points} pts · ${tb.pointsScored} scored',
                        style: TextStyle(color: AppColors.warningAmber),
                      ),
                  ],
                ),
                isThreeLine: chain?.lastRoundStats.containsKey(candidates[i].teamId) ?? false,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.arrow_upward), onPressed: () => onMoveUp(i)),
                    IconButton(icon: const Icon(Icons.arrow_downward), onPressed: () => onMoveDown(i)),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (contestedGroup != null && !contestedInProgress)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: _TiebreakerActionCard(
              teamNames: contestedGroup.map((r) => r.teamName).join(' vs '),
              round: chain!.nextRound,
              loading: scheduling,
              onTap: scheduling ? null : () => onScheduleTiebreaker(contestedGroup, chain.nextRound),
            ),
          ),
        if (contestedGroup != null && contestedInProgress)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warningAmber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded, color: AppColors.warningAmber),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Tie-breaker${chain.nextRound > 1 ? ' Round ${chain.nextRound}' : ''} '
                      'in progress for ${contestedGroup.map((r) => r.teamName).join(' vs ')} — '
                      'enter its result in Admin > Matches, then come back here.',
                      style: TextStyle(color: AppColors.warningAmber, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Same card treatment as [_TiebreakerActionCard] below, for the other
/// on-demand extra match this screen can schedule: a best-of-3 Final's
/// decider (Game 3), shown only once Games 1 and 2 have split 1-1 (see
/// [_GenerateBracketScreenState._needsFinalGame3]).
class _DeciderActionCard extends StatelessWidget {
  final String teamNames;
  final bool loading;
  final VoidCallback? onTap;

  const _DeciderActionCard({required this.teamNames, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.warningAmber.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.warningAmber.withValues(alpha: 0.2),
                child: const Icon(Icons.sports_tennis, color: AppColors.warningAmber),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Schedule Decider — Game 3',
                      style: textTheme.titleSmall
                          ?.copyWith(color: AppColors.warningAmber, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(teamNames, style: textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      'The Final split 1-1 — these teams play a decider.',
                      style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.warningAmber),
                )
              else
                const Icon(Icons.chevron_right, color: AppColors.warningAmber),
            ],
          ),
        ),
      ),
    );
  }
}

/// A modern, clearly-tappable action card for scheduling a tie-breaker match
/// — replaces a plain OutlinedButton whose single-line label (icon + "Schedule
/// Tie-Breaker Match: A vs B") read more like a wall of text than a button.
class _TiebreakerActionCard extends StatelessWidget {
  final String teamNames;
  final int round;
  final bool loading;
  final VoidCallback? onTap;

  const _TiebreakerActionCard({
    required this.teamNames,
    required this.round,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.warningAmber.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.warningAmber.withValues(alpha: 0.2),
                child: const Icon(Icons.sports_tennis, color: AppColors.warningAmber),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      round > 1 ? 'Schedule Tie-Breaker — Round $round' : 'Schedule Tie-Breaker Match',
                      style: textTheme.titleSmall
                          ?.copyWith(color: AppColors.warningAmber, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(teamNames, style: textTheme.bodySmall),
                    if (round > 1) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Round ${round - 1} ended level — these teams play again.',
                        style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.warningAmber),
                )
              else
                const Icon(Icons.chevron_right, color: AppColors.warningAmber),
            ],
          ),
        ),
      ),
    );
  }
}
