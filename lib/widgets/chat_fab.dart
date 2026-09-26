import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/design/app_colors.dart';
import '../core/design/app_radius.dart';
import '../models/chat_message.dart';
import '../services/firestore_service.dart';
import '../services/local_identity_service.dart';
import '../state/season_state.dart';

/// Floating chat entry point shown on every viewer screen (wired in via a
/// `ShellRoute` in `app_router.dart`, so no individual screen needs to know
/// about it), with a small unread-count badge sourced from the same bounded
/// chat stream the chat screen itself uses — no extra Firestore reads.
class ChatFab extends StatefulWidget {
  const ChatFab({super.key});

  @override
  State<ChatFab> createState() => _ChatFabState();
}

class _ChatFabState extends State<ChatFab> {
  final _firestoreService = FirestoreService();
  final _identity = LocalIdentityService();
  DateTime? _lastReadAt;

  @override
  void initState() {
    super.initState();
    _loadLastRead();
  }

  Future<void> _loadLastRead() async {
    final t = await _identity.getLastReadAt();
    if (mounted) setState(() => _lastReadAt = t);
  }

  Future<void> _openChat() async {
    await context.push('/chat');
    // Back from chat — refresh the read marker the screen just set, so the
    // badge clears immediately without waiting on the next stream event.
    await _loadLastRead();
  }

  @override
  Widget build(BuildContext context) {
    // Watched (not read-once) so the badge/stream correctly follow an admin
    // switching the active season while this persistent overlay stays alive
    // across navigation — unlike a one-shot pushed screen, this widget isn't
    // rebuilt fresh per season change otherwise.
    final season = context.watch<SeasonState>().activeSeasonId ?? '';
    final messagesStream = _firestoreService.watchRecentChatMessages(season: season);

    return Positioned(
      right: 16,
      bottom: 16,
      child: StreamBuilder<List<ChatMessage>>(
        stream: messagesStream,
        builder: (context, snapshot) {
          final messages = snapshot.data ?? [];
          final unread = _lastReadAt == null
              ? messages.length
              : messages.where((m) => m.createdAt?.isAfter(_lastReadAt!) ?? false).length;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              FloatingActionButton(
                heroTag: 'chatFab',
                tooltip: 'Chat',
                onPressed: _openChat,
                child: const Icon(Icons.forum_outlined),
              ),
              if (unread > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.liveRed,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                    ),
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
