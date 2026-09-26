import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/design/app_colors.dart';
import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../models/match.dart';
import '../services/firestore_service.dart';
import '../services/local_prefs_service.dart';

/// "Who wins?" prediction widget for a match — tap a team to predict, switch
/// anytime before it starts, locks once the match goes live, and reveals
/// whether this device's pick was right once it's completed. Same trust
/// level as [ReactionBar]: local-only pick tracking via [LocalPrefsService],
/// not a security boundary.
class PredictionWidget extends StatefulWidget {
  final Match match;

  const PredictionWidget({super.key, required this.match});

  @override
  State<PredictionWidget> createState() => _PredictionWidgetState();
}

class _PredictionWidgetState extends State<PredictionWidget> {
  final _firestoreService = FirestoreService();
  final _prefs = LocalPrefsService();
  String? _myPick;
  bool _loaded = false;

  String get _prefKey => 'predicted_${widget.match.id}';

  @override
  void initState() {
    super.initState();
    _loadPick();
  }

  Future<void> _loadPick() async {
    final pick = await _prefs.getString(_prefKey);
    if (mounted) {
      setState(() {
        _myPick = pick;
        _loaded = true;
      });
    }
  }

  Future<void> _pick(String choice) async {
    if (_myPick == choice) return;
    final previous = _myPick;
    setState(() => _myPick = choice);
    await _prefs.setString(_prefKey, choice);
    try {
      await _firestoreService.castPrediction(widget.match.id, choice: choice, previousChoice: previous);
    } catch (_) {
      // Best-effort, offline-queued write like reactions — nothing to
      // surface here for a prediction tap.
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    // Predictions only make sense once both teams are actually decided.
    if (match.teamA.teamId == null || match.teamB.teamId == null) {
      return const SizedBox.shrink();
    }
    if (!_loaded) return const SizedBox.shrink();

    final locked = match.status != MatchStatus.upcoming;
    // Once locked, a device that never predicted has nothing to show —
    // don't clutter the screen with a closed poll it never took part in.
    if (locked && _myPick == null) return const SizedBox.shrink();

    final counts = match.predictionCounts;
    final countA = counts[PredictionChoice.teamA] ?? 0;
    final countB = counts[PredictionChoice.teamB] ?? 0;
    final total = countA + countB;

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(locked ? 'Prediction' : 'Who wins?', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PredictionOption(
                  label: match.teamA.name ?? 'Team A',
                  count: countA,
                  total: total,
                  selected: _myPick == PredictionChoice.teamA,
                  enabled: !locked,
                  onTap: () => _pick(PredictionChoice.teamA),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _PredictionOption(
                  label: match.teamB.name ?? 'Team B',
                  count: countB,
                  total: total,
                  selected: _myPick == PredictionChoice.teamB,
                  enabled: !locked,
                  onTap: () => _pick(PredictionChoice.teamB),
                ),
              ),
            ],
          ),
          if (match.status == MatchStatus.completed && _myPick != null && match.result != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _ResultReveal(result: match.result!, myPick: _myPick!),
            ),
        ],
      ),
    );
  }
}

class _PredictionOption extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PredictionOption({
    required this.label,
    required this.count,
    required this.total,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = total == 0 ? 0.0 : count / total;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.15) : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 4,
                backgroundColor: scheme.surfaceContainerHighest,
                color: selected ? scheme.primary : scheme.outline,
              ),
            ),
            const SizedBox(height: 2),
            Text('$count ${count == 1 ? "pick" : "picks"}', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _ResultReveal extends StatelessWidget {
  final MatchResult result;
  final String myPick;

  const _ResultReveal({required this.result, required this.myPick});

  @override
  Widget build(BuildContext context) {
    final correct = (myPick == PredictionChoice.teamA && result == MatchResult.teamA) ||
        (myPick == PredictionChoice.teamB && result == MatchResult.teamB);
    final tie = result == MatchResult.tie;

    final (icon, text, color) = tie
        ? (Icons.horizontal_rule_rounded, "It was a tie — no call on that one.", AppColors.warningAmber)
        : correct
            ? (Icons.check_circle_outline, 'You called it!', AppColors.winGreen)
            : (Icons.cancel_outlined, 'Not this time.', Theme.of(context).colorScheme.error);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
