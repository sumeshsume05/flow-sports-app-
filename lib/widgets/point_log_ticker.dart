import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../models/point_log_entry.dart';
import '../services/firestore_service.dart';

/// Live-updating point-by-point log for a match, oldest entry at the top —
/// same shape/behavior as [CommentaryTicker], just fed by the live-score
/// +/- taps (`FirestoreService.watchPointLog`/`incrementLiveScore`) instead
/// of free-text commentary. Read-only for viewers; entries are written only
/// from the admin match edit screen's Live Score control.
class PointLogTicker extends StatefulWidget {
  final String matchId;
  final String teamAName;
  final String teamBName;

  const PointLogTicker({
    super.key,
    required this.matchId,
    required this.teamAName,
    required this.teamBName,
  });

  @override
  State<PointLogTicker> createState() => _PointLogTickerState();
}

class _PointLogTickerState extends State<PointLogTicker> {
  final _firestoreService = FirestoreService();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PointLogEntry>>(
      stream: _firestoreService.watchPointLog(widget.matchId),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? [];
        if (entries.isEmpty) return const SizedBox.shrink();
        _scrollToLatest();

        final textTheme = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;

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
              Text('Point by Point', style: textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: ListView.builder(
                  controller: _scrollController,
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final entry = entries[i];
                    final scorer = entry.team == 'A' ? widget.teamAName : widget.teamBName;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs + 2),
                      child: Text(
                        '${entry.scoreA} - ${entry.scoreB}  •  $scorer point',
                        style: textTheme.bodyMedium,
                      ),
                    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.15, end: 0);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
