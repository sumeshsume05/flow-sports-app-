import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/design/app_colors.dart';
import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../models/match.dart';
import 'status_badge.dart';

/// A simple knockout bracket visual. Renders whichever shape is actually
/// present (see core/utils/bracket_resolver.dart's 2/3/4-team generators —
/// the admin picks the qualifier count, so this needs to handle all three):
/// just a Final (2 teams), Semifinal + Final (3 teams, Seed 1 had a bye), or
/// the full Match 1/2/3 + Final (4 teams). Not a package dependency — a
/// custom widget is simpler than pulling in a generic tree-drawing library
/// for these few fixed shapes.
class BracketTree extends StatelessWidget {
  final List<Match> knockoutMatches; // KO1, KO2, KO3, KOF — whichever exist
  final void Function(Match match)? onTapMatch;

  const BracketTree({super.key, required this.knockoutMatches, this.onTapMatch});

  Match? _byCode(String code) {
    for (final m in knockoutMatches) {
      if (m.matchCode == code) return m;
    }
    return null;
  }

  /// Renders the Final slot — a single box normally, or (when the admin
  /// picked a best-of-3 Final — see bracket_resolver.dart's _finalGames)
  /// a stack of game boxes with a running series score. teamA/teamB are
  /// identical across KOF1/KOF2[/KOF3] by construction, so any one game's
  /// refs name the two sides consistently for the series-score label.
  Widget _finalSlot(BuildContext context, {Match? koF1, Match? koF2, Match? koF3, String? subtitle}) {
    if (koF1 == null) return const SizedBox.shrink();
    final games = [koF1, koF2!, ?koF3];
    final aWins = games.where((m) => m.result == MatchResult.teamA).length;
    final bWins = games.where((m) => m.result == MatchResult.teamB).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Final — Best of 3 ($aWins–$bWins)',
          style: Theme.of(context).textTheme.titleSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        if (subtitle != null) ...[
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs),
        ],
        for (var i = 0; i < games.length; i++) ...[
          _BracketBox(match: games[i], onTap: onTapMatch, highlight: true),
          if (i < games.length - 1) const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ko1 = _byCode('KO1');
    final ko2 = _byCode('KO2');
    final ko3 = _byCode('KO3');
    final koF = _byCode('KOF');
    final koF1 = _byCode('KOF1');
    final koF2 = _byCode('KOF2');
    final koF3 = _byCode('KOF3');
    final hasFinal = koF != null || koF1 != null;

    if (!hasFinal) {
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

    final arrow = Icon(Icons.arrow_downward_rounded, color: Theme.of(context).colorScheme.outline);

    Widget finalBox({String? subtitle}) {
      if (koF1 != null) {
        return _finalSlot(context, koF1: koF1, koF2: koF2, koF3: koF3, subtitle: subtitle);
      }
      return _BracketBox(match: koF!, onTap: onTapMatch, subtitle: subtitle, highlight: true);
    }

    // 2-team shape: just the Final.
    if (ko1 == null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: finalBox(),
      ).animate().fadeIn(duration: 250.ms);
    }

    // 3-team shape: Semifinal (Seeds 2 vs 3) -> Final (Seed 1 had a bye).
    if (ko2 == null || ko3 == null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BracketBox(match: ko1, onTap: onTapMatch, subtitle: 'Winner faces Seed 1 (bye) in the Final'),
            const SizedBox(height: AppSpacing.xs),
            arrow,
            const SizedBox(height: AppSpacing.xs),
            finalBox(subtitle: 'Seed 1 (bye) vs the Semifinal winner'),
          ],
        ),
      ).animate().fadeIn(duration: 250.ms);
    }

    // 4-team shape (the original, unchanged).
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
          arrow,
          const SizedBox(height: AppSpacing.xs),
          _BracketBox(
              match: ko3, onTap: onTapMatch, subtitle: 'Loser of SF1 vs Winner of SF2 — winner reaches the Final'),
          const SizedBox(height: AppSpacing.xs),
          arrow,
          const SizedBox(height: AppSpacing.xs),
          finalBox(subtitle: 'Winner of SF1 vs Winner of the Final Qualifier'),
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
