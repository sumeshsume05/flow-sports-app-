import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/utils/bracket_resolver.dart';
import '../../core/utils/round_robin.dart';
import '../../core/utils/standings_calculator.dart';
import '../../models/standing_row.dart';
import '../../services/firestore_service.dart';

class GenerateBracketScreen extends StatefulWidget {
  final String category;
  final String season;

  const GenerateBracketScreen({super.key, required this.category, required this.season});

  @override
  State<GenerateBracketScreen> createState() => _GenerateBracketScreenState();
}

class _GenerateBracketScreenState extends State<GenerateBracketScreen> {
  final _firestoreService = FirestoreService();
  // All teams in seed contention — normally exactly 4, but wider when teams
  // are tied on points at the 4th-place cutoff, since the app can't guess
  // which tied team should take the last spot. The admin arranges this list
  // (reorder, or just leave lower ones below the line) and whichever 4 end
  // up on top when generating are the ones seeded.
  List<StandingRow>? _candidates;
  // Non-null exactly when the cutoff is ambiguous — walks however many
  // tie-breaker rounds have actually been played for that group so far (a
  // round can itself end in another tie, needing a further round).
  TieChainResult? _chain;
  bool _generating = false;
  bool _scheduling = false;
  String? _message;

  Future<void> _load() async {
    final teams = await _firestoreService.fetchTeams(
      sport: Sport.badminton,
      category: widget.category,
      season: widget.season,
    );
    final leagueMatches = await _firestoreService.fetchMatches(
      sport: Sport.badminton,
      category: widget.category,
      season: widget.season,
      stage: 'league',
    );
    final tiebreakerMatches = await _firestoreService.fetchMatches(
      sport: Sport.badminton,
      category: widget.category,
      season: widget.season,
      stage: 'tiebreaker',
    );
    final standings = computeStandings(teams: teams, leagueMatches: leagueMatches);
    final rawCandidates = _candidatesForTopFour(standings);
    final cluster = decidingTieCluster(rawCandidates);

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

    if (mounted) {
      setState(() {
        _candidates = candidates;
        _chain = chain;
      });
    }
  }

  /// Everyone who could plausibly claim a top-4 spot: the clear top 4 plus
  /// anyone else still level with 4th place on both points and points scored
  /// (points scored already breaks most ties automatically — this only
  /// widens the list when teams are genuinely dead level on both).
  List<StandingRow> _candidatesForTopFour(List<StandingRow> standings) {
    if (standings.length <= 4) return List.of(standings);
    final cutoff = standings[3];
    return standings
        .where((r) => r.points > cutoff.points ||
            (r.points == cutoff.points && r.pointsScored == cutoff.pointsScored))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _moveUp(int index) {
    if (index == 0) return;
    setState(() {
      final row = _candidates!.removeAt(index);
      _candidates!.insert(index - 1, row);
    });
  }

  void _moveDown(int index) {
    if (index == _candidates!.length - 1) return;
    setState(() {
      final row = _candidates!.removeAt(index);
      _candidates!.insert(index + 1, row);
    });
  }

  Future<void> _scheduleTiebreaker(List<StandingRow> group, int round) async {
    setState(() => _scheduling = true);
    try {
      final matches = generateTiebreakerMatches(
        tiedTeams: group,
        sport: Sport.badminton,
        category: widget.category,
        season: widget.season,
        round: round,
      );
      await _firestoreService.addMatchesBatch(matches);
      setState(() => _message = round > 1
          ? 'Tie-breaker Round $round scheduled — the previous round ended in another tie for these '
              'teams, so they play again. Enter the result in Admin > Matches, then come back here.'
          : 'Tie-breaker match scheduled — enter its result in Admin > Matches, then come back here.');
      await _load();
    } catch (e) {
      setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _scheduling = false);
    }
  }

  void _showBlocked(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _generate() async {
    if (_generating) return;
    final candidates = _candidates;
    if (candidates == null || candidates.length < 4) {
      _showBlocked('Need at least 4 teams with completed league matches.');
      return;
    }
    final chain = _chain;
    if (chain != null && chain.contestedGroup != null) {
      final names = chain.contestedGroup!.map((r) => r.teamName).join(' vs ');
      if (chain.contestedGroupMatches.isNotEmpty) {
        // A tie-breaker is already scheduled and unfinished — this is an
        // explicit commitment in progress, so it's a hard block, not a
        // dialog to click past.
        _showBlocked('Finish the tie-breaker for $names before generating the bracket.');
        return;
      }
      // Nothing scheduled yet — the cutoff is still genuinely ambiguous, so
      // never generate silently off whatever arbitrary order the tied teams
      // happen to be sorted in. Always surface this and require an explicit
      // confirmation, whether the tap was deliberate or accidental.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Teams are still tied'),
          content: Text(
            '$names are still tied for the last spot and haven\'t played a '
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
    setState(() {
      _generating = true;
      _message = null;
    });

    try {
      final existing = await _firestoreService.fetchMatches(
        sport: Sport.badminton,
        category: widget.category,
        season: widget.season,
        stage: 'knockout',
      );
      if (existing.isNotEmpty) {
        setState(() =>
            _message = 'Knockout matches already exist — delete them first from Admin > Matches to regenerate.');
        return;
      }

      final matches = generateKnockoutMatches(
        top4Seeds: _candidates!.take(4).toList(),
        sport: Sport.badminton,
        category: widget.category,
        season: widget.season,
      );
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final candidates = _candidates;
    final chain = _chain;
    final hasExtras = candidates != null && candidates.length > 4;
    // A tie can also sit entirely within the visible top 4 (e.g. seed 1 vs 2
    // dead level) without adding any extra "OUT" candidates — still worth
    // flagging so the admin doesn't miss it.
    final hasTieWithinTop4 =
        candidates != null && candidates.take(4).any((r) => r.tiedWithAnother);
    final contestedGroup = chain?.contestedGroup;
    // A round has been scheduled for the current contest but isn't finished.
    final contestedInProgress = contestedGroup != null && chain!.contestedGroupMatches.isNotEmpty;
    final contestStart =
        contestedGroup == null ? null : candidates!.indexOf(contestedGroup.first);

    return Scaffold(
      appBar: AppBar(title: const Text('Generate Knockout Bracket')),
      body: candidates == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Confirm seed order (Seed 1 vs 2, Seed 3 vs 4):',
                      style: textTheme.titleSmall),
                  if (hasExtras)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        'Several teams are tied for the last spot. Schedule a tie-breaker '
                        'match below, or use the arrows to move whichever team should take '
                        '4th place to the top of the list — anyone left below the line is out.',
                        style: TextStyle(color: AppColors.warningAmber, fontWeight: FontWeight.w600),
                      ),
                    )
                  else if (hasTieWithinTop4)
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
                                style: textTheme.labelSmall
                                    ?.copyWith(color: AppColors.warningAmber, letterSpacing: 0.6),
                              ),
                            ),
                            Expanded(child: Divider(color: AppColors.warningAmber)),
                          ],
                        ),
                      )
                    else if (contestStart == null && hasExtras && i == 4)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: Divider(thickness: 2),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs + 2),
                      child: Card(
                        color: contestStart != null && i >= contestStart
                            ? AppColors.warningAmber.withValues(alpha: 0.12)
                            : (i >= 4
                                ? scheme.surfaceContainerHighest
                                : (candidates[i].tiedWithAnother
                                    ? AppColors.warningAmber.withValues(alpha: 0.12)
                                    : null)),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              contestStart != null && i >= contestStart
                                  ? '—'
                                  : (i < 4 ? '${i + 1}' : '—'),
                            ),
                          ),
                          title: Text(candidates[i].teamName),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${candidates[i].points} pts · ${candidates[i].pointsScored} scored (league)'
                                '${contestStart != null && i >= contestStart ? " — contesting" : (contestStart == null && i >= 4 ? " — OUT" : "")}',
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
                              IconButton(
                                  icon: const Icon(Icons.arrow_upward), onPressed: () => _moveUp(i)),
                              IconButton(
                                  icon: const Icon(Icons.arrow_downward),
                                  onPressed: () => _moveDown(i)),
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
                        loading: _scheduling,
                        onTap: _scheduling
                            ? null
                            : () => _scheduleTiebreaker(contestedGroup, chain.nextRound),
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
                                style: TextStyle(
                                    color: AppColors.warningAmber, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(_message!),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  TextButton(
                    onPressed: () => context.push('/bracket?category=${widget.category}'), // season carried via router's active SeasonState
                    child: const Text('View bracket'),
                  ),
                ],
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
