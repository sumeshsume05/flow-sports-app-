import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../models/commentary_entry.dart';
import '../services/firestore_service.dart';

/// Live-updating commentary feed for a match, newest entry at the bottom
/// like a running ticker. Read-only for viewers — posting is admin-only,
/// from the admin match edit screen. Height-bounded with its own internal
/// scroll (auto-following new entries) since the match detail screen it
/// sits on isn't itself scrollable.
class CommentaryTicker extends StatefulWidget {
  final String matchId;

  const CommentaryTicker({super.key, required this.matchId});

  @override
  State<CommentaryTicker> createState() => _CommentaryTickerState();
}

class _CommentaryTickerState extends State<CommentaryTicker> {
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
    return StreamBuilder<List<CommentaryEntry>>(
      stream: _firestoreService.watchCommentary(widget.matchId),
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
              Text('Live Commentary', style: textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: ListView.builder(
                  controller: _scrollController,
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final entry = entries[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs + 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (entry.createdAt != null)
                            Padding(
                              padding: const EdgeInsets.only(right: AppSpacing.sm),
                              child: Text(
                                DateFormat.Hm().format(entry.createdAt!),
                                style: textTheme.labelSmall,
                              ),
                            ),
                          Expanded(child: Text(entry.text, style: textTheme.bodyMedium)),
                        ],
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
