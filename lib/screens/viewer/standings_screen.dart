import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/utils/standings_calculator.dart';
import '../../models/match.dart';
import '../../models/standing_row.dart';
import '../../models/team.dart';
import '../../services/firestore_service.dart';
import '../../widgets/standings_table.dart';

class StandingsScreen extends StatelessWidget {
  final String category;
  final String season;
  final _firestoreService = FirestoreService();
  late final _teamsStream =
      _firestoreService.watchTeams(sport: Sport.badminton, category: category, season: season);
  late final _matchesStream =
      _firestoreService.watchMatches(sport: Sport.badminton, category: category, season: season);

  StandingsScreen({super.key, required this.category, required this.season});

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
            builder: (context, matchesSnap) {
              if (!matchesSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final leagueMatches =
                  matchesSnap.data!.where((m) => m.stage == MatchStage.league).toList();
              final List<StandingRow> standings = computeStandings(
                teams: teamsSnap.data!,
                leagueMatches: leagueMatches,
              );
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (topFourHasAmbiguousTie(standings))
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Some teams are tied on points around the top-4 cutoff. '
                          'Seed order will need manual confirmation before generating the bracket.',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ),
                    StandingsTable(rows: standings),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
