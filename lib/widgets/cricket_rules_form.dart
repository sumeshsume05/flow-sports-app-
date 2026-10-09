import 'package:flutter/material.dart';

import '../core/cricket/cricket_rules.dart';
import '../core/design/app_spacing.dart';

/// Editor for a [CricketRules] — used both for the tournament default
/// (Admin > Cricket rules) and for one match's own copy (match setup).
/// Every change is reported through [onChanged]; the parent decides when to
/// save.
class CricketRulesForm extends StatefulWidget {
  final CricketRules initial;
  final ValueChanged<CricketRules> onChanged;

  const CricketRulesForm({super.key, required this.initial, required this.onChanged});

  @override
  State<CricketRulesForm> createState() => _CricketRulesFormState();
}

class _CricketRulesFormState extends State<CricketRulesForm> {
  late CricketRules _rules = widget.initial;

  void _set(CricketRules rules) {
    setState(() => _rules = rules);
    widget.onChanged(rules);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final r = _rules;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
          child: Text(title, style: textTheme.titleSmall),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Start from a preset, then adjust anything below.', style: textTheme.bodySmall),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            ActionChip(
              avatar: const Icon(Icons.sports_cricket, size: 18),
              label: const Text('Office / tape-ball'),
              onPressed: () => _set(const CricketRules.tapeBall()),
            ),
            ActionChip(
              avatar: const Icon(Icons.sports_baseball_outlined, size: 18),
              label: const Text('T20 hard-ball'),
              onPressed: () => _set(const CricketRules.t20()),
            ),
          ],
        ),
        section('Match size'),
        _StepperRow(
          label: 'Overs per innings',
          value: r.overs,
          min: 1,
          max: 50,
          onChanged: (v) => _set(r.copyWith(overs: v)),
        ),
        _StepperRow(
          label: 'Balls per over',
          value: r.ballsPerOver,
          min: 4,
          max: 8,
          onChanged: (v) => _set(r.copyWith(ballsPerOver: v)),
        ),
        _StepperRow(
          label: 'Players per team',
          value: r.squadSize,
          min: 2,
          max: 11,
          onChanged: (v) => _set(r.copyWith(squadSize: v)),
        ),
        _SwitchRow(
          label: 'Last man stands',
          help: 'The last batter keeps batting alone instead of the innings ending one wicket earlier.',
          value: r.lastManStands,
          onChanged: (v) => _set(r.copyWith(lastManStands: v)),
        ),
        _SwitchRow(
          label: 'Limit overs per bowler',
          value: r.maxOversPerBowler != null,
          onChanged: (v) => _set(v
              ? r.copyWith(maxOversPerBowler: (r.overs / 3).ceil().clamp(1, r.overs))
              : r.copyWith(clearMaxOversPerBowler: true)),
        ),
        if (r.maxOversPerBowler != null)
          _StepperRow(
            label: 'Max overs per bowler',
            value: r.maxOversPerBowler!,
            min: 1,
            max: r.overs,
            onChanged: (v) => _set(r.copyWith(maxOversPerBowler: v)),
          ),
        section('Extras'),
        _StepperRow(
          label: 'Wide: penalty runs',
          value: r.widePenalty,
          min: 0,
          max: 5,
          onChanged: (v) => _set(r.copyWith(widePenalty: v)),
        ),
        _SwitchRow(
          label: 'Wide is bowled again',
          help: 'Off = the wide uses up one of the over\'s balls.',
          value: r.wideReBowl,
          onChanged: (v) => _set(r.copyWith(wideReBowl: v)),
        ),
        _StepperRow(
          label: 'No-ball: penalty runs',
          value: r.noBallPenalty,
          min: 0,
          max: 5,
          onChanged: (v) => _set(r.copyWith(noBallPenalty: v)),
        ),
        _SwitchRow(
          label: 'No-ball is bowled again',
          value: r.noBallReBowl,
          onChanged: (v) => _set(r.copyWith(noBallReBowl: v)),
        ),
        _SwitchRow(
          label: 'Free hit after a no-ball',
          help: 'The next ball can only get the batter out by run out.',
          value: r.freeHit,
          onChanged: (v) => _set(r.copyWith(freeHit: v)),
        ),
        _SwitchRow(
          label: 'Byes allowed',
          value: r.byesAllowed,
          onChanged: (v) => _set(r.copyWith(byesAllowed: v)),
        ),
        _SwitchRow(
          label: 'Leg byes allowed',
          value: r.legByesAllowed,
          onChanged: (v) => _set(r.copyWith(legByesAllowed: v)),
        ),
        section('Ways a batter can be out'),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final kind in WicketKind.values)
              FilterChip(
                label: Text(kind.label),
                selected: r.allowedWickets.contains(kind),
                onSelected: (on) => _set(r.copyWith(
                  allowedWickets: {
                    for (final k in WicketKind.values)
                      if (k == kind ? on : r.allowedWickets.contains(k)) k,
                  },
                )),
              ),
          ],
        ),
        section('League points'),
        _StepperRow(
          label: 'Win',
          value: r.pointsWin,
          min: 0,
          max: 10,
          onChanged: (v) => _set(r.copyWith(pointsWin: v)),
        ),
        _StepperRow(
          label: 'Tie',
          value: r.pointsTie,
          min: 0,
          max: 10,
          onChanged: (v) => _set(r.copyWith(pointsTie: v)),
        ),
        _StepperRow(
          label: 'No result',
          value: r.pointsNoResult,
          min: 0,
          max: 10,
          onChanged: (v) => _set(r.copyWith(pointsNoResult: v)),
        ),
        section('Knockout'),
        _SwitchRow(
          label: 'Super over if a knockout match is tied',
          value: r.superOverOnKnockoutTie,
          onChanged: (v) => _set(r.copyWith(superOverOnKnockoutTie: v)),
        ),
      ],
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _StepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Less',
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 32,
          child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'More',
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String? help;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({required this.label, this.help, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: help == null ? null : Text(help!),
      value: value,
      onChanged: onChanged,
    );
  }
}
