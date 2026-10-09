import '../../models/match.dart';
import '../constants.dart';
import 'cricket_rules.dart';
import 'tournament_plan.dart';

/// A freshly generated cricket match that doesn't yet carry its own rules.
bool needsCricketRules(Match m) => m.sport == Sport.cricket && m.rules == null;

/// Key for looking a category+season's plan up in a map.
String cricketPlanKey(String category, String season) => '$category|$season';

/// Firestore document id (under `config/`) holding a category's plan.
String cricketPlanDocId(String category, String season) => 'cricketPlan_${category}_$season';

/// Gives every cricket match in [matches] that has no rules yet a copy of the
/// tournament default [defaults] — with that match's *stage* over count
/// applied when its category's plan in [plans] set one (e.g. 10 overs for the
/// Final). Other matches (other sports, or cricket matches that already carry
/// rules) come back untouched. A match keeps the rules it was generated with
/// even if the default or the plan changes afterwards — only its own setup
/// page changes them.
List<Match> stampCricketRules(
  List<Match> matches,
  CricketRules defaults, {
  Map<String, CricketTournamentConfig> plans = const {},
}) =>
    [
      for (final m in matches)
        if (needsCricketRules(m))
          m.withRules(rulesForStage(
            defaults,
            plans[cricketPlanKey(m.category, m.season)],
            cricketStageForMatch(m.stage, m.matchCode),
          ))
        else
          m,
    ];
