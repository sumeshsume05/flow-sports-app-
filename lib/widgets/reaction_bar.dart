import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../services/firestore_service.dart';
import '../services/local_prefs_service.dart';

/// Emoji reaction chips shown on a match, with live counts. Tapping toggles
/// this device's reaction on/off (react, then tap again to undo) — guarded
/// locally via [LocalPrefsService] so one device can't double-count itself,
/// not server-enforced beyond keeping counts non-negative (see that class's
/// doc comment and the `reactionCountsValid` Firestore rule).
class ReactionBar extends StatefulWidget {
  final String matchId;
  final Map<String, int> counts;

  /// Smaller chips for use inline on a match list card, vs. full-size on
  /// the match detail screen.
  final bool compact;

  const ReactionBar({
    super.key,
    required this.matchId,
    required this.counts,
    this.compact = false,
  });

  @override
  State<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<ReactionBar> {
  final _firestoreService = FirestoreService();
  final _prefs = LocalPrefsService();
  final Set<String> _reactedLocally = {};

  @override
  void initState() {
    super.initState();
    _loadReactedFlags();
  }

  Future<void> _loadReactedFlags() async {
    for (final emoji in ReactionEmoji.all) {
      if (await _prefs.hasFlag(_flagKey(emoji))) {
        if (mounted) setState(() => _reactedLocally.add(emoji));
      }
    }
  }

  String _flagKey(String emoji) => 'reacted_${widget.matchId}_$emoji';

  Future<void> _tap(String emoji) async {
    final wasActive = _reactedLocally.contains(emoji);
    setState(() {
      if (wasActive) {
        _reactedLocally.remove(emoji);
      } else {
        _reactedLocally.add(emoji);
      }
    });
    await (wasActive ? _prefs.clearFlag(_flagKey(emoji)) : _prefs.setFlag(_flagKey(emoji)));
    try {
      await _firestoreService.incrementReaction(widget.matchId, emoji, delta: wasActive ? -1 : 1);
    } catch (_) {
      // Offline writes queue silently via Firestore's local cache; nothing
      // to surface here for a best-effort reaction tap.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs + 2,
      children: [
        for (final emoji in ReactionEmoji.all)
          _ReactionChip(
            glyph: reactionEmojiGlyph(emoji),
            count: widget.counts[emoji] ?? 0,
            active: _reactedLocally.contains(emoji),
            compact: widget.compact,
            onTap: () => _tap(emoji),
          ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final String glyph;
  final int count;
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  const _ReactionChip({
    required this.glyph,
    required this.count,
    required this.active,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.xs + 2 : AppSpacing.sm,
          vertical: compact ? 3 : 6,
        ),
        decoration: BoxDecoration(
          color: active ? scheme.primary.withValues(alpha: 0.15) : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: active ? scheme.primary : scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(glyph, style: TextStyle(fontSize: compact ? 13 : 16)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 12 : 14,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
