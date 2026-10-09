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
  bool _adjustingLiveScoreA = false;
  bool _adjustingLiveScoreB = false;
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

  Future<void> _setStatus(MatchStatus status, Match match) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Reopening a *completed knockout* match would leave later rounds
      // standing on a result that no longer exists. If a later round has
      // already been started, stop and say so; otherwise clear the slots this
      // result had filled in the same batch.
      if (match.stage == MatchStage.knockout &&
          match.status == MatchStatus.completed &&
          status != MatchStatus.completed) {
        final knockout = await _firestoreService.fetchMatches(
          sport: match.sport,
          category: match.category,
          season: match.season,
          stage: 'knockout',
        );
        final dependents = dependentsOf(match.matchCode, knockout.where((m) => m.id != match.id).toList());
        final started = dependents.where(isStarted).toList();
        if (started.isNotEmpty) {
          if (mounted) {
            setState(() => _error =
                "Can't reopen ${match.label}: ${started.map((m) => m.label).join(', ')} "
                '${started.length == 1 ? 'has' : 'have'} already been started or played from its result. '
                'Reset the later round first, then come back to this match.');
          }
          return;
        }
        await _firestoreService.resetKnockoutMatch(
          match.id,
          status,
          unresolved: unresolveDependentSlots(match.matchCode, dependents),
        );
        return;
      }
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

  /// Bumps [team]'s live score by [delta] (+1 per point, -1 to undo a wrong
  /// tap) and keeps the Final Score fields in sync with the resultant value
  /// — without touching `_initFields`'s one-time-init guard, so an admin
  /// mid-edit of those fields elsewhere never gets silently overwritten
  /// except by their own live-score tap.
  Future<void> _adjustLiveScore(String team, int delta) async {
    setState(() {
      if (team == 'A') {
        _adjustingLiveScoreA = true;
      } else {
        _adjustingLiveScoreB = true;
      }
      _error = null;
    });
    try {
      final (scoreA, scoreB) =
          await _firestoreService.incrementLiveScore(widget.matchId, team: team, delta: delta);
      _scoreAController.text = scoreA.toString();
      _scoreBController.text = scoreB.toString();
    } on FirestoreWriteException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() {
          if (team == 'A') {
            _adjustingLiveScoreA = false;
          } else {
            _adjustingLiveScoreB = false;
          }
        });
      }
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

        // Correcting a result so the *winner changes* would swap the teams of a
        // later match that has already been started or played, leaving its
        // result attached to the wrong teams and the podium wrong. Refuse, and
        // say what to reset first. (Fixing only the score keeps the same teams,
        // so it is never blocked.)
        final stale = staleDependentUpdates(dependentUpdates, otherKnockout);
        if (stale.isNotEmpty) {
          if (mounted) {
            setState(() => _error =
                'This changes who advances, but ${stale.map((m) => m.label).join(', ')} '
                '${stale.length == 1 ? 'has' : 'have'} already been started or played. Reset the later '
                'round first (Reset to Upcoming), then correct this result.');
          }
          return;
        }
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
                        : () => _setStatus(MatchStatus.live, match),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Reset to Upcoming'),
                    onPressed: _saving || match.status == MatchStatus.upcoming
                        ? null
                        : () => _setStatus(MatchStatus.upcoming, match),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (match.status == MatchStatus.live) ...[
                _LiveScoreCard(
                  teamAName: match.teamA.name ?? 'TBD',
                  teamBName: match.teamB.name ?? 'TBD',
                  scoreA: int.tryParse(_scoreAController.text) ?? 0,
                  scoreB: int.tryParse(_scoreBController.text) ?? 0,
                  adjustingA: _adjustingLiveScoreA,
                  adjustingB: _adjustingLiveScoreB,
                  onAdjustA: (delta) => _adjustLiveScore('A', delta),
                  onAdjustB: (delta) => _adjustLiveScore('B', delta),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
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

/// Per-team +/- live score control, shown only while a match is `live` (see
/// `_AdminMatchEditScreenState.build`). Writes straight to the same
/// scoreA/scoreB the Final Score section below saves — see
/// `FirestoreService.incrementLiveScore` — so finishing a match is just
/// reviewing this number and tapping the existing Save Result button, not
/// retyping it.
class _LiveScoreCard extends StatelessWidget {
  final String teamAName;
  final String teamBName;
  final int scoreA;
  final int scoreB;
  final bool adjustingA;
  final bool adjustingB;
  final void Function(int delta) onAdjustA;
  final void Function(int delta) onAdjustB;

  const _LiveScoreCard({
    required this.teamAName,
    required this.teamBName,
    required this.scoreA,
    required this.scoreB,
    required this.adjustingA,
    required this.adjustingB,
    required this.onAdjustA,
    required this.onAdjustB,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.live.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.live.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Live Score', style: textTheme.titleSmall?.copyWith(color: AppColors.live)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _LiveScoreTeamControl(
                  name: teamAName,
                  score: scoreA,
                  adjusting: adjustingA,
                  onTapPlus: () => onAdjustA(1),
                  onTapMinus: scoreA > 0 ? () => onAdjustA(-1) : null,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _LiveScoreTeamControl(
                  name: teamBName,
                  score: scoreB,
                  adjusting: adjustingB,
                  onTapPlus: () => onAdjustB(1),
                  onTapMinus: scoreB > 0 ? () => onAdjustB(-1) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tap + the moment a team wins a point. Tap − to undo a wrong tap for that team.',
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LiveScoreTeamControl extends StatelessWidget {
  final String name;
  final int score;
  final bool adjusting;
  final VoidCallback onTapPlus;
  final VoidCallback? onTapMinus;

  const _LiveScoreTeamControl({
    required this.name,
    required this.score,
    required this.adjusting,
    required this.onTapPlus,
    required this.onTapMinus,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(name, style: textTheme.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.outlined(
              icon: const Icon(Icons.remove),
              onPressed: adjusting ? null : onTapMinus,
            ),
            SizedBox(
              width: 40,
              child: Text(
                '$score',
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton.filled(
              icon: const Icon(Icons.add),
              onPressed: adjusting ? null : onTapPlus,
            ),
          ],
        ),
      ],
    );
  }
}
