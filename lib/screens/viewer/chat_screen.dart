import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../models/chat_message.dart';
import '../../services/firestore_service.dart';
import '../../services/local_identity_service.dart';
import '../../state/auth_state.dart';
import '../../state/chat_settings_state.dart';

class ChatScreen extends StatefulWidget {
  final String season;

  const ChatScreen({super.key, required this.season});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _firestoreService = FirestoreService();
  final _identity = LocalIdentityService();
  final _textController = TextEditingController();
  late final _messagesStream = _firestoreService.watchRecentChatMessages(season: widget.season);

  String? _displayName;
  bool _sending = false;
  String? _error;
  StreamSubscription<List<ChatMessage>>? _readMarkerSub;

  @override
  void initState() {
    super.initState();
    _loadDisplayName();
    _identity.markReadNow();
    // Keep the read marker current for as long as this screen is open —
    // marking only on open/close races with the chat FAB, which reloads its
    // unread count the moment `Navigator.pop` is called, before this
    // screen's dispose() actually runs (that's deferred until the exit
    // transition finishes). Marking on every message here means the marker
    // is already correct well before any of that navigation timing matters.
    _readMarkerSub = _messagesStream.listen((_) => _identity.markReadNow());
  }

  @override
  void dispose() {
    _readMarkerSub?.cancel();
    _identity.markReadNow();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadDisplayName() async {
    final name = await _identity.getDisplayName();
    if (!mounted) return;
    if (name == null) {
      // First run on this device — ask once, after the frame so we have a
      // stable BuildContext for the dialog.
      WidgetsBinding.instance.addPostFrameCallback((_) => _promptForName());
    } else {
      setState(() => _displayName = name);
    }
  }

  Future<void> _promptForName() async {
    // Not dismissible and returns null only if the dialog route is popped
    // some other way — _NamePromptDialog itself only ever pops with a
    // validated, non-empty-after-trim name, so chat can't be reached
    // without one.
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _NamePromptDialog(),
    );
    if (name == null) return;
    await _identity.setDisplayName(name);
    if (mounted) setState(() => _displayName = name);
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _displayName == null) return;

    if (!await _identity.canSendNow()) {
      setState(() => _error = 'Slow down a little before sending another message.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final deviceId = await _identity.getOrCreateDeviceId();
      await _firestoreService.sendChatMessage(ChatMessage(
        id: '',
        text: text,
        authorName: _displayName!,
        authorDeviceId: deviceId,
        createdAt: null,
        season: widget.season,
      ));
      await _identity.recordSentNow();
      _textController.clear();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The FAB that normally opens this screen already hides itself when
    // chat is closed, but this screen can still be reached directly (e.g. a
    // still-open tab from before it was closed) — show the same closed
    // state rather than an empty/broken-looking composer.
    if (!context.watch<ChatSettingsState>().chatEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tournament Chat')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'Chat is currently closed by the tournament admin.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tournament Chat')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text('No messages yet — say hello!'),
                    ),
                  );
                }
                // Query is newest-first; a reversed ListView shows the
                // newest message at the bottom, like a normal chat.
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _MessageBubble(message: messages[i]),
                );
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      maxLength: chatMessageMaxLength,
                      decoration: const InputDecoration(
                        hintText: 'Say something…',
                        isDense: true,
                        counterText: '',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _sending
                      ? const SizedBox(
                          width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton.filled(
                          icon: const Icon(Icons.send),
                          onPressed: _send,
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final _firestoreService = FirestoreService();

  _MessageBubble({required this.message});

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: Text('Remove this message from ${message.authorName}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _firestoreService.deleteChatMessage(message.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Moderation is admin-only — same authorization already gating the
    // admin screens elsewhere in the app, just consumed here from a viewer
    // screen since chat itself needs no login.
    final isAdmin = context.watch<AuthState>().isAdmin;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(message.authorName,
                    style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (message.createdAt != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(DateFormat.Hm().format(message.createdAt!), style: textTheme.labelSmall),
                ],
                if (isAdmin) ...[
                  const Spacer(),
                  InkWell(
                    onTap: () => _confirmDelete(context),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.delete_outline, size: 16, color: scheme.error),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(message.text),
          ],
        ),
      ),
    );
  }
}

/// Blocks chat until a name is set — any characters are fine, but it must
/// be at least [chatDisplayNameMinLength] characters once whitespace is
/// trimmed (so e.g. 4 spaces doesn't count as a valid name). No skip/cancel:
/// this dialog only ever pops with a name that already passes that check.
class _NamePromptDialog extends StatefulWidget {
  const _NamePromptDialog();

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.length < chatDisplayNameMinLength) {
      setState(() => _error = 'Enter at least $chatDisplayNameMinLength characters.');
      return;
    }
    Navigator.pop(context, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pick a display name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: chatDisplayNameMaxLength,
        decoration: InputDecoration(
          hintText: 'e.g. Alex from Team Smashers',
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        FilledButton(onPressed: _submit, child: const Text('Join chat')),
      ],
    );
  }
}
