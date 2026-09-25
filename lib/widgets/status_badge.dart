import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/design/app_colors.dart';
import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../models/match.dart';

class StatusBadge extends StatelessWidget {
  final MatchStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      MatchStatus.live => (AppColors.liveRed, 'LIVE'),
      MatchStatus.completed => (AppColors.winGreen, 'DONE'),
      MatchStatus.upcoming => (Colors.blueGrey, 'UPCOMING'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == MatchStatus.live) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(color: AppColors.liveRed, shape: BoxShape.circle),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeOut(
                  duration: 700.ms,
                  begin: 1,
                  curve: Curves.easeInOut,
                ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
