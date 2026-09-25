import 'package:csv/csv.dart';

import '../../models/match.dart';
import '../constants.dart';

/// Builds one CSV covering every stage (league, knockout, tie-breaker) for a
/// sport — "round 1, round 2, everything" in one downloadable file, sorted
/// so a category's league matches come before its knockout matches.
String buildMatchesCsv(List<Match> matches) {
  final sorted = List<Match>.of(matches)
    ..sort((a, b) {
      final byCategory = a.category.compareTo(b.category);
      if (byCategory != 0) return byCategory;
      final byStage = a.stage.index.compareTo(b.stage.index);
      if (byStage != 0) return byStage;
      return a.matchNumber.compareTo(b.matchNumber);
    });

  final rows = <List<dynamic>>[
    [
      'Category',
      'Stage',
      'Match Code',
      'Label',
      'Team A',
      'Team B',
      'Score A',
      'Score B',
      'Winner',
      'Status',
      'Venue',
      'Court',
    ],
    for (final m in sorted)
      [
        categoryLabel(m.category),
        m.stage.name,
        m.matchCode,
        m.label,
        m.teamA.name ?? 'TBD',
        m.teamB.name ?? 'TBD',
        m.scoreA ?? '',
        m.scoreB ?? '',
        switch (m.result) {
          MatchResult.teamA => m.teamA.name ?? 'Team A',
          MatchResult.teamB => m.teamB.name ?? 'Team B',
          MatchResult.tie => 'Tie',
          null => '',
        },
        m.status.name,
        m.venue ?? '',
        m.court ?? '',
      ],
  ];

  return const ListToCsvConverter().convert(rows);
}
