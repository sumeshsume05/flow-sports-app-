import 'package:flutter/material.dart';

import '../../core/cricket/cricket_rules.dart';
import '../../core/design/app_spacing.dart';
import '../../services/firestore_service.dart';
import '../../widgets/cricket_rules_form.dart';

/// Tournament-wide default cricket rules. A match takes its own copy of
/// these when it is generated (schedule, knockout, tie-breaker or manual
/// match), so changing the default later never alters a match that already
/// exists.
class CricketRulesScreen extends StatefulWidget {
  const CricketRulesScreen({super.key});

  @override
  State<CricketRulesScreen> createState() => _CricketRulesScreenState();
}

class _CricketRulesScreenState extends State<CricketRulesScreen> {
  final _firestoreService = FirestoreService();
  late final Future<CricketRules> _initial = _firestoreService.watchCricketRules().first;
  CricketRules? _edited;
  bool _saving = false;

  Future<void> _save() async {
    final rules = _edited;
    if (rules == null) return;
    setState(() => _saving = true);
    try {
      await _firestoreService.saveCricketRules(rules);
      if (!mounted) return;
      setState(() => _edited = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Saved. Matches generated from now on use these rules; existing matches keep theirs.'),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cricket rules')),
      body: FutureBuilder<CricketRules>(
        future: _initial,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                'These are the default rules for cricket matches. Each match gets its own copy when it is '
                'generated, and you can still change that one match without affecting the others.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              CricketRulesForm(
                initial: snapshot.data!,
                onChanged: (r) => setState(() => _edited = r),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : 'Save default rules'),
                onPressed: _edited == null || _saving ? null : _save,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }
}
