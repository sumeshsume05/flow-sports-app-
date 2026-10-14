import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/cricket/commentary_text.dart';
import '../../core/cricket/cricket_event.dart';
import '../../core/cricket/innings_replay.dart';
import '../../core/cricket/match_result.dart';
import '../../core/cricket/match_scoring.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../models/match.dart';
import 'cricket_scoring/ball_list_screen.dart';
import 'cricket_scoring/scoring_controller.dart';
import 'cricket_scoring/wicket_sheet.dart';

/// Live ball-by-ball scoring for one cricket match. One next step at a time:
/// start the innings (pick openers) → score balls → innings break → second
/// innings → review the result and save it. Setup (rules, squads, toss) is
/// done on the match page before this.
class AdminCricketScoringScreen extends StatefulWidget {
  final String matchId;

  /// Tests pass their own controller (backed by a fake Firestore).
  final CricketScoringController? controller;

  const AdminCricketScoringScreen({super.key, required this.matchId, this.controller});

  @override
  State<AdminCricketScoringScreen> createState() => _AdminCricketScoringScreenState();
}

class _AdminCricketScoringScreenState extends State<AdminCricketScoringScreen> {
  late final CricketScoringController _c;

  // What the scorer has chosen for the NEXT ball (cleared after each ball).
  Delivery _delivery = Delivery.legal;
  RunType _extra = RunType.none;
  String? _chosenBowler;

  @override
  void initState() {
    super.initState();
    _c = widget.controller ?? CricketScoringController(widget.matchId, editorId: FirebaseAuth.instance.currentUser?.uid);
  }

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Fire-and-forget: Firestore applies a write locally at once and queues it
  /// when there is no signal, so the keypad never waits on the network.
  void _fire(Future<void> write) {
    write.catchError((Object e) => _say('$e'));
  }

  /// A short message after a one-tap action, optionally with an UNDO button, so
  /// nothing the scorer taps by accident is silent. It floats at the TOP of the
  /// screen: at the bottom it would cover the keypad and the Undo button.
  void _toast(String message, {bool withUndo = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final height = MediaQuery.of(context).size.height;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(12, 0, 12, (height - 140).clamp(0, height)),
      action: withUndo ? SnackBarAction(label: 'UNDO', onPressed: () => _undo(quiet: true)) : null,
    ));
  }

  void _saidWithUndo(String message) => _toast(message, withUndo: true);

  /// What the newest entry of the innings being scored is, in words.
  String? _describeLast() {
    final cur = _c.state?.current;
    if (cur == null) return null;
    final events = [...cur.events]..sort((a, b) => a.seq.compareTo(b.seq));
    if (events.isEmpty) return null;
    final last = events.last;
    for (final b in cur.result.balls) {
      if (b.seq == last.seq) return ballCommentary(b, _c.nameOf, freeHitRule: _c.rules.freeHit);
    }
    return switch (last.kind) {
      EventKind.swapStrike => 'Batters swapped ends',
      EventKind.retire => 'A batter retired',
      EventKind.endInnings => 'Innings ended',
      EventKind.ball => 'The last ball',
    };
  }

  /// Removes the newest entry and says which one it was.
  void _undo({bool quiet = false}) {
    final what = _describeLast();
    _fire(_c.undo());
    if (!quiet && what != null) _toast('Undid: $what');
  }

  void _resetNextBall() => setState(() {
        _delivery = Delivery.legal;
        _extra = RunType.none;
        _chosenBowler = null;
      });

  String _bowlerForNext(InningsResult r) => _chosenBowler ?? r.currentBowlerId ?? r.setup.bowlingLineup.first;

  void _tapRuns(InningsResult r, int n) {
    final bowler = _bowlerForNext(r);
    final delivery = _delivery;
    final extra = _extra;
    _fire(_c.addBall((seq) => scoredBall(
          seq: seq,
          bowlerId: bowler,
          rules: _c.rules,
          delivery: delivery,
          extra: extra,
          runsTapped: n,
        )));
    _resetNextBall();
  }

  Future<void> _tapWicket(InningsResult r) async {
    final entry = await showWicketSheet(
      context,
      innings: r,
      delivery: _delivery,
      extraRunsAreWide: _delivery == Delivery.wide,
      nameOf: _c.nameOf,
    );
    if (entry == null || !mounted) return;
    final bowler = _bowlerForNext(r);
    final delivery = _delivery;
    final extra = _extra;
    _fire(_c.addBall((seq) => scoredBall(
          seq: seq,
          bowlerId: bowler,
          rules: _c.rules,
          delivery: delivery,
          extra: extra,
          runsTapped: entry.runs,
          wicket: entry.wicket,
        )));
    _resetNextBall();
  }

  Future<void> _retire(InningsResult r) async {
    final crease = [if (r.strikerId != null) r.strikerId!, if (r.nonStrikerId != null) r.nonStrikerId!];
    final who = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Who retires?'),
        children: [for (final id in crease) SimpleDialogOption(onPressed: () => Navigator.pop(context, id), child: Text(_c.nameOf(id)))],
      ),
    );
    if (who == null || !mounted) return;
    final incoming = availableBatters(r).where((id) => id != who).toList();
    String? next;
    if (incoming.isNotEmpty) {
      next = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Next batter'),
          children: [for (final id in incoming) SimpleDialogOption(onPressed: () => Navigator.pop(context, id), child: Text(_c.nameOf(id)))],
        ),
      );
      if (next == null) return;
    }
    _fire(_c.addEvent(CricketEvent.retire(seq: 0, retiredBatterId: who, newBatterId: next)));
    _saidWithUndo('${_c.nameOf(who)} retired${next == null ? '' : ' — ${_c.nameOf(next)} comes in'}');
  }

  Future<void> _endInnings(MatchScoringState s) async {
    if (s.hasBlockingFlags) {
      _say('Some balls still need review — fix or accept them first.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this innings now?'),
        content: const Text('Use this for a declaration, time up, or a shortened match.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('End innings')),
        ],
      ),
    );
    if (ok == true) _fire(_c.addEvent(const CricketEvent.endInnings(0)));
  }

  Future<void> _saveResult() async {
    final state = _c.state;
    final match = _c.match;
    if (state != null && state.result != null && match != null) {
      final knockout = match.stage == MatchStage.knockout;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save this result?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(state.result!.text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: AppSpacing.sm),
              for (final v in state.innings)
                Text('${_c.teamName(v.battingSide)}: ${v.result.scoreText} (${v.result.oversText} ov)'),
              const SizedBox(height: AppSpacing.sm),
              Text(knockout
                  ? 'The winner moves on to the next round of the bracket. Viewers see the result at once.'
                  : 'This counts in the points table. Viewers see the result at once.'),
              const Text('You can still reopen the match to fix a ball.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save result')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      final problem = await _c.finish();
      if (problem != null) _say(problem);
    } catch (e) {
      _say('$e');
    }
  }

  Future<void> _reopen() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reopen this match?'),
        content: const Text('It goes back to live so balls can be edited. It stops counting in the table '
            'until you save the result again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reopen')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final problem = await _c.reopen();
      if (problem != null) _say(problem);
    } catch (e) {
      _say('$e');
    }
  }

  void _openBalls() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CricketBallListScreen(controller: _c)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final match = _c.match;
        final state = _c.state;
        return Scaffold(
          appBar: AppBar(
            title: Text(match == null ? 'Cricket scoring' : '${_c.nameA} vs ${_c.nameB}'),
            actions: [
              if (state != null && state.innings.isNotEmpty)
                IconButton(
                  tooltip: 'All balls — edit',
                  icon: Badge(
                    isLabelVisible: state.hasBlockingFlags,
                    label: Text('${state.blockingFlags.length}'),
                    child: const Icon(Icons.list_alt_outlined),
                  ),
                  onPressed: _openBalls,
                ),
            ],
          ),
          body: _body(context),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    if (_c.error != null) {
      return _Notice(
        icon: Icons.error_outline,
        text: 'Couldn\'t read the ball log: ${_c.error}\n\n'
            'If this says permission-denied, the Firestore rules for live scoring haven\'t been deployed yet.',
      );
    }
    if (!_c.ready) {
      return _c.matchLoaded && _c.match == null
          ? const _Notice(icon: Icons.search_off, text: 'This match no longer exists.')
          : const Center(child: CircularProgressIndicator());
    }
    final state = _c.state!;
    switch (state.phase) {
      case ScoringPhase.needsSetup:
        return _Notice(
          icon: Icons.settings_outlined,
          text: state.problem ?? 'Finish match setup first.',
          action: FilledButton(onPressed: () => context.pop(), child: const Text('Back to match setup')),
        );
      case ScoringPhase.broken:
        return _Notice(
          icon: Icons.warning_amber_rounded,
          text: state.problem ?? 'The match setup no longer fits the scoring.',
          action: FilledButton(onPressed: () => context.pop(), child: const Text('Back to match setup')),
        );
      case ScoringPhase.awaitingInnings:
        return _StartInnings(controller: _c, state: state, onReview: _openBalls);
      case ScoringPhase.scoring:
        return _scoring(context, state);
      case ScoringPhase.finished:
        return _finished(context, state);
    }
  }

  // ---- scoring ----------------------------------------------------------

  Widget _scoring(BuildContext context, MatchScoringState state) {
    final v = state.current!;
    final r = v.result;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final needBowler = needsNewBowler(r) && _chosenBowler == null;
    final bowlerId = needBowler ? null : _bowlerForNext(r);
    final bowler = bowlerId == null ? null : r.bowlers[bowlerId];
    final batName = _c.teamName(v.battingSide);
    final chase = chaseText(r, batName);

    Widget batterRow(String? id, {required bool onStrike}) {
      if (id == null) return const SizedBox.shrink();
      final b = r.batters[id]!;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text('${onStrike ? '▶ ' : '    '}${_c.nameOf(id)}',
                  style: textTheme.bodyLarge?.copyWith(fontWeight: onStrike ? FontWeight.w700 : null)),
            ),
            Text('${b.runs} (${b.balls})  4s ${b.fours}  6s ${b.sixes}', style: textTheme.bodyMedium),
          ],
        ),
      );
    }

    final overBalls = r.overs.isEmpty ? const <BallRecord>[] : r.overs.last.balls;
    final overLabel = r.overs.isNotEmpty && r.overs.last.complete ? 'Last over' : 'This over';

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Card(
                color: scheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(batName, style: textTheme.titleMedium),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(r.scoreText, style: textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text('(${r.oversText} / ${r.maxBalls ~/ r.rules.ballsPerOver} ov)',
                                style: textTheme.titleMedium),
                          ),
                        ],
                      ),
                      Text('Run rate ${r.runRate.toStringAsFixed(2)}', style: textTheme.bodySmall),
                      if (chase != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(chase, style: textTheme.titleSmall),
                        if (r.requiredRunRate != null)
                          Text('Required rate ${r.requiredRunRate!.toStringAsFixed(2)}', style: textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
              ),
              if (state.hasBlockingFlags)
                _ReviewBanner(count: state.blockingFlags.length, onTap: _openBalls),
              if (r.freeHitNext)
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Text('FREE HIT — only a run out is possible', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      batterRow(r.strikerId, onStrike: true),
                      batterRow(r.nonStrikerId, onStrike: false),
                      const Divider(),
                      Row(
                        children: [
                          Expanded(
                            child: Text(bowlerId == null ? 'Bowler: pick one' : 'Bowler: ${_c.nameOf(bowlerId)}',
                                style: textTheme.bodyLarge),
                          ),
                          if (bowler != null)
                            Flexible(
                              child: Text(
                                '${bowler.oversText} ov · ${bowler.runsConceded} ${bowler.runsConceded == 1 ? 'run' : 'runs'} · ${bowler.wickets} ${bowler.wickets == 1 ? 'wkt' : 'wkts'}',
                                style: textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                      if (overBalls.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Align(alignment: Alignment.centerLeft, child: Text(overLabel, style: textTheme.bodySmall)),
                        const SizedBox(height: AppSpacing.xs),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final b in overBalls)
                                CircleAvatar(
                                  radius: 15,
                                  backgroundColor: b.isWicket ? AppColors.liveRed : scheme.surfaceContainerHighest,
                                  child: Text(b.token,
                                      style: TextStyle(
                                          fontSize: b.token.length > 3 ? 9 : 12,
                                          fontWeight: FontWeight.w700,
                                          color: b.isWicket ? Colors.white : null)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (needBowler) _bowlerPicker(r),
            ],
          ),
        ),
        if (!needBowler) _controls(context, r, state),
      ],
    );
  }

  Widget _bowlerPicker(InningsResult r) {
    final textTheme = Theme.of(context).textTheme;
    final choices = bowlerChoices(r);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.balls.isEmpty ? 'Who bowls the first over?' : 'Over finished — who bowls next?', style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final b in choices)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(_c.nameOf(b.id)),
                subtitle: Text(switch (b.issue) {
                  BowlerIssue.none => '${b.oversText} overs so far',
                  BowlerIssue.justBowled => 'Bowled the last over',
                  BowlerIssue.overLimit => 'Already at the over limit',
                }),
                trailing: b.issue == BowlerIssue.none
                    ? null
                    : const Icon(Icons.warning_amber_rounded, color: AppColors.warningAmber),
                onTap: () async {
                  if (b.issue != BowlerIssue.none) {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Pick ${_c.nameOf(b.id)} anyway?'),
                        content: Text(b.issue == BowlerIssue.justBowled
                            ? 'They bowled the last over. The same bowler can\'t bowl two overs in a row.'
                            : 'They have already bowled the most overs allowed.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Pick anyway')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                  }
                  setState(() => _chosenBowler = b.id);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _modeHint() {
    final parts = <String>[
      if (_delivery == Delivery.wide) 'Wide',
      if (_delivery == Delivery.noBall) 'No ball',
      if (_extra == RunType.bye) 'Byes',
      if (_extra == RunType.legBye) 'Leg byes',
    ];
    if (parts.isEmpty) return 'Tap the runs scored off this ball';
    final what = _delivery == Delivery.wide ? 'extra runs run' : (_extra == RunType.none ? 'runs off the bat' : 'runs');
    return '${parts.join(' + ')} — now tap the $what (0 for none)';
  }

  Widget _controls(BuildContext context, InningsResult r, MatchScoringState state) {
    final scheme = Theme.of(context).colorScheme;
    final rules = _c.rules;

    Widget key(String text, VoidCallback onTap, {Color? color, Color? fg}) => Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            height: 56,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: fg),
              onPressed: onTap,
              child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          ),
        );

    return Material(
      elevation: 8,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  FilterChip(
                    label: const Text('Wide'),
                    selected: _delivery == Delivery.wide,
                    onSelected: (on) => setState(() {
                      _delivery = on ? Delivery.wide : Delivery.legal;
                      if (on) _extra = RunType.none;
                    }),
                  ),
                  FilterChip(
                    label: const Text('No ball'),
                    selected: _delivery == Delivery.noBall,
                    onSelected: (on) => setState(() => _delivery = on ? Delivery.noBall : Delivery.legal),
                  ),
                  if (rules.byesAllowed)
                    FilterChip(
                      label: const Text('Bye'),
                      selected: _extra == RunType.bye,
                      onSelected: _delivery == Delivery.wide
                          ? null
                          : (on) => setState(() => _extra = on ? RunType.bye : RunType.none),
                    ),
                  if (rules.legByesAllowed)
                    FilterChip(
                      label: const Text('Leg bye'),
                      selected: _extra == RunType.legBye,
                      onSelected: _delivery == Delivery.wide
                          ? null
                          : (on) => setState(() => _extra = on ? RunType.legBye : RunType.none),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(_modeHint(), style: Theme.of(context).textTheme.bodySmall),
              ),
              Row(children: [
                for (final n in const [0, 1, 2, 3]) Expanded(child: key('$n', () => _tapRuns(r, n))),
              ]),
              Row(children: [
                Expanded(child: key('4', () => _tapRuns(r, 4))),
                Expanded(child: key('5', () => _tapRuns(r, 5))),
                Expanded(child: key('6', () => _tapRuns(r, 6))),
                Expanded(
                  child: key('W', () => _tapWicket(r), color: AppColors.liveRed, fg: Colors.white),
                ),
              ]),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _undo,
                      icon: const Icon(Icons.undo),
                      label: const Text('Undo'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _openBalls,
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Edit balls'),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) {
                      switch (v) {
                        case 'swap':
                          _fire(_c.addEvent(const CricketEvent.swapStrike(0)));
                          _saidWithUndo('Batters swapped ends');
                        case 'bowler':
                          setState(() => _chosenBowler = null);
                          _changeBowler(r);
                        case 'retire':
                          _retire(r);
                        case 'dead':
                          _fire(_c.addBall((seq) =>
                              CricketEvent(seq: seq, bowlerId: _bowlerForNext(r), delivery: Delivery.deadBall)));
                          _saidWithUndo('Dead ball recorded — it will be bowled again');
                        case 'end':
                          _endInnings(state);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'swap', child: Text('Swap batters')),
                      PopupMenuItem(value: 'bowler', child: Text('Change bowler')),
                      PopupMenuItem(value: 'retire', child: Text('Retire a batter')),
                      PopupMenuItem(value: 'dead', child: Text('Dead ball')),
                      PopupMenuItem(value: 'end', child: Text('End innings')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeBowler(InningsResult r) async {
    final choices = bowlerChoices(r);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text('Change bowler for the next ball', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final b in choices)
              ListTile(
                title: Text(_c.nameOf(b.id)),
                subtitle: Text('${b.oversText} overs'),
                onTap: () => Navigator.pop(context, b.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _chosenBowler = picked);
  }

  // ---- finished ---------------------------------------------------------

  Widget _finished(BuildContext context, MatchScoringState state) {
    final textTheme = Theme.of(context).textTheme;
    final res = state.result;
    final saved = _c.isCompleted;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(saved ? 'Result saved' : 'Match over', style: textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(res?.text ?? '', style: textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.md),
                for (final v in state.innings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${_c.teamName(v.battingSide)}: ${v.result.scoreText} (${v.result.oversText} ov)',
                      style: textTheme.bodyLarge,
                    ),
                  ),
                if (res?.winner == CricketWinner.tie)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.sm),
                    child: Text('Level scores. In a league match a tie gives one point each.'),
                  ),
              ],
            ),
          ),
        ),
        if (state.hasBlockingFlags && !saved) _ReviewBanner(count: state.blockingFlags.length, onTap: _openBalls),
        if (!saved)
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Save result'),
            onPressed: state.hasBlockingFlags ? null : _saveResult,
          )
        else
          OutlinedButton.icon(
            icon: const Icon(Icons.lock_open),
            label: const Text('Reopen to edit'),
            onPressed: _reopen,
          ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          icon: const Icon(Icons.list_alt_outlined),
          label: const Text('See all balls'),
          onPressed: _openBalls,
        ),
        if (!saved) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            icon: const Icon(Icons.undo),
            label: const Text('Undo the last ball'),
            onPressed: _undo,
          ),
        ],
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Notice({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: AppSpacing.md),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: AppSpacing.md), action!],
          ],
        ),
      ),
    );
  }
}

class _ReviewBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ReviewBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.warningAmber.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.warningAmber),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('$count ball${count == 1 ? '' : 's'} need review after an edit. Tap to fix or accept.'),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pick the two openers and start the innings (or the second innings after
/// the break).
class _StartInnings extends StatefulWidget {
  final CricketScoringController controller;
  final MatchScoringState state;
  final VoidCallback onReview;

  const _StartInnings({required this.controller, required this.state, required this.onReview});

  @override
  State<_StartInnings> createState() => _StartInningsState();
}

class _StartInningsState extends State<_StartInnings> {
  String? _striker;
  String? _nonStriker;
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = widget.state;
    final textTheme = Theme.of(context).textTheme;
    final index = s.nextInningsIndex;
    final first = c.match!.toss!.battingFirstSide;
    final side = index.isEven ? first : otherSide(first);
    final lineup = side == 'A' ? c.match!.lineupA : c.match!.lineupB;
    _striker ??= lineup.isNotEmpty ? lineup[0] : null;
    _nonStriker ??= lineup.length > 1 ? lineup[1] : null;
    final target = index == 1 ? s.innings.first.result.runs + 1 : null;
    final rules = c.rules;
    final toss = c.match!.toss!;

    Widget picker(String label, String? value, ValueChanged<String?> onChanged) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: DropdownButtonFormField<String>(
            initialValue: value,
            decoration: InputDecoration(labelText: label),
            items: [for (final id in lineup) DropdownMenuItem(value: id, child: Text(c.nameOf(id)))],
            onChanged: onChanged,
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (s.hasBlockingFlags) _ReviewBanner(count: s.blockingFlags.length, onTap: widget.onReview),
        if (index == 1)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Innings break', style: textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${c.teamName(first)}: ${s.innings.first.result.scoreText} (${s.innings.first.result.oversText} ov)',
                    style: textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text('${c.teamName(side)} need $target runs in ${rules.overs} overs.'),
                ],
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(index == 0 ? 'Start the match' : 'Start the second innings', style: textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                if (index == 0)
                  Text(
                    '${c.teamName(toss.winner)} won the toss and chose to ${toss.elected}. '
                    '${c.teamName(side)} bat first.',
                  ),
                const SizedBox(height: AppSpacing.md),
                Text('${c.teamName(side)} openers', style: textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                picker('On strike', _striker, (v) => setState(() => _striker = v)),
                picker('At the other end', _nonStriker, (v) => setState(() => _nonStriker = v)),
                if (_striker != null && _striker == _nonStriker)
                  Text('Pick two different players.',
                      style: textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.sports_cricket),
                    label: Text(_starting ? 'Starting…' : 'Start innings'),
                    onPressed: _starting || _striker == null || _nonStriker == null || _striker == _nonStriker
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() => _starting = true);
                            try {
                              // Not awaited past the local write: works offline.
                              c
                                  .startInnings(InningsStart(strikerId: _striker!, nonStrikerId: _nonStriker!))
                                  .catchError((Object e) => messenger.showSnackBar(SnackBar(content: Text('$e'))));
                            } finally {
                              if (mounted) setState(() => _starting = false);
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
