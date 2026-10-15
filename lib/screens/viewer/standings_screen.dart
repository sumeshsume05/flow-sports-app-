import 'package:flutter/material.dart';

import '../../core/utils/match_action_text.dart';
import '../../core/constants.dart';
import '../../core/cricket/tournament_plan.dart';
import '../../core/utils/sections.dart';
import '../../core/utils/sport_standings.dart';
import '../../core/utils/standings_calculator.dart';
import '../../models/match.dart';
import '../../models/standing_row.dart';
import '../../models/team.dart';
import '../../services/firestore_service.dart';
import '../../widgets/standings_table.dart';

class StandingsScreen extends StatelessWidget {
  final String sport;
  final String category;
  final String season;

  /// Tests pass one backed by a fake Firestore.
  final FirestoreService? service;
  late final _firestoreService = service ?? FirestoreService();
  late final _teamsStream = _firestoreService.watchTeams(
    sport: sport,
    category: category,
    season: season,
  );
  late final _matchesStream = _firestoreService.watchMatches(
    sport: sport,
    category: category,
    season: season,
  );

  /// Cricket's plan says how many teams qualify (per section when sectioned);
  /// every other sport reads the bracket alone.
  late final Stream<CricketTournamentConfig> _planStream =
      sport == Sport.cricket
      ? _firestoreService.watchCricketPlan(category, season)
      : Stream.value(const CricketTournamentConfig());

  StandingsScreen({
    super.key,
    required this.sport,
    required this.category,
    required this.season,
    this.service,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Standings')),
      body: StreamBuilder<List<Team>>(
        stream: _teamsStream,
        builder: (context, teamsSnap) {
          if (!teamsSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<List<Match>>(
            stream: _matchesStream,
            builder: (context, matchesSnap) =>
                StreamBuilder<CricketTournamentConfig>(
                  stream: _planStream,
                  builder: (context, planSnap) {
                    if (!matchesSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final plan =
                        planSnap.data ?? const CricketTournamentConfig();
                    final cricket = sport == Sport.cricket;
                    final teams = teamsSnap.data!;
                    final leagueMatches = matchesSnap.data!
                        .where((m) => m.stage == MatchStage.league)
                        .toList();

                    final withSection = teams
                        .where((t) => t.section != null)
                        .length;
                    final sectioned =
                        withSection > 0 && withSection == teams.length;

                    if (!sectioned) {
                      final List<StandingRow> standings = computeSportStandings(
                        sport: sport,
                        teams: teams,
                        leagueMatches: leagueMatches,
                      );
                      // How many teams go through: whatever the admin chose when the
                      // bracket was made (2, 3 or 4) — 4 until there is a bracket.
                      final qualifyCount = qualifierCountFromBracket(
                        matchesSnap.data!
                            .where((m) => m.stage == MatchStage.knockout)
                            .toList(),
                        fallback: cricket ? plan.qualifiers : 4,
                      );
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // No banner before a single match is played — everyone is
                            // level at 0, which isn't a real tie.
                            if (standings.any((r) => r.played > 0) &&
                                topFourHasAmbiguousTie(
                                  standings,
                                  cutoffCount: qualifyCount,
                                ))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  'Some teams are tied on points around the top-$qualifyCount cutoff. '
                                  'Seed order will need manual confirmation before generating the bracket.',
                                  style: const TextStyle(color: Colors.orange),
                                ),
                              ),
                            StandingsTable(
                              rows: standings,
                              qualifyCount: qualifyCount,
                            ),
                          ],
                        ),
                      );
                    }

                    final sections =
                        teams.map((t) => t.section!).toSet().toList()..sort();
                    return ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (final section in sections) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, top: 4),
                            child: Text(
                              'Section $section',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Builder(
                            builder: (context) {
                              final sectionStandings = computeSportStandings(
                                sport: sport,
                                teams: teams
                                    .where((t) => t.section == section)
                                    .toList(),
                                leagueMatches: leagueMatchesForSection(
                                  leagueMatches,
                                  teams,
                                  section,
                                ),
                              );
                              final sectionQualify = cricket
                                  ? plan.qualifiers.clamp(1, 8)
                                  : 2;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (sectionStandings.any(
                                        (r) => r.played > 0,
                                      ) &&
                                      topFourHasAmbiguousTie(
                                        sectionStandings,
                                        cutoffCount: sectionQualify,
                                      ))
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 12),
                                      child: Text(
                                        'Some teams are tied on points around the qualifying cutoff for this section.',
                                        style: TextStyle(color: Colors.orange),
                                      ),
                                    ),
                                  StandingsTable(
                                    rows: sectionStandings,
                                    qualifyCount: sectionQualify,
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                        ],
                      ],
                    );
                  },
                ),
          );
        },
      ),
    );
  }
}
