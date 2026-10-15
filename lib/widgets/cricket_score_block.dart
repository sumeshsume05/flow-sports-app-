import 'package:flutter/material.dart';

import '../core/cricket/match_display.dart';
import '../core/design/app_colors.dart';
import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../models/match.dart';

/// The two teams' scores for a cricket match — "Blues 45/2 (4.3 ov)" — plus
/// one line underneath (result, chase, or the toss). Used by the match list
/// card and the top of the detail screen; reads only the match doc.
class CricketScoreBlock extends StatelessWidget {
  final Match match;

  /// Bigger numbers for the detail screen.
  final bool large;

  const CricketScoreBlock({super.key, required this.match, this.large = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final scores = sideScores(match);
    final live = match.status == MatchStatus.live;
    final status = matchStatusLine(match);
    final winner = match.result == MatchResult.teamA
        ? 'A'
        : match.result == MatchResult.teamB
            ? 'B'
            : null;

    final block = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < scores.length; i++) ...[
          if (i > 0) SizedBox(height: large ? AppSpacing.sm : AppSpacing.xs),
          _SideRow(
            score: scores[i],
            large: large,
            highlight: live && scores[i].batting,
            won: match.status == MatchStatus.completed && winner == scores[i].side,
            // Nothing was bowled in a walkover / no-result match: no "Yet to bat".
            showYetToBat: match.status != MatchStatus.upcoming && match.innings.isNotEmpty,
          ),
        ],
        if (live && match.liveText != null) ...[
          SizedBox(height: large ? AppSpacing.sm : AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sports_cricket, size: large ? 16 : 13, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  match.liveText!,
                  style: textTheme.bodySmall,
                  maxLines: large ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        if (status != null) ...[
          SizedBox(height: large ? AppSpacing.md : AppSpacing.sm),
          Text(
            status,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: match.status == MatchStatus.completed ? FontWeight.w700 : FontWeight.w500,
              color: live
                  ? AppColors.live
                  : match.status == MatchStatus.completed
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    if (!live) return block;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.live.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: block,
    );
  }
}

class _SideRow extends StatelessWidget {
  final SideScore score;
  final bool large;
  final bool highlight;
  final bool won;
  final bool showYetToBat;

  const _SideRow({
    required this.score,
    required this.large,
    required this.highlight,
    required this.won,
    required this.showYetToBat,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final emphasised = highlight || won;
    final color = highlight
        ? AppColors.live
        : won
            ? scheme.primary
            : null;
    final nameStyle = TextStyle(
      fontSize: large ? 18 : 15,
      fontWeight: emphasised ? FontWeight.w800 : FontWeight.w500,
      color: color,
    );
    final scoreStyle = TextStyle(
      fontSize: large ? 22 : 16,
      fontWeight: FontWeight.w800,
      color: color,
    );
    final oversStyle = TextStyle(
      fontSize: large ? 14 : 12,
      color: color ?? scheme.onSurfaceVariant,
    );
    final row = Row(
      children: [
        if (won) ...[
          Icon(Icons.emoji_events_rounded, size: large ? 20 : 14, color: scheme.primary),
          const SizedBox(width: 4),
        ] else if (highlight) ...[
          Icon(Icons.sports_cricket, size: large ? 18 : 14, color: AppColors.live),
          const SizedBox(width: 4),
        ],
        Expanded(child: Text(score.name, style: nameStyle, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: AppSpacing.sm),
        if (score.hasBatted) ...[
          Text(score.score!, style: scoreStyle),
          const SizedBox(width: 6),
          Text('(${score.overs} ov)', style: oversStyle),
        ] else if (showYetToBat)
          Text('Yet to bat', style: oversStyle),
      ],
    );
    final so = score.superOver;
    if (so == null) return row;
    final soColor = score.superOverBatting ? AppColors.live : scheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Super over  $so',
            style: oversStyle.copyWith(color: soColor, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
