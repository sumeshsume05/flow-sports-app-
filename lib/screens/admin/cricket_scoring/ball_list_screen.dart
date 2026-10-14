import 'package:flutter/material.dart';

import '../../../core/cricket/commentary_text.dart';
import '../../../core/cricket/cricket_event.dart';
import '../../../core/cricket/match_scoring.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_spacing.dart';
import 'ball_editor.dart';
import 'scoring_controller.dart';

/// Every ball of the match in order, over by over. Tap a ball to correct or
/// delete it; balls whose inputs stopped making sense after an earlier edit
/// carry a ⚠ and can be fixed or accepted as they are.
class CricketBallListScreen extends StatefulWidget {
  final CricketScoringController controller;

  const CricketBallListScreen({super.key, required this.controller});

  @override
  State<CricketBallListScreen> createState() => _CricketBallListScreenState();
}

class _CricketBallListScreenState extends State<CricketBallListScreen> {
  int? _innings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final state = c.state;
        final textTheme = Theme.of(context).textTheme;
        if (state == null || state.innings.isEmpty) {
          return Scaffold(appBar: AppBar(title: const Text('Balls')), body: const Center(child: Text('No balls yet.')));
        }
        final index = _innings ?? state.innings.last.index;
        final view = state.innings.firstWhere((i) => i.index == index, orElse: () => state.innings.last);
        final r = view.result;
        final events = [...view.events]..sort((a, b) => a.seq.compareTo(b.seq));
        final records = {for (final b in r.balls) b.seq: b};
        final blocking = r.blockingFlags;

        final rows = <Widget>[];
        int? lastOver;
        for (final e in events) {
          final rec = records[e.seq];
          final flags = r.flagsFor(e.seq);
          if (rec != null && rec.over != lastOver) {
            lastOver = rec.over;
            final over = r.overs.where((o) => o.over == rec.over).firstOrNull;
            rows.add(Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
              child: Text(
                'Over ${rec.over + 1}${over?.bowlerId == null ? '' : ' — ${c.nameOf(over!.bowlerId!)}'}',
                style: textTheme.titleSmall,
              ),
            ));
          }
          final logged = LoggedEvent(view.index, e);
          final String title;
          final String subtitle;
          if (rec != null) {
            title = rec.token;
            subtitle = ballCommentary(rec, c.nameOf, freeHitRule: c.rules.freeHit);
          } else {
            title = switch (e.kind) {
              EventKind.swapStrike => '⇄',
              EventKind.retire => 'Ret',
              EventKind.endInnings => 'End',
              EventKind.ball => '?',
            };
            subtitle = switch (e.kind) {
              EventKind.swapStrike => 'Batters swapped ends',
              EventKind.retire => '${e.retiredBatterId == null ? 'A batter' : c.nameOf(e.retiredBatterId!)} retired',
              EventKind.endInnings => 'Innings ended by the scorer',
              EventKind.ball => 'Ball not counted — review it',
            };
          }
          rows.add(ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: rec?.isWicket == true ? AppColors.liveRed : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(title,
                  style: TextStyle(
                      fontSize: title.length > 3 ? 9 : 12,
                      fontWeight: FontWeight.w700,
                      color: rec?.isWicket == true ? Colors.white : null)),
            ),
            title: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: flags.isEmpty
                ? null
                : Text(
                    flags.map((f) => f.message).join(' '),
                    style: TextStyle(color: flags.every((f) => f.acknowledged) ? null : AppColors.warningAmber),
                  ),
            trailing: flags.isEmpty
                ? null
                : Icon(
                    flags.every((f) => f.acknowledged) ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                    color: AppColors.warningAmber,
                  ),
            onTap: c.isCompleted
                ? null
                : e.kind == EventKind.ball
                    ? () => showBallEditor(context, c, logged)
                    : () => _confirmDeleteControl(context, c, logged),
          ));
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Balls')),
          body: ListView(
            children: [
              if (state.innings.length > 1)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SegmentedButton<int>(
                    segments: [
                      for (final i in state.innings)
                        ButtonSegment(value: i.index, label: Text('${c.teamName(i.battingSide)} innings')),
                    ],
                    selected: {view.index},
                    onSelectionChanged: (s) => setState(() => _innings = s.first),
                  ),
                ),
              if (c.isCompleted)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text('This match is finished. Reopen it from the scoring screen to edit balls.'),
                ),
              if (blocking.isNotEmpty)
                Container(
                  margin: const EdgeInsets.all(AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.warningAmber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.warningAmber),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text('${blocking.length} thing${blocking.length == 1 ? '' : 's'} to review. '
                            'Fix the ball, or accept it as it is.'),
                      ),
                      if (!c.isCompleted)
                        TextButton(onPressed: () => _acceptAll(c, view), child: const Text('Accept all')),
                    ],
                  ),
                ),
              ...rows,
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        );
      },
    );
  }

  Future<void> _acceptAll(CricketScoringController c, InningsView view) async {
    final byEvent = <int, Set<String>>{};
    for (final f in view.result.blockingFlags) {
      byEvent.putIfAbsent(f.seq, () => {}).add(f.code.name);
    }
    for (final e in view.events) {
      final more = byEvent[e.seq];
      if (more != null) await c.acknowledge(e.seq, {...e.acknowledgedFlags, ...more});
    }
  }

  Future<void> _confirmDeleteControl(BuildContext context, CricketScoringController c, LoggedEvent e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this entry?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await c.deleteBall(e);
  }
}
