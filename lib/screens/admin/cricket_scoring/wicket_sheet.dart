import 'package:flutter/material.dart';

import '../../../core/cricket/cricket_event.dart';
import '../../../core/cricket/cricket_rules.dart';
import '../../../core/cricket/innings_replay.dart';
import '../../../core/cricket/match_scoring.dart';
import '../../../core/design/app_spacing.dart';
import 'wicket_form.dart';

/// What the scorer entered in the wicket sheet.
class WicketEntry {
  final Wicket wicket;

  /// Runs completed before the dismissal (e.g. a run-out going for a second).
  final int runs;

  const WicketEntry(this.wicket, this.runs);
}

/// Dismissals possible on this kind of delivery under this match's rules.
List<WicketKind> wicketKindsFor(CricketRules rules, Delivery delivery, bool freeHit) {
  Iterable<WicketKind> kinds = WicketKind.values.where(rules.allowedWickets.contains);
  if (delivery == Delivery.wide) kinds = kinds.where(wicketKindsAllowedOnWide.contains);
  if (delivery == Delivery.noBall || freeHit) kinds = kinds.where(wicketKindsAllowedOnNoBall.contains);
  return kinds.toList();
}

/// Bottom sheet for "Wicket": how out, who, fielder, runs run, who comes in.
/// Returns null when cancelled.
Future<WicketEntry?> showWicketSheet(
  BuildContext context, {
  required InningsResult innings,
  required Delivery delivery,
  required bool extraRunsAreWide,
  required String Function(String id) nameOf,
}) {
  return showModalBottomSheet<WicketEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _WicketSheet(
      innings: innings,
      delivery: delivery,
      extraRunsAreWide: extraRunsAreWide,
      nameOf: nameOf,
    ),
  );
}

class _WicketSheet extends StatefulWidget {
  final InningsResult innings;
  final Delivery delivery;
  final bool extraRunsAreWide;
  final String Function(String id) nameOf;

  const _WicketSheet({
    required this.innings,
    required this.delivery,
    required this.extraRunsAreWide,
    required this.nameOf,
  });

  @override
  State<_WicketSheet> createState() => _WicketSheetState();
}

class _WicketSheetState extends State<_WicketSheet> {
  Wicket? _wicket;
  int _runs = 0;

  @override
  Widget build(BuildContext context) {
    final r = widget.innings;
    final kinds = wicketKindsFor(r.rules, widget.delivery, r.freeHitNext);
    final crease = [if (r.strikerId != null) r.strikerId!, if (r.nonStrikerId != null) r.nonStrikerId!];
    final endsInnings = r.wickets + 1 >= r.maxWickets;
    final incoming = availableBatters(r);
    final needPick = !endsInnings && incoming.isNotEmpty;
    final canSave = _wicket != null && (!needPick || _wicket!.newBatterId != null);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Wicket', style: Theme.of(context).textTheme.titleLarge),
              if (r.freeHitNext)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xs),
                  child: Text('Free hit — only a run out (and similar) is possible.'),
                ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Text(
                  widget.extraRunsAreWide ? 'Extra runs run before the dismissal' : 'Runs completed before the dismissal',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final n in const [0, 1, 2, 3])
                    ChoiceChip(
                      label: Text('$n'),
                      selected: _runs == n,
                      onSelected: (_) => setState(() => _runs = n),
                    ),
                ],
              ),
              WicketForm(
                rules: r.rules,
                kindChoices: kinds,
                outChoices: crease,
                incomingChoices: incoming,
                fielderChoices: r.setup.bowlingLineup,
                strikerId: r.strikerId,
                completedRuns: _runs,
                needsIncoming: !endsInnings,
                nameOf: widget.nameOf,
                onChanged: (w) {
                  // Deferred: the form reports from initState / build paths.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _wicket != w) setState(() => _wicket = w);
                  });
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canSave ? () => Navigator.pop(context, WicketEntry(_wicket!, _runs)) : null,
                  child: const Text('Save wicket'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
