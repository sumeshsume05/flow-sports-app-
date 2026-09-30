import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/utils/bracket_resolver.dart';
import '../../models/commentary_entry.dart';
import '../../models/match.dart';
import '../../services/firestore_service.dart';
import '../../widgets/score_input_field.dart';
import '../../widgets/status_badge.dart';

class AdminMatchEditScreen extends StatefulWidget {
  final String matchId;

  const AdminMatchEditScreen({super.key, required this.matchId});

  @override
  State<AdminMatchEditScreen> createState() => _AdminMatchEditScreenState();
}

class _AdminMatchEditScreenState extends State<AdminMatchEditScreen> {
  final _firestoreService = FirestoreService();
  late final _matchStream = _firestoreService.watchMatchWithSyncStatus(widget.matchId);
  final _scoreAController = TextEditingController();
  final _scoreBController = TextEditingController();
  final _venueController = TextEditingController();
  final _courtController = TextEditingController();
  final _commentaryController = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  bool _postingCommentary = false;
  String? _error;

  @override
  void dispose() {
    _scoreAController.dispose();
    _scoreBController.dispose();
    _venueController.dispose();
    _courtController.dispose();
    _commentaryController.dispose();
    super.dispose();
  }

  void _initFields(Match match) {
    if (_initialized) return;
    _scoreAController.text = match.scoreA?.toString() ?? '';
    _scoreBController.text = match.scoreB?.toString() ?? '';
    _venueController.text = match.venue ?? '';
    _courtController.text = match.court ?? '';
    _initialized = true;
  }

  Future<void> _setStatus(MatchStatus status) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _firestoreService.setMatchStatus(widget.matchId, status);
    } on FirestoreWriteException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickSchedule(Match match) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: match.scheduledAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(match.scheduledAt ?? now),
    );
    if (time == null) return;
    final scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _firestoreService.setMatchSchedule(widget.matchId, scheduledAt);
    } on FirestoreWriteException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearSchedule() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _firestoreService.setMatchSchedule(widget.matchId, null);
    } on FirestoreWriteException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveVenueDetails() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _firestoreService.updateMatch(widget.matchId, {
        'venue': _venueController.text.trim().isEmpty ? null : _venueController.text.trim(),
        'court': _courtController.text.trim().isEmpty ? null : _courtController.text.trim(),
      });
    } on FirestoreWriteException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _postCommentary() async {
    final text = _commentaryController.text.trim();
    if (text.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _postingCommentary = true);
    try {
      await _firestoreService.postCommentary(
        widget.matchId,
        CommentaryEntry(id: '', text: text, createdAt: null, postedByUid: uid),
      );
      _commentaryController.clear();
    } on FirestoreWriteException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _postingCommentary = false);
    }
  }

  Future<void> _saveResult(Match match) async {
    final scoreA = int.tryParse(_scoreAController.text);
    final scoreB = int.tryParse(_scoreBController.text);
    if (scoreA == null || scoreB == null) {
      setState(() => _error = 'Enter both scores to save the result.');
      return;
    }
    // A knockout match must produce a winner to advance the bracket — a
    // badminton game can't legitimately finish level (it goes to extra
    // points), so an equal score here means a mis-entered score, not a real
    // tie. Reported bug: saving one anyway used to silently (and wrongly)
    // advance team B, since nothing caught it before it reached the
    // dependent-slot resolver.
    if (match.stage == MatchStage.knockout && scoreA == scoreB) {
      setState(() => _error =
          "Knockout matches can't end level — a badminton game goes to extra points until there's a winner. Check the score.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final result = Match.computeResult(scoreA, scoreB)!;

      var dependentUpdates = <Match>[];
      if (match.stage == MatchStage.knockout) {
        final otherKnockout = await _firestoreService.fetchMatches(
          sport: match.sport,
          category: match.category,
          season: match.season,
          stage: 'knockout',
        );
        final completed = Match(
          id: match.id,
          sport: match.sport,
          category: match.category,
          season: match.season,
          stage: match.stage,
          matchNumber: match.matchNumber,
          label: match.label,
          matchCode: match.matchCode,
          teamA: match.teamA,
          teamB: match.teamB,
          scoreA: scoreA,
          scoreB: scoreB,
          result: result,
          status: MatchStatus.completed,
          notifyTopic: match.notifyTopic,
        );
        dependentUpdates = resolveDependentSlots(
          completed: completed,
          otherKnockoutMatches: otherKnockout.where((m) => m.id != match.id).toList(),
        );
      }

      await _firestoreService.saveResultAndResolveDependents(
        matchId: match.id,
        scoreA: scoreA,
        scoreB: scoreB,
        result: result,
        dependentUpdates: dependentUpdates,
      );
    } on FirestoreWriteException catch (e) {
      // Scores are deliberately left in the fields — nothing typed courtside
      // is ever thrown away on a failed save.
      if (mounted) {
        setState(() => _error = '${e.message} Your entered scores are kept — tap Save Result to retry.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Match')),
      body: StreamBuilder<(Match?, bool)>(
        stream: _matchStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (match, hasPendingWrites) = snapshot.data!;
          if (match == null) {
            return const Center(child: Text('Match not found.'));
          }
          _initFields(match);
          final hasResult = match.result != null;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Row(
                children: [
                  Expanded(child: Text(match.label, style: textTheme.titleLarge)),
                  StatusBadge(status: match.status),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('${match.teamA.name ?? "TBD"}  vs  ${match.teamB.name ?? "TBD"}',
                  style: textTheme.titleMedium),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start Match'),
                    onPressed: _saving || match.status == MatchStatus.live
                        ? null
                        : () => _setStatus(MatchStatus.live),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Reset to Upcoming'),
                    onPressed: _saving || match.status == MatchStatus.upcoming
                        ? null
                        : () => _setStatus(MatchStatus.upcoming),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Live commentary', style: textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Post a short live update — viewers see it appear instantly on the match.',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentaryController,
                      maxLength: commentaryMaxLength,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Set 2, 15-10',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _postCommentary(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _postingCommentary
                      ? const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton.filled(
                          icon: const Icon(Icons.send),
                          onPressed: _postCommentary,
                        ),
                ],
              ),
              const Divider(height: AppSpacing.xl * 1.5),
              if (match.teamA.teamId != null && match.teamB.teamId != null) ...[
                Text('Enter the final score', style: textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Saves instantly, even on a weak signal — it queues locally and '
                  "syncs the moment you're back online.",
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: ScoreInputField(
                          label: match.teamA.name ?? 'Team A', controller: _scoreAController),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: ScoreInputField(
                          label: match.teamB.name ?? 'Team B', controller: _scoreBController),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
                FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_saving ? 'Saving...' : 'Save Result'),
                  onPressed: _saving ? null : () => _saveResult(match),
                ),
                if (hasResult) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasPendingWrites ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
                        size: 16,
                        color: hasPendingWrites ? AppColors.warningAmber : AppColors.winGreen,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        hasPendingWrites ? 'Saved — syncing…' : 'Synced',
                        style: textTheme.bodySmall?.copyWith(
                          color: hasPendingWrites ? AppColors.warningAmber : AppColors.winGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ).animate(key: ValueKey(hasPendingWrites)).fadeIn(duration: 200.ms),
                ],
              ] else
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Text(
                    'Both teams need to be decided (e.g. an earlier match finished) '
                    'before a result can be entered here.',
                  ),
                ),
              const Divider(height: AppSpacing.xl * 1.5),
              Text('Schedule', style: textTheme.titleMedium),
              Text(
                'Optional — shown on the match list once set. Can be changed or cleared any time.',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      match.scheduledAt == null
                          ? 'Not scheduled'
                          : DateFormat('MMM d, y — h:mm a').format(match.scheduledAt!),
                      style: textTheme.bodyMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => _pickSchedule(match),
                    child: Text(match.scheduledAt == null ? 'Set' : 'Change'),
                  ),
                  if (match.scheduledAt != null)
                    TextButton(
                      onPressed: _saving ? null : _clearSchedule,
                      child: const Text('Clear'),
                    ),
                ],
              ),
              const Divider(height: AppSpacing.xl * 1.5),
              Text('Venue details', style: textTheme.titleMedium),
              Text('Optional — helps players find the right court.', style: textTheme.bodySmall),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _venueController,
                decoration: const InputDecoration(labelText: 'Venue'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _courtController,
                decoration: const InputDecoration(labelText: 'Court'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: _saving ? null : _saveVenueDetails,
                child: const Text('Save venue details'),
              ),
            ],
          ).animate().fadeIn(duration: 200.ms);
        },
      ),
    );
  }
}
