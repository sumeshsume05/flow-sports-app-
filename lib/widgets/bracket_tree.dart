import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/design/app_colors.dart';
import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../models/match.dart';
import 'status_badge.dart';

/// A simple 4-box knockout bracket visual: Match 1, Match 2, Match 3, Final.
/// Not a package dependency — the bracket only ever has these 4 fixed slots
/// (see core/utils/bracket_resolver.dart), so a custom widget is simpler than
/// pulling in a generic tree-drawing library for one fixed shape.
class BracketTree extends StatelessWidget {
  final List<Match> knockoutMatches; // KO1, KO2, KO3, KOF, in any order
  final void Function(Match match)? onTapMatch;

  const BracketTree({super.key, required this.knockoutMatches, this.onTapMatch});

  Match? _byCode(String code) {
    for (final m in knockoutMatches) {
      if (m.matchCode == code) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ko1 = _byCode('KO1');
    final ko2 = _byCode('KO2');
    final ko3 = _byCode('KO3');
    final koF = _byCode('KOF');

    if (ko1 == null || ko2 == null || ko3 == null || koF == null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            Icon(Icons.account_tree_outlined, size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: AppSpacing.sm),
            const Text('Bracket not generated yet — check back once the league stage wraps up.'),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _BracketBox(match: ko1, onTap: onTapMatch)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _BracketBox(match: ko2, onTap: onTapMatch)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Icon(Icons.arrow_downward_rounded, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: AppSpacing.xs),
          _BracketBox(
              match: ko3, onTap: onTapMatch, subtitle: 'Loser of SF1 vs Winner of SF2 — winner reaches the Final'),
          const SizedBox(height: AppSpacing.xs),
          Icon(Icons.arrow_downward_rounded, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: AppSpacing.xs),
          _BracketBox(
            match: koF,
            onTap: onTapMatch,
            subtitle: 'Winner of SF1 vs Winner of the Final Qualifier',
            highlight: true,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}

class _BracketBox extends StatelessWidget {
  final Match match;
  final void Function(Match match)? onTap;
  final String? subtitle;
  final bool highlight;

  const _BracketBox({required this.match, this.onTap, this.subtitle, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: highlight ? scheme.primary.withValues(alpha: 0.1) : null,
      shape: highlight
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
            )
          : null,
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(match),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm + 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      match.label,
                      style: Theme.of(context).textTheme.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  StatusBadge(status: match.status),
                ],
              ),
              const SizedBox(height: AppSpacing.xs + 2),
              _TeamLine(name: match.teamA.name ?? 'TBD', won: match.result == MatchResult.teamA),
              _TeamLine(name: match.teamB.name ?? 'TBD', won: match.result == MatchResult.teamB),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamLine extends StatelessWidget {
  final String name;
  final bool won;

  const _TeamLine({required this.name, required this.won});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (won) ...[
          Icon(Icons.emoji_events_rounded, size: 13, color: AppColors.winGreen),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: won ? FontWeight.w800 : FontWeight.w400,
              color: won ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
