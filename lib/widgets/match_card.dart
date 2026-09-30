import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/design/app_colors.dart';
import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../core/utils/relative_time.dart';
import '../models/match.dart';
import 'reaction_bar.dart';
import 'status_badge.dart';

class MatchCard extends StatelessWidget {
  final Match match;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Shows a compact, tappable [ReactionBar] plus a one-line preview of the
  /// latest live-commentary entry (if any) — on by default for the viewer
  /// match list so "which teams are popular" and "what's happening" are both
  /// visible at a glance without opening each match. Admin's management list
  /// opts out of both to keep that screen purely functional.
  final bool showReactions;

  const MatchCard({
    super.key,
    required this.match,
    this.onTap,
    this.trailing,
    this.showReactions = true,
  });

  @override
  Widget build(BuildContext context) {
    final aName = match.teamA.name ?? 'TBD';
    final bName = match.teamB.name ?? 'TBD';
    final aWon = match.result == MatchResult.teamA;
    final bWon = match.result == MatchResult.teamB;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // Championship match — a bold gold/amber treatment, distinct from the
    // primary orange already used all over the rest of the app, so this one
    // card actually stands out at a glance rather than blending in.
    final isFinal = match.matchCode == 'KOF';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
      child: Card(
        color: isFinal ? AppColors.warningAmber.withValues(alpha: 0.16) : null,
        shape: isFinal
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: const BorderSide(color: AppColors.warningAmber, width: 2),
              )
            : null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        match.label,
                        style: textTheme.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (match.scheduledAt != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        DateFormat('MMM d, h:mm a').format(match.scheduledAt!),
                        style: textTheme.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(width: AppSpacing.sm),
                    StatusBadge(status: match.status),
                    if (trailing != null) ...[const SizedBox(width: AppSpacing.sm), trailing!],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _TeamRow(name: aName, score: match.scoreA, isWinner: aWon),
                const SizedBox(height: AppSpacing.xs),
                _TeamRow(name: bName, score: match.scoreB, isWinner: bWon),
                if (match.venue != null || match.court != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        [match.venue, match.court]
                            .where((s) => s != null && s.isNotEmpty)
                            .join(' · '),
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
                if (showReactions) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ReactionBar(matchId: match.id, counts: match.reactionCounts, compact: true),
                ],
                if (showReactions && match.lastCommentaryText != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💬', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          match.lastCommentaryText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall,
                        ),
                      ),
                      if (match.lastCommentaryAt != null) ...[
                        const SizedBox(width: 4),
                        Text(relativeTime(match.lastCommentaryAt!), style: textTheme.labelSmall),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  final String name;
  final int? score;
  final bool isWinner;

  const _TeamRow({required this.name, required this.score, required this.isWinner});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontWeight: isWinner ? FontWeight.w800 : FontWeight.w400,
      fontSize: 15,
      color: isWinner ? scheme.primary : null,
    );
    return Row(
      children: [
        if (isWinner) ...[
          Icon(Icons.emoji_events_rounded, size: 14, color: scheme.primary),
          const SizedBox(width: 4),
        ],
        Expanded(child: Text(name, style: style, overflow: TextOverflow.ellipsis)),
        if (score != null) Text('$score', style: style),
      ],
    );
  }
}
