import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/cricket/innings_replay.dart';
import '../../core/cricket/match_display.dart';
import '../../core/cricket/match_scoring.dart';
import '../../core/cricket/rules_summary.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../models/match.dart';
import '../../models/team.dart';
import '../../services/firestore_service.dart';
import '../../widgets/commentary_ticker.dart';
import '../../widgets/cricket_score_block.dart';
import '../../widgets/prediction_widget.dart';
import '../../widgets/reaction_bar.dart';
import '../../widgets/status_badge.dart';

/// The body of the match detail screen for a cricket match: the scores on
/// top, then Live / Scorecard / Info tabs.
///
/// Data: the match doc (already streamed by the screen), the two teams'
/// rosters for player names, and the ball log. A live match streams the log
/// so the scorecard moves ball by ball; a finished or upcoming one reads it
/// once, which keeps the read count low on the free plan.
class CricketMatchDetail extends StatefulWidget {
  final Match match;

  /// Tests inject these; the app reads from Firestore.
  final Stream<List<Team>>? teamsOverride;
  final Stream<List<LoggedEvent>>? ballsOverride;

  /// Shares the result as text (the Info tab's button).
  final VoidCallback? onShare;

  /// Predictions, reactions and admin commentary (they talk to Firestore on
  /// their own, so tests switch them off).
  final bool showEngagement;

  const CricketMatchDetail({
    super.key,
    required this.match,
    this.onShare,
    this.teamsOverride,
    this.ballsOverride,
    this.showEngagement = true,
  });

  @override
  State<CricketMatchDetail> createState() => _CricketMatchDetailState();
}

class _CricketMatchDetailState extends State<CricketMatchDetail> {
  FirestoreService? _service;
  late final Stream<List<Team>> _teams;
  late Stream<List<LoggedEvent>> _balls;
  late bool _streamsBalls;

  FirestoreService get _fs => _service ??= FirestoreService();

  @override
  void initState() {
    super.initState();
    _teams = widget.teamsOverride ??
        _fs.watchTeams(
          sport: widget.match.sport,
          category: widget.match.category,
          season: widget.match.season,
        );
    _openBalls();
  }

  @override
  void didUpdateWidget(CricketMatchDetail old) {
    super.didUpdateWidget(old);
    final live = widget.match.status == MatchStatus.live;
    if (live != _streamsBalls) _openBalls();
  }

  void _openBalls() {
    _streamsBalls = widget.match.status == MatchStatus.live;
    final source = widget.ballsOverride ?? _fs.watchBalls(widget.match.id);
    _balls = _streamsBalls ? source : source.take(1);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Team>>(
      stream: _teams,
      builder: (context, teamsSnap) {
        return StreamBuilder<List<LoggedEvent>>(
          stream: _balls,
          builder: (context, ballsSnap) {
            final teams = teamsSnap.data ?? const <Team>[];
            Team? find(String? id) {
              for (final t in teams) {
                if (t.id == id) return t;
              }
              return null;
            }

            final data = buildCricketView(
              match: widget.match,
              teamA: find(widget.match.teamA.teamId),
              teamB: find(widget.match.teamB.teamId),
              events: ballsSnap.data,
            );
            return CricketMatchDetailView(
              match: widget.match,
              data: data,
              ballsLoading: !ballsSnap.hasData && !ballsSnap.hasError,
              ballsFailed: ballsSnap.hasError,
              onShare: widget.onShare,
              showEngagement: widget.showEngagement,
            );
          },
        );
      },
    );
  }
}

/// Pure presentation of [CricketMatchDetail] — everything it needs is passed
/// in, so tests can build it from a simulated match.
class CricketMatchDetailView extends StatelessWidget {
  final Match match;
  final CricketViewData data;
  final bool ballsLoading;
  final bool ballsFailed;
  final VoidCallback? onShare;
  final bool showEngagement;

  const CricketMatchDetailView({
    super.key,
    required this.match,
    required this.data,
    this.ballsLoading = false,
    this.ballsFailed = false,
    this.onShare,
    this.showEngagement = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(match.label, style: Theme.of(context).textTheme.titleLarge),
                    ),
                    StatusBadge(status: match.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: CricketScoreBlock(match: match, large: true),
                ),
              ],
            ),
          ),
          const TabBar(tabs: [Tab(text: 'Live'), Tab(text: 'Scorecard'), Tab(text: 'Info')]),
          Expanded(
            child: TabBarView(
              children: [
                _LiveTab(match: match, data: data, showEngagement: showEngagement),
                _ScorecardTab(
                  match: match,
                  data: data,
                  loading: ballsLoading,
                  failed: ballsFailed,
                ),
                _InfoTab(match: match, data: data, onShare: onShare),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live
// ---------------------------------------------------------------------------

class _LiveTab extends StatelessWidget {
  final Match match;
  final CricketViewData data;
  final bool showEngagement;

  const _LiveTab({required this.match, required this.data, required this.showEngagement});

  @override
  Widget build(BuildContext context) {
    final state = data.state;
    final cur = state?.current;
    final scoring = state != null && state.phase == ScoringPhase.scoring && cur != null;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (scoring) ...[
          if (cur.isSuperOver) ...[
            const _Note(icon: Icons.bolt, text: 'Super over — 1 over each, 2 wickets', color: AppColors.live),
            const SizedBox(height: AppSpacing.md),
          ],
          _AtTheCrease(result: cur.result, nameOf: data.nameOf),
          const SizedBox(height: AppSpacing.md),
        ] else if (match.status == MatchStatus.upcoming) ...[
          _Note(
            icon: Icons.schedule,
            text: tossText(match.toss, match.teamA.name ?? 'TBD', match.teamB.name ?? 'TBD') ??
                'The match has not started yet.',
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (showEngagement) ...[
          PredictionWidget(match: match),
          const SizedBox(height: AppSpacing.md),
          ReactionBar(matchId: match.id, counts: match.reactionCounts),
          const SizedBox(height: AppSpacing.md),
          CommentaryTicker(matchId: match.id),
        ],
        if (cur != null && cur.result.balls.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _BallByBall(
            result: cur.result,
            nameOf: data.nameOf,
            freeHitRule: match.rules?.freeHit ?? true,
          ),
        ],
      ],
    );
  }
}

class _AtTheCrease extends StatelessWidget {
  final InningsResult result;
  final String Function(String id) nameOf;

  const _AtTheCrease({required this.result, required this.nameOf});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bowler = result.currentBowlerId == null ? null : result.bowlers[result.currentBowlerId];
    final over = result.overs.isEmpty ? null : result.overs.last;

    Widget batter(String? id, {required bool strike}) {
      if (id == null) return const SizedBox.shrink();
      final s = result.batters[id];
      return Row(
        children: [
          Expanded(
            child: Text(
              '${nameOf(id)}${strike ? ' *' : ''}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: strike ? FontWeight.w700 : FontWeight.w400),
            ),
          ),
          Text('${s?.runs ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(' (${s?.balls ?? 0})', style: textTheme.bodySmall),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Batting', style: textTheme.labelMedium),
          const SizedBox(height: 4),
          batter(result.strikerId, strike: true),
          const SizedBox(height: 2),
          batter(result.nonStrikerId, strike: false),
          const Divider(height: AppSpacing.lg),
          Text('Bowling', style: textTheme.labelMedium),
          const SizedBox(height: 4),
          if (bowler != null) ...[
            Text(nameOf(bowler.id), overflow: TextOverflow.ellipsis),
            Text(
              '${bowler.oversText} ov · ${bowler.maidens} md · ${bowler.runsConceded} runs · '
              '${bowler.wickets} wkts',
              style: textTheme.bodySmall,
            ),
          ]
          else
            Text('Next bowler is being picked', style: textTheme.bodySmall),
          if (over != null && !over.complete || (over != null && over.balls.isNotEmpty)) ...[
            const SizedBox(height: AppSpacing.md),
            Text('This over', style: textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final b in over.balls) _BallChip(token: b.token, ball: b)],
            ),
          ],
          if (result.freeHitNext) ...[
            const SizedBox(height: AppSpacing.md),
            const _Note(icon: Icons.bolt, text: 'Free hit on the next ball', color: AppColors.warningAmber),
          ],
          if (result.requiredRunRate != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Run rate ${oneDecimal(result.runRate)} · Needed ${oneDecimal(result.requiredRunRate!)}',
              style: textTheme.bodySmall,
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            Text('Run rate ${oneDecimal(result.runRate)}', style: textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _BallChip extends StatelessWidget {
  final String token;
  final BallRecord ball;

  const _BallChip({required this.token, required this.ball});

  @override
  Widget build(BuildContext context) {
    final Color color = ball.isWicket
        ? AppColors.liveRed
        : (ball.completedRuns == 0 && ball.batRuns >= 4)
            ? AppColors.winGreen
            : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      constraints: const BoxConstraints(minWidth: 30),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        token,
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color),
      ),
    );
  }
}

class _BallByBall extends StatefulWidget {
  final InningsResult result;
  final String Function(String id) nameOf;
  final bool freeHitRule;

  const _BallByBall({required this.result, required this.nameOf, required this.freeHitRule});

  @override
  State<_BallByBall> createState() => _BallByBallState();
}

class _BallByBallState extends State<_BallByBall> {
  static const _recentOvers = 3;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final groups = overGroups(
      widget.result,
      widget.nameOf,
      maxOvers: _all ? null : _recentOvers,
      freeHitRule: widget.freeHitRule,
    );
    final hasMore = widget.result.overs.where((o) => o.balls.isNotEmpty).length > _recentOvers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ball by ball', style: textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        for (final g in groups) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs + 2),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(g.header, style: textTheme.labelLarge),
          ),
          for (final l in g.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    margin: const EdgeInsets.only(right: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: (l.wicket
                              ? AppColors.liveRed
                              : l.boundary
                                  ? AppColors.winGreen
                                  : Theme.of(context).colorScheme.onSurfaceVariant)
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(l.label,
                        style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: Text(
                      l.text,
                      style: TextStyle(
                        fontWeight: l.wicket || l.boundary ? FontWeight.w700 : FontWeight.w400,
                        color: l.wicket
                            ? AppColors.liveRed
                            : l.boundary
                                ? AppColors.winGreen
                                : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (hasMore)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? 'Show recent overs only' : 'Show all overs'),
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _Note({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: TextStyle(color: c))),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scorecard
// ---------------------------------------------------------------------------

class _ScorecardTab extends StatelessWidget {
  final Match match;
  final CricketViewData data;
  final bool loading;
  final bool failed;

  const _ScorecardTab({
    required this.match,
    required this.data,
    required this.loading,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    final state = data.state;
    if (!data.hasScorecard) {
      final String text;
      if (match.resultType == ResultType.walkover) {
        text = 'No scorecard — this match was a walkover.';
      } else if (match.resultType == ResultType.noResult) {
        text = 'No scorecard — this match ended with no result.';
      } else if (match.status == MatchStatus.upcoming) {
        text = 'The scorecard appears once the match starts.';
      } else if (loading) {
        text = 'Loading the scorecard…';
      } else if (failed) {
        text = 'The scorecard could not be loaded. Pull back and open the match again.';
      } else {
        text = 'No scorecard for this match yet.';
      }
      return Center(
        child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Text(text)),
      );
    }
    final teamName = {'A': match.teamA.name ?? 'Team A', 'B': match.teamB.name ?? 'Team B'};
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (failed)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.md),
            child: _Note(
              icon: Icons.cloud_off,
              text: 'Could not refresh the ball-by-ball data. Showing what was loaded.',
              color: AppColors.warningAmber,
            ),
          ),
        for (final v in state!.innings) ...[
          _InningsCard(
            view: v,
            battingTeam: teamName[v.battingSide]!,
            bowlingTeam: teamName[v.bowlingSide]!,
            nameOf: data.nameOf,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }
}

class _InningsCard extends StatelessWidget {
  final InningsView view;
  final String battingTeam;
  final String bowlingTeam;
  final String Function(String id) nameOf;

  const _InningsCard({
    required this.view,
    required this.battingTeam,
    required this.bowlingTeam,
    required this.nameOf,
  });

  @override
  Widget build(BuildContext context) {
    final r = view.result;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final order = battingOrder(r);
    final didNotBat = [
      for (final id in r.setup.battingLineup)
        if (!order.contains(id)) nameOf(id),
    ];
    final bowlers = [
      for (final b in r.bowlers.values)
        if (b.legalBalls > 0 || b.runsConceded > 0 || b.wides > 0 || b.noBalls > 0) b,
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(inningsTitle(view, battingTeam),
                    style: textTheme.titleMedium, overflow: TextOverflow.ellipsis),
              ),
              Text('${r.scoreText} (${r.oversText} ov)',
                  style: textTheme.titleMedium?.copyWith(color: scheme.primary)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Row(cells: ['Batter', 'R', 'B', '4s', '6s', 'SR'], header: true),
          for (final id in order) _BatterRow(stats: r.batters[id]!, name: nameOf(id), nameOf: nameOf),
          const Divider(height: AppSpacing.lg),
          _Row(cells: [extrasText(r.extras)], wide: true),
          const SizedBox(height: 2),
          _Row(
            cells: ['Total  ${r.scoreText}  (${r.oversText} ov, RR ${oneDecimal(r.runRate)})'],
            wide: true,
            bold: true,
          ),
          if (didNotBat.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Did not bat: ${didNotBat.join(', ')}', style: textTheme.bodySmall),
          ],
          if (r.fallOfWickets.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Fall of wickets', style: textTheme.labelMedium),
            const SizedBox(height: 2),
            Text(
              r.fallOfWickets.map((f) => fallOfWicketText(f, nameOf)).join(' · '),
              style: textTheme.bodySmall,
            ),
          ],
          const Divider(height: AppSpacing.xl),
          Text('$bowlingTeam bowling', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          const _Row(cells: ['Bowler', 'O', 'M', 'R', 'W', 'Econ'], header: true),
          for (final b in bowlers)
            _Row(cells: [
              nameOf(b.id),
              b.oversText,
              '${b.maidens}',
              '${b.runsConceded}',
              '${b.wickets}',
              oneDecimal(b.economy),
            ]),
        ],
      ),
    );
  }
}

class _BatterRow extends StatelessWidget {
  final BatterStats stats;
  final String name;
  final String Function(String id) nameOf;

  const _BatterRow({required this.stats, required this.name, required this.nameOf});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final out = stats.status == BatterStatus.out;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row(
            cells: [
              name,
              '${stats.runs}',
              '${stats.balls}',
              '${stats.fours}',
              '${stats.sixes}',
              oneDecimal(stats.strikeRate, dashWhenZero: true),
            ],
            bold: !out,
          ),
          Text(dismissalText(stats, nameOf), style: textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// A table row: the first cell takes the leftover width, the rest are fixed
/// narrow columns so the table fits a 360px-wide phone without scrolling.
class _Row extends StatelessWidget {
  final List<String> cells;
  final bool header;
  final bool bold;

  /// One cell that uses the whole row (extras / total lines).
  final bool wide;

  const _Row({required this.cells, this.header = false, this.bold = false, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = header
        ? textTheme.labelMedium
        : textTheme.bodyMedium?.copyWith(fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    if (wide) return Text(cells.first, style: style);
    return Row(
      children: [
        Expanded(child: Text(cells.first, style: style, overflow: TextOverflow.ellipsis)),
        for (var i = 1; i < cells.length; i++)
          SizedBox(
            width: i == cells.length - 1 ? 46 : 34,
            child: Text(cells[i], textAlign: TextAlign.right, style: style),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Info
// ---------------------------------------------------------------------------

class _InfoTab extends StatelessWidget {
  final Match match;
  final CricketViewData data;
  final VoidCallback? onShare;

  const _InfoTab({required this.match, required this.data, this.onShare});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final nameA = match.teamA.name ?? 'Team A';
    final nameB = match.teamB.name ?? 'Team B';
    final toss = tossText(match.toss, nameA, nameB);

    Widget squad(String team, List<String> ids) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(team, style: textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(ids.isEmpty ? 'Not picked yet' : ids.map(data.nameOf).join(', '),
                  style: textTheme.bodyMedium),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (match.scheduledAt != null)
          _InfoLine(
            icon: Icons.event,
            text: DateFormat('EEE, MMM d · h:mm a').format(match.scheduledAt!),
          ),
        if (match.venue != null && match.venue!.isNotEmpty)
          _InfoLine(icon: Icons.location_on_outlined, text: match.venue!),
        if (toss != null) _InfoLine(icon: Icons.casino_outlined, text: toss),
        if (match.rules != null) _InfoLine(icon: Icons.rule, text: rulesSummary(match.rules!)),
        if (match.notes != null && match.notes!.isNotEmpty)
          _InfoLine(icon: Icons.notes, text: match.notes!),
        const SizedBox(height: AppSpacing.md),
        squad(nameA, match.lineupA),
        squad(nameB, match.lineupB),
        TextButton.icon(
          onPressed: () => showCricketHelpSheet(context),
          icon: const Icon(Icons.help_outline),
          label: const Text('How to read cricket scores'),
        ),
        if (onShare != null)
          OutlinedButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.share),
            label: const Text('Share result'),
          ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Help
// ---------------------------------------------------------------------------

/// A short plain-words guide for viewers who don't follow cricket.
Future<void> showCricketHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final textTheme = Theme.of(context).textTheme;
      Widget item(String head, String body) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(head, style: textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(body),
              ],
            ),
          );
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          children: [
            Text('How to read cricket scores', style: textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            item('45/2', '45 runs scored, 2 batters out (wickets).'),
            item('4.3 ov', '4 overs and 3 balls bowled. An over is 6 balls.'),
            item('Run rate', 'Runs per over so far. "Needed" is the rate the chasing team must keep up to win.'),
            item('Chasing', 'The second team must score one run more than the first team to win.'),
            item('Wd / Nb', 'Wide and no ball. Both give the batting team a run and the ball is bowled again.'),
            item('Free hit', 'After a no ball, the next ball cannot get the batter out (except a run out).'),
            item('Extras', 'Runs that do not come off the bat: wides, no balls, byes and leg byes.'),
            item('NRR', 'Net run rate, used to rank teams that have the same points.'),
          ],
        ),
      );
    },
  );
}
