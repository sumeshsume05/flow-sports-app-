import 'package:flutter/material.dart';

import '../core/design/app_colors.dart';
import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../core/utils/match_grouping.dart';

/// Header for one [MatchSection] in a match list — bordered pill with the
/// round/stage name, match count, and a completed badge once every match in
/// it is done, so a long list of matches reads as distinct, clearly
/// separated rounds instead of one ambiguous flat list.
class MatchSectionHeader extends StatelessWidget {
  final MatchSection section;

  const MatchSectionHeader({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final completed = section.isCompleted;

    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 4, vertical: AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color: completed
            ? AppColors.winGreen.withValues(alpha: 0.08)
            : scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: (completed ? AppColors.winGreen : scheme.primary).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_circle_rounded : Icons.play_circle_outline_rounded,
            size: 16,
            color: completed ? AppColors.winGreen : scheme.primary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '${section.title}  ·  ${section.matches.length} match${section.matches.length == 1 ? '' : 'es'}',
              style: textTheme.labelLarge?.copyWith(
                color: completed ? AppColors.winGreen : scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (completed)
            Text(
              'COMPLETED',
              style: textTheme.labelSmall
                  ?.copyWith(color: AppColors.winGreen, fontWeight: FontWeight.w800),
            ),
        ],
      ),
    );
  }
}
