import 'package:flutter/material.dart';

import '../../../core/cricket/commentary_text.dart';
import '../../../core/cricket/cricket_event.dart';
import '../../../core/cricket/edit_preview.dart';
import '../../../core/cricket/cricket_rules.dart';
import '../../../core/cricket/innings_replay.dart';
import '../../../core/cricket/match_display.dart';
import '../../../core/cricket/match_scoring.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_spacing.dart';
import 'scoring_controller.dart';
import 'wicket_form.dart';

/// Edit one recorded ball. Only this ball's inputs change; every later ball
/// keeps what the scorer entered and is re-derived by the replay — anything
/// that no longer makes sense afterwards shows up as a ⚠ for review.
Future<void> showBallEditor(BuildContext context, CricketScoringController c, LoggedEvent ev) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      builder: (context, scroll) => _BallEditor(controller: c, ev: ev, scroll: scroll),
    ),
  );
}

class _BallEditor extends StatefulWidget {
  final CricketScoringController controller;
  final LoggedEvent ev;
  final ScrollController scroll;

  const _BallEditor({required this.controller, required this.ev, required this.scroll});

  @override
  State<_BallEditor> createState() => _BallEditorState();
}

class _BallEditorState extends State<_BallEditor> {
  late Delivery _delivery;
  late RunType _runType;
  late int _runs;
  late Boundary _boundary;
  late bool _overthrow;
  late int _completed;
  String? _bowler;
  late bool _hasWicket;
  Wicket? _wicket;
  bool _saving = false;

  CricketEvent get _e => widget.ev.event;
  CricketScoringController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _delivery = _e.delivery;
    _runType = _e.runType;
    _runs = _e.runs;
    _boundary = _e.boundary;
    _overthrow = _e.completedRunsOverride != null;
    _completed = _e.completedRunsOverride ?? 0;
    _bowler = _e.bowlerId;
    _hasWicket = _e.wicket != null;
    _wicket = _e.wicket;
  }

  int get _defaultCompleted => _boundary != Boundary.none ? 0 : _runs;

  int? _boundaryValue(Boundary b) => switch (b) {
        Boundary.four => _c.rules.boundaryFour,
        Boundary.six => _c.rules.boundarySix,
        Boundary.none => null,
      };

  /// Runs changed with the + / − buttons. A boundary is the ball reaching the
  /// rope for 4 or 6; if the runs drop below that, the ball can no longer be a
  /// boundary — it was run — so the boundary is cleared. (Left on, the app
  /// would treat the runs as "no one ran", and the strike would never change.)
  void _setRuns(int n) => setState(() {
        _runs = n;
        final v = _boundaryValue(_boundary);
        if (v != null && n < v) _boundary = Boundary.none;
        if (n > 0 && _runType == RunType.none && _delivery != Delivery.wide) _runType = RunType.bat;
        if (_overthrow) _completed = _defaultCompleted;
      });

  /// Choosing Four / Six sets the runs to what a boundary is worth.
  void _setBoundary(Boundary b) => setState(() {
        _boundary = b;
        final v = _boundaryValue(b);
        if (v != null && _runs < v) {
          _runs = v;
          if (_runType == RunType.none && _delivery != Delivery.wide) _runType = RunType.bat;
        }
        if (_overthrow) _completed = _defaultCompleted;
      });

  CricketEvent _built() => CricketEvent(
        seq: _e.seq,
        bowlerId: _bowler,
        delivery: _delivery,
        runType: _delivery == Delivery.wide || _delivery == Delivery.deadBall ? RunType.none : _runType,
        runs: _delivery == Delivery.deadBall ? 0 : _runs,
        boundary: _delivery == Delivery.deadBall ? Boundary.none : _boundary,
        completedRunsOverride: _overthrow ? _completed : null,
        wicket: _hasWicket ? _wicket : null,
      );

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final state = _c.state;
    final view = state?.innings.where((i) => i.index == widget.ev.innings).firstOrNull;
    final result = view?.result;
    final record = result?.balls.where((b) => b.seq == _e.seq).firstOrNull;
    final flags = result?.flagsFor(_e.seq) ?? const <ReviewFlag>[];
    final batting = result?.setup.battingLineup ?? const <String>[];
    final bowling = result?.setup.bowlingLineup ?? const <String>[];
    final nameOf = _c.nameOf;

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
          child: Text(t, style: textTheme.titleSmall),
        );

    final noExtraType = _delivery == Delivery.wide || _delivery == Delivery.deadBall;

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
      children: [
        Text(record == null ? 'Edit ball' : 'Edit ball — ${ballPlace(record)}', style: textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Only this ball changes. Later balls keep what you entered; the score, strike and overs are worked out again.',
          style: textTheme.bodySmall,
        ),
        if (record != null) ...[
          const SizedBox(height: AppSpacing.md),
          _WhoCard(
            bowler: record.bowlerId == null ? null : nameOf(record.bowlerId!),
            striker: record.strikerId == null ? null : nameOf(record.strikerId!),
            nonStriker: record.nonStrikerId == null ? null : nameOf(record.nonStrikerId!),
            now: ballCommentary(record, nameOf, freeHitRule: _c.rules.freeHit),
          ),
        ],
        for (final f in flags)
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.warningAmber.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(f.acknowledged ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                    color: AppColors.warningAmber),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(f.message)),
                if (!f.acknowledged)
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => _run(() => _c.acknowledge(_e.seq, {..._e.acknowledgedFlags, f.code.name})),
                    child: const Text('Accept as is'),
                  ),
              ],
            ),
          ),
        label('Delivery'),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final (d, t) in const [
              (Delivery.legal, 'Normal'),
              (Delivery.wide, 'Wide'),
              (Delivery.noBall, 'No ball'),
              (Delivery.deadBall, 'Dead ball'),
            ])
              ChoiceChip(
                label: Text(t),
                selected: _delivery == d,
                onSelected: (_) => setState(() {
                  // A wide's runs are extras and a dead ball has none, so moving to or from
                  // those starts the run fields afresh (the old values stay in the audit trail).
                  // Normal ↔ No ball keeps the runs: both can have runs off the bat.
                  final resets = d == Delivery.wide || d == Delivery.deadBall || _delivery == Delivery.wide;
                  if (d != _delivery && resets) {
                    _runs = 0;
                    _runType = RunType.none;
                    _boundary = Boundary.none;
                    _overthrow = false;
                    _completed = 0;
                  }
                  if (d == Delivery.deadBall) _hasWicket = false;
                  _delivery = d;
                }),
              ),
          ],
        ),
        if (_delivery != Delivery.deadBall) ...[
          label(_delivery == Delivery.wide ? 'Extra runs run (on top of the wide)' : 'Runs'),
          if (!noExtraType)
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final (t, text) in [
                  (RunType.none, 'None'),
                  (RunType.bat, 'Off the bat'),
                  if (_c.rules.byesAllowed || _runType == RunType.bye) (RunType.bye, 'Byes'),
                  if (_c.rules.legByesAllowed || _runType == RunType.legBye) (RunType.legBye, 'Leg byes'),
                ])
                  ChoiceChip(
                    label: Text(text),
                    selected: _runType == t,
                    onSelected: (_) => setState(() {
                      _runType = t;
                      if (t == RunType.none) {
                        _runs = 0;
                        _boundary = Boundary.none;
                      }
                    }),
                  ),
              ],
            ),
          Row(
            children: [
              IconButton.outlined(
                onPressed: _runs > 0 ? () => _setRuns(_runs - 1) : null,
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text('$_runs', style: textTheme.headlineSmall),
              ),
              IconButton.outlined(
                onPressed: _runs < 12 ? () => _setRuns(_runs + 1) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          label('Reached the boundary?'),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final (b, t) in const [(Boundary.none, 'No'), (Boundary.four, 'Four'), (Boundary.six, 'Six')])
                ChoiceChip(
                  label: Text(t),
                  selected: _boundary == b,
                  onSelected: (_) => _setBoundary(b),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Four / Six = the ball reached the rope, nobody ran. A boundary never changes who is on strike. '
              'If the batters ran the runs, choose No.',
              style: textTheme.bodySmall,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Runs actually run were different'),
            subtitle: const Text('Overthrows or a short run. Only these decide who is on strike next.'),
            value: _overthrow,
            onChanged: (v) => setState(() {
              _overthrow = v;
              _completed = _defaultCompleted;
            }),
          ),
          if (_overthrow)
            Row(
              children: [
                const Text('Runs run:'),
                IconButton.outlined(
                  onPressed: _completed > 0 ? () => setState(() => _completed--) : null,
                  icon: const Icon(Icons.remove),
                ),
                Text('$_completed', style: textTheme.titleLarge),
                IconButton.outlined(
                  onPressed: () => setState(() => _completed++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
        ],
        label('Bowler'),
        DropdownButtonFormField<String>(
          initialValue: bowling.contains(_bowler) ? _bowler : null,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: [for (final id in bowling) DropdownMenuItem(value: id, child: Text(nameOf(id)))],
          onChanged: (v) => setState(() => _bowler = v),
        ),
        if (_delivery != Delivery.deadBall) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('A batter is out on this ball'),
            value: _hasWicket,
            onChanged: (v) => setState(() {
              _hasWicket = v;
              if (!v) _wicket = null;
            }),
          ),
          if (_hasWicket)
            WicketForm(
              key: ValueKey('${_e.seq}-wicket'),
              rules: _c.rules,
              kindChoices: WicketKind.values,
              outChoices: batting,
              incomingChoices: batting,
              fielderChoices: bowling,
              strikerId: record?.strikerId,
              completedRuns: _overthrow ? _completed : _defaultCompleted,
              needsIncoming: true,
              nameOf: nameOf,
              initial: _e.wicket,
              onChanged: (w) => WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _wicket != w) setState(() => _wicket = w);
              }),
            ),
        ],
        if (view != null && result != null) ...[
          const SizedBox(height: AppSpacing.md),
          _PreviewCard(
            preview: _hasWicket && _wicket == null
                ? null
                : previewEdit(
                    rules: _c.rules,
                    setup: result.setup,
                    events: view.events,
                    edited: _built(),
                    nameOf: nameOf,
                  ),
            waitingForWicket: _hasWicket && _wicket == null,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _saving || (_hasWicket && _wicket == null)
              ? null
              : () => _run(() => _c.editBall(widget.ev, _built())),
          child: Text(_saving ? 'Saving…' : 'Save ball'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.liveRed),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete this ball'),
          onPressed: _saving ? null : () => _confirmDelete(),
        ),
      ],
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this ball?'),
        content: const Text('Later balls stay as they are; the score and strike are worked out again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await _run(() => _c.deleteBall(widget.ev));
  }
}

/// Who was involved in the ball being edited, in words — the batter and the
/// bowler are named by role so the two can't be mixed up.
class _WhoCard extends StatelessWidget {
  final String? bowler;
  final String? striker;
  final String? nonStriker;
  final String now;

  const _WhoCard({required this.bowler, required this.striker, required this.nonStriker, required this.now});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget row(String role, String? name) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: [
              SizedBox(width: 118, child: Text(role, style: textTheme.bodySmall)),
              Expanded(child: Text(name ?? '—', style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('Bowler', bowler),
          row('Batter on strike', striker),
          row('Other batter', nonStriker),
          const SizedBox(height: AppSpacing.xs),
          Text('Recorded as: $now', style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// "If you save this" — the effect of the edit as it stands in the form.
class _PreviewCard extends StatelessWidget {
  final EditPreview? preview;
  final bool waitingForWicket;

  const _PreviewCard({required this.preview, required this.waitingForWicket});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final warns = preview?.warns ?? false;
    final color = warns ? AppColors.warningAmber : Theme.of(context).colorScheme.primary;
    final lines = waitingForWicket
        ? const ['Fill in the wicket details below to see what changes.']
        : (preview?.lines ?? const ['This change can\'t be previewed.']);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('If you save this', style: textTheme.labelLarge?.copyWith(color: color)),
          const SizedBox(height: 2),
          for (final l in lines) Text(l),
        ],
      ),
    );
  }
}
