import '../../models/match.dart';
import '../constants.dart';
import 'cricket_rules.dart';

/// A freshly generated cricket match that doesn't yet carry its own rules.
bool needsCricketRules(Match m) => m.sport == Sport.cricket && m.rules == null;

/// Gives every cricket match in [matches] that has no rules yet a copy of
/// [rules]; other matches (other sports, or cricket matches that already
/// carry rules) come back untouched. A match keeps the rules it was
/// generated with even if the tournament default changes afterwards — only
/// its own setup page changes them.
List<Match> stampCricketRules(List<Match> matches, CricketRules rules) => [
      for (final m in matches) needsCricketRules(m) ? m.withRules(rules) : m,
    ];
