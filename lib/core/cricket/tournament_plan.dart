import '../../models/match.dart';
import 'cricket_rules.dart';

/// The kinds of match that can have their own over count.
enum CricketStage { league, quarterfinal, semifinal, qualifier, finalGame, tiebreaker }

extension CricketStageLabel on CricketStage {
  String get label => switch (this) {
        CricketStage.league => 'League',
        CricketStage.quarterfinal => 'Quarterfinal',
        CricketStage.semifinal => 'Semifinal',
        CricketStage.qualifier => 'Qualifier',
        CricketStage.finalGame => 'Final',
        CricketStage.tiebreaker => 'Tie-breaker',
      };
}

/// Which [CricketStage] a generated match belongs to, from its stage and
/// match code (`KO1`/`KO2` semifinals, `KO3` the page-playoff qualifier,
/// `KOF*` the Final). Null when the code isn't one we recognise — such a
/// match simply uses the default overs.
CricketStage? cricketStageForMatch(MatchStage stage, String matchCode) {
  switch (stage) {
    case MatchStage.league:
      return CricketStage.league;
    case MatchStage.tiebreaker:
      return CricketStage.tiebreaker;
    case MatchStage.knockout:
      if (matchCode.startsWith('KOF')) return CricketStage.finalGame;
      if (matchCode == 'KO3') return CricketStage.qualifier;
      if (matchCode == 'KO1' || matchCode == 'KO2' || matchCode.startsWith('SF')) {
        return CricketStage.semifinal;
      }
      if (matchCode.startsWith('QF')) return CricketStage.quarterfinal;
      return null;
  }
}

/// The stages a knockout of [qualifiers] teams actually plays, in order.
List<CricketStage> knockoutStagesFor(int qualifiers) {
  if (qualifiers < 2) return const [];
  if (qualifiers == 2) return const [CricketStage.finalGame];
  if (qualifiers == 3) return const [CricketStage.semifinal, CricketStage.finalGame];
  if (qualifiers == 4) {
    return const [CricketStage.semifinal, CricketStage.qualifier, CricketStage.finalGame];
  }
  return const [CricketStage.quarterfinal, CricketStage.semifinal, CricketStage.finalGame];
}

/// A sensible most-overs-per-bowler for an innings of [overs]: 1 for a very
/// short match, otherwise a fifth of the innings with a floor of 2 (6 overs →
/// 2, 10 → 2, 20 → 4). Always non-decreasing as overs grow.
int suggestedMaxOversPerBowler(int overs) {
  if (overs <= 3) return 1;
  final fifth = (overs / 5).ceil();
  return fifth < 2 ? 2 : fifth;
}

/// The per-bowler limit a match of [overs] should carry given the tournament
/// default [defaults]. If the admin left the default limit at the suggested
/// value for the default overs, it follows the new overs; if they customised
/// it, their number is kept (but never above the overs). No limit stays no
/// limit.
int? maxOversPerBowlerFor(CricketRules defaults, int overs) {
  final base = defaults.maxOversPerBowler;
  if (base == null) return null;
  final followsSuggestion = base == suggestedMaxOversPerBowler(defaults.overs);
  final value = followsSuggestion ? suggestedMaxOversPerBowler(overs) : base;
  return value.clamp(1, overs);
}

/// Plain-English warning when a squad can't cover the overs under the
/// per-bowler limit, or null when it can. Everyone in the squad counts as a
/// possible bowler (roles are optional, so they aren't used to exclude anyone).
String? bowlerSupplyWarning({required int squadCount, required CricketRules rules}) {
  final limit = rules.maxOversPerBowler;
  if (limit == null || limit < 1) return null;
  final needed = (rules.overs / limit).ceil();
  if (squadCount >= needed) return null;
  return '${rules.overs} overs with at most $limit per bowler needs at least $needed bowlers, '
      'but only $squadCount ${squadCount == 1 ? 'player is' : 'players are'} selected.';
}

/// The admin's plan for one category's tournament (stored per category and
/// season). Section *membership* lives on each team; [sections] is just how
/// many the admin chose. [stageOvers] holds only stages the admin overrode —
/// a missing stage uses the tournament default overs.
class CricketTournamentConfig {
  /// 1 = one league, no sections.
  final int sections;
  final bool knockout;

  /// Per section when [sections] > 1, otherwise the total for the league.
  final int qualifiers;

  /// Extra best runners-up on top of [qualifiers] per section. Only allowed
  /// when every section has the same number of teams.
  final int wildcards;
  final bool bestOfThreeFinal;
  final Map<CricketStage, int> stageOvers;

  const CricketTournamentConfig({
    this.sections = 1,
    this.knockout = true,
    this.qualifiers = 4,
    this.wildcards = 0,
    this.bestOfThreeFinal = false,
    this.stageOvers = const {},
  });

  bool get sectioned => sections > 1;

  CricketTournamentConfig copyWith({
    int? sections,
    bool? knockout,
    int? qualifiers,
    int? wildcards,
    bool? bestOfThreeFinal,
    Map<CricketStage, int>? stageOvers,
  }) =>
      CricketTournamentConfig(
        sections: sections ?? this.sections,
        knockout: knockout ?? this.knockout,
        qualifiers: qualifiers ?? this.qualifiers,
        wildcards: wildcards ?? this.wildcards,
        bestOfThreeFinal: bestOfThreeFinal ?? this.bestOfThreeFinal,
        stageOvers: stageOvers ?? this.stageOvers,
      );

  Map<String, dynamic> toMap() => {
        'sections': sections,
        'knockout': knockout,
        'qualifiers': qualifiers,
        'wildcards': wildcards,
        'bestOfThreeFinal': bestOfThreeFinal,
        'stageOvers': {for (final e in stageOvers.entries) e.key.name: e.value},
      };

  factory CricketTournamentConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const CricketTournamentConfig();
    const d = CricketTournamentConfig();
    final raw = map['stageOvers'];
    return CricketTournamentConfig(
      sections: map['sections'] as int? ?? d.sections,
      knockout: map['knockout'] as bool? ?? d.knockout,
      qualifiers: map['qualifiers'] as int? ?? d.qualifiers,
      wildcards: map['wildcards'] as int? ?? d.wildcards,
      bestOfThreeFinal: map['bestOfThreeFinal'] as bool? ?? d.bestOfThreeFinal,
      stageOvers: raw is Map
          ? {
              for (final e in raw.entries)
                for (final s in CricketStage.values)
                  if (s.name == e.key && e.value is int && (e.value as int) > 0) s: e.value as int,
            }
          : const {},
    );
  }
}

/// The rules a match of [stage] should be generated with: the tournament
/// default, with the stage's own over count (and a per-bowler limit that
/// follows it) when the admin set one.
CricketRules rulesForStage(
  CricketRules defaults,
  CricketTournamentConfig? config,
  CricketStage? stage,
) {
  final overs = stage == null ? null : config?.stageOvers[stage];
  if (overs == null || overs == defaults.overs) return defaults;
  final limit = maxOversPerBowlerFor(defaults, overs);
  return defaults.copyWith(
    overs: overs,
    maxOversPerBowler: limit,
    clearMaxOversPerBowler: limit == null,
  );
}

// ---- sections -----------------------------------------------------------

const maxSections = 8;

/// 'A', 'B', 'C', … for section index 0, 1, 2, …
String sectionLetter(int index) => String.fromCharCode(0x41 + index);

/// Snake-order assignment so strength is spread evenly: with 3 sections the
/// order is A, B, C, C, B, A, A, B, C … The input order is the strength order
/// (best first — e.g. by seed, else the order teams were added). Returns
/// team id → section letter.
Map<String, String> autoBalanceSections(List<String> orderedTeamIds, int sections) {
  final k = sections.clamp(1, maxSections);
  final out = <String, String>{};
  for (var i = 0; i < orderedTeamIds.length; i++) {
    final round = i ~/ k;
    final pos = i % k;
    out[orderedTeamIds[i]] = sectionLetter(round.isEven ? pos : k - 1 - pos);
  }
  return out;
}

// ---- match-count preview ------------------------------------------------

class SectionPreview {
  final String label; // '' when there are no sections
  final int teams;
  final int leagueMatches;

  const SectionPreview(this.label, this.teams, this.leagueMatches);
}

class TournamentPreview {
  final int teamCount;
  final List<SectionPreview> sections;
  final int leagueMatches;
  final int qualifiers;
  final int knockoutMin;
  final int knockoutMax;

  /// Overs for each stage that will be played, after applying any per-stage
  /// override to the default.
  final Map<CricketStage, int> overs;
  final List<String> blockers;
  final List<String> warnings;

  const TournamentPreview({
    required this.teamCount,
    required this.sections,
    required this.leagueMatches,
    required this.qualifiers,
    required this.knockoutMin,
    required this.knockoutMax,
    required this.overs,
    required this.blockers,
    required this.warnings,
  });

  int get totalMin => leagueMatches + knockoutMin;
  int get totalMax => leagueMatches + knockoutMax;
  bool get canGenerate => blockers.isEmpty;
}

/// Matches in a round-robin of [n] teams: every pair once.
int roundRobinMatches(int n) => n < 2 ? 0 : n * (n - 1) ~/ 2;

/// Knockout matches for [qualifiers] teams with a single Final: 2 → 1, 3 → 2,
/// the 4-team page playoff → 4, otherwise a standard bracket needs one fewer
/// match than teams.
int knockoutMatchCount(int qualifiers) {
  if (qualifiers < 2) return 0;
  if (qualifiers == 4) return 4;
  return qualifiers - 1;
}

/// Knockout shapes the bracket generator can build today.
bool knockoutSupported(int qualifiers) => qualifiers >= 2 && qualifiers <= 4;

/// Works out what a plan will produce before anything is generated.
///
/// [sectionSizes] lists how many teams are in each section (length ==
/// `config.sections` when sectioned; ignored otherwise); [unassigned] is how
/// many teams have no section yet. Counts are returned as a range because a
/// best-of-3 Final needs 2 or 3 games and tie-breaker matches can't be known
/// in advance.
TournamentPreview previewTournament({
  required int teamCount,
  required List<int> sectionSizes,
  int unassigned = 0,
  required CricketTournamentConfig config,
  required int defaultOvers,
}) {
  final blockers = <String>[];
  final warnings = <String>[];

  final sectioned = config.sectioned;
  final sizes = sectioned ? sectionSizes : [teamCount];
  final sections = <SectionPreview>[
    for (var i = 0; i < sizes.length; i++)
      SectionPreview(sectioned ? sectionLetter(i) : '', sizes[i], roundRobinMatches(sizes[i])),
  ];
  final league = sections.fold<int>(0, (s, p) => s + p.leagueMatches);

  if (teamCount < 2) blockers.add('Add at least 2 teams.');

  if (sectioned) {
    if (unassigned > 0) {
      blockers.add('$unassigned ${unassigned == 1 ? 'team has' : 'teams have'} no section yet.');
    }
    for (final s in sections) {
      if (s.teams < 2) {
        blockers.add('Section ${s.label} needs at least 2 teams (it has ${s.teams}).');
      }
    }
    final nonEmpty = sections.map((s) => s.teams).toSet();
    if (nonEmpty.length > 1 && sections.every((s) => s.teams >= 2)) {
      warnings.add('Sections have different sizes '
          '(${sections.map((s) => '${s.label}: ${s.teams}').join(', ')}), so teams play a different '
          'number of matches and ranking across sections is less fair.');
    }
  }

  var qualifiers = 0;
  var koMin = 0;
  var koMax = 0;
  if (config.knockout && teamCount >= 2) {
    final smallest = sizes.isEmpty ? 0 : sizes.reduce((a, b) => a < b ? a : b);
    if (config.qualifiers < (sectioned ? 1 : 2)) {
      blockers.add(sectioned
          ? 'Choose at least 1 qualifier per section.'
          : 'Choose at least 2 qualifying teams.');
    }
    if (sectioned) {
      if (config.qualifiers > smallest && smallest >= 2) {
        blockers.add('Qualifiers per section (${config.qualifiers}) is more than the smallest '
            'section has ($smallest teams).');
      }
      if (config.wildcards > 0) {
        final equal = sizes.toSet().length == 1;
        if (!equal) {
          blockers.add('Wildcard qualifiers need all sections to have the same number of teams.');
        } else if (config.qualifiers >= smallest) {
          blockers.add('Wildcards are the best runners-up, so each section must have more teams '
              'than it qualifies directly.');
        }
        if (config.wildcards > sizes.length - 1) {
          blockers.add('At most ${sizes.length - 1} wildcard${sizes.length - 1 == 1 ? '' : 's'} '
              'with ${sizes.length} sections.');
        }
        warnings.add('Wildcard knockouts will be generated in a later update.');
      }
      qualifiers = config.qualifiers * sizes.length + config.wildcards;
    } else {
      if (config.qualifiers > teamCount) {
        blockers.add('Only $teamCount teams, so ${config.qualifiers} can\'t qualify.');
      }
      qualifiers = config.qualifiers;
    }
    if (qualifiers >= 2) {
      final base = knockoutMatchCount(qualifiers);
      koMin = config.bestOfThreeFinal ? base + 1 : base;
      koMax = config.bestOfThreeFinal ? base + 2 : base;
      if (!knockoutSupported(qualifiers)) {
        warnings.add('A knockout of $qualifiers teams can\'t be generated yet — for now only 2, 3 '
            'or 4 qualifying teams are supported.');
      }
      warnings.add('Tie-breaker matches may be added if teams are level at the qualifying cut-off.');
    }
  }

  final stages = [
    CricketStage.league,
    if (config.knockout && qualifiers >= 2) ...knockoutStagesFor(qualifiers),
    CricketStage.tiebreaker,
  ];
  final overs = {for (final s in stages) s: config.stageOvers[s] ?? defaultOvers};

  return TournamentPreview(
    teamCount: teamCount,
    sections: sections,
    leagueMatches: league,
    qualifiers: qualifiers,
    knockoutMin: koMin,
    knockoutMax: koMax,
    overs: overs,
    blockers: blockers,
    warnings: warnings,
  );
}
