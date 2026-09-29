import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/design/app_colors.dart';
import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../models/standing_row.dart';

/// Renders standings as a list of rows that fit phone width with **no
/// horizontal scrolling** — the previous version wrapped a Material
/// `DataTable` in a horizontal scroll, and only Rank/Team/Pts fit on a real
/// screen before scrolling was needed. Each team is one row: rank, name and
/// points on the primary line (the number people actually care about), and
/// the rest of the stats in a compact line underneath — everything visible
/// at once.
class StandingsTable extends StatelessWidget {
  final List<StandingRow> rows;

  /// How many teams qualify out of this table — drives the "tied" highlight
  /// and the qualifying-rank badge color. 4 for a single flat league table;
  /// pass the section's own qualifier count (e.g. 2) when rendering one
  /// section's table out of several.
  final int qualifyCount;

  const StandingsTable({super.key, required this.rows, this.qualifyCount = 4});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Text('No teams yet — standings appear once league matches are played.'),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _StandingsRow(row: rows[i], qualifyCount: qualifyCount)
                .animate(delay: (i * 40).ms)
                .fadeIn(duration: 250.ms)
                .slideX(begin: 0.05, end: 0, duration: 250.ms),
          ),
      ],
    );
  }
}

class _StandingsRow extends StatelessWidget {
  final StandingRow row;
  final int qualifyCount;

  const _StandingsRow({required this.row, required this.qualifyCount});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tied = row.tiedWithAnother && (row.rank ?? 99) <= qualifyCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: tied ? AppColors.warningAmber.withValues(alpha: 0.12) : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: tied ? Border.all(color: AppColors.warningAmber.withValues(alpha: 0.5)) : null,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: (row.rank ?? 99) <= qualifyCount
                ? scheme.primary.withValues(alpha: 0.15)
                : scheme.surfaceContainerHighest,
            child: Text(
              '${row.rank}',
              style: textTheme.labelLarge?.copyWith(
                color: (row.rank ?? 99) <= qualifyCount ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.teamName, style: textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  'P ${row.played} · W ${row.won} · T ${row.tied} · L ${row.lost} · Scored ${row.pointsScored}',
                  style: textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${row.points}', style: textTheme.headlineSmall?.copyWith(color: scheme.primary)),
              Text('pts', style: textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}
