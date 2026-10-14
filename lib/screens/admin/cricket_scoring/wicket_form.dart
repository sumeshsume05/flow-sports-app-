import 'package:flutter/material.dart';

import '../../../core/cricket/cricket_event.dart';
import '../../../core/cricket/cricket_rules.dart';
import '../../../core/design/app_spacing.dart';

/// The fields of a dismissal, shared by the live wicket sheet and the
/// edit-a-ball form. It owns its own selections and reports a complete
/// [Wicket] through [onChanged] whenever one of them changes.
///
/// [strikerId] is the batter who faced the ball (it decides the default end
/// for the incoming batter); [completedRuns] is how many runs were run before
/// the dismissal (it matters for run-outs: the incoming batter takes the end
/// the dismissed one was running to).
class WicketForm extends StatefulWidget {
  final CricketRules rules;
  final List<WicketKind> kindChoices;
  final List<String> outChoices;
  final List<String> incomingChoices;
  final List<String> fielderChoices;
  final String? strikerId;
  final int completedRuns;

  /// False when this wicket ends the innings (nobody comes in).
  final bool needsIncoming;
  final String Function(String id) nameOf;
  final Wicket? initial;
  final ValueChanged<Wicket?> onChanged;

  const WicketForm({
    super.key,
    required this.rules,
    required this.kindChoices,
    required this.outChoices,
    required this.incomingChoices,
    required this.fielderChoices,
    required this.strikerId,
    required this.completedRuns,
    required this.needsIncoming,
    required this.nameOf,
    required this.onChanged,
    this.initial,
  });

  @override
  State<WicketForm> createState() => _WicketFormState();
}

class _WicketFormState extends State<WicketForm> {
  WicketKind? _kind;
  String? _out;
  String? _fielder;
  bool _crossed = false;
  String? _incoming;
  NewBatterEnd _end = NewBatterEnd.onStrike;
  bool _endTouched = false;

  bool get _strikerOnly => _kind?.strikerOnly ?? false;

  @override
  void initState() {
    super.initState();
    final w = widget.initial;
    if (w != null) {
      _kind = w.kind;
      _out = w.outBatterId;
      _fielder = w.fielderId;
      _crossed = w.crossed;
      _incoming = w.newBatterId;
      _end = w.newBatterEnd;
      _endTouched = true;
    } else {
      _kind = widget.kindChoices.isEmpty ? null : widget.kindChoices.first;
      _out = widget.strikerId ?? (widget.outChoices.isEmpty ? null : widget.outChoices.first);
      _applyDefaultEnd();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  void _applyDefaultEnd() {
    if (_endTouched || _kind == null || _out == null) return;
    _end = Wicket.defaultNewBatterEnd(
      kind: _kind!,
      outBatterWasStriker: _out == widget.strikerId,
      completedRuns: widget.completedRuns,
      crossed: _crossed,
    );
  }

  @override
  void didUpdateWidget(WicketForm old) {
    super.didUpdateWidget(old);
    if (old.completedRuns != widget.completedRuns) {
      _applyDefaultEnd();
      _emit();
    }
  }

  void _emit() {
    if (!mounted) return;
    final kind = _kind;
    final out = _strikerOnly ? (widget.strikerId ?? _out) : _out;
    widget.onChanged(kind == null || out == null
        ? null
        : Wicket(
            kind: kind,
            outBatterId: out,
            fielderId: _showFielder ? _fielder : null,
            crossed: kind == WicketKind.caught && _crossed,
            newBatterId: widget.needsIncoming ? _incoming : null,
            newBatterEnd: _end,
          ));
  }

  bool get _showFielder =>
      _kind == WicketKind.caught || _kind == WicketKind.runOut || _kind == WicketKind.stumped;

  void _change(VoidCallback fn) {
    setState(() {
      fn();
      _applyDefaultEnd();
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final nameOf = widget.nameOf;
    final out = _strikerOnly ? (widget.strikerId ?? _out) : _out;

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
          child: Text(t, style: textTheme.titleSmall),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('How out'),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final k in widget.kindChoices)
              ChoiceChip(
                label: Text(k.label),
                selected: _kind == k,
                onSelected: (_) => _change(() => _kind = k),
              ),
          ],
        ),
        if (widget.kindChoices.isEmpty)
          const Text('No dismissal is possible on this ball with this match\'s rules.'),
        if (_kind != null && !_strikerOnly) ...[
          label('Who is out'),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final id in widget.outChoices)
                ChoiceChip(
                  label: Text(nameOf(id)),
                  selected: _out == id,
                  onSelected: (_) => _change(() => _out = id),
                ),
            ],
          ),
        ] else if (_kind != null && out != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text('${nameOf(out)} is out.', style: textTheme.bodyMedium),
          ),
        if (_kind == WicketKind.caught)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Batters had crossed'),
            value: _crossed,
            onChanged: (v) => _change(() => _crossed = v),
          ),
        if (_showFielder) ...[
          label('Fielder (optional)'),
          DropdownButtonFormField<String?>(
            initialValue: widget.fielderChoices.contains(_fielder) ? _fielder : null,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('—')),
              for (final id in widget.fielderChoices) DropdownMenuItem(value: id, child: Text(nameOf(id))),
            ],
            onChanged: (v) => _change(() => _fielder = v),
          ),
        ],
        if (widget.needsIncoming && widget.incomingChoices.isNotEmpty) ...[
          label('Next batter'),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final id in widget.incomingChoices)
                ChoiceChip(
                  label: Text(nameOf(id)),
                  selected: _incoming == id,
                  onSelected: (_) => _change(() => _incoming = id),
                ),
            ],
          ),
          label('Next batter stands'),
          SegmentedButton<NewBatterEnd>(
            segments: const [
              ButtonSegment(value: NewBatterEnd.onStrike, label: Text('On strike')),
              ButtonSegment(value: NewBatterEnd.offStrike, label: Text('Other end')),
            ],
            selected: {_end},
            onSelectionChanged: (s) => _change(() {
              _end = s.first;
              _endTouched = true;
            }),
          ),
        ] else if (widget.needsIncoming && widget.incomingChoices.isEmpty && widget.kindChoices.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: Text('No one is left to come in — the other batter carries on alone.'),
          ),
      ],
    );
  }
}
