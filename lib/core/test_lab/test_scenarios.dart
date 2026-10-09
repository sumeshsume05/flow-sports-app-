import '../../models/match.dart';
import '../../models/player.dart';
import '../constants.dart';

/// One ready-made set of test teams the admin can create with a single tap
/// instead of typing teams and players by hand. Pure data — no Firestore —
/// so every scenario is unit-tested.
class TestScenario {
  final String id;
  final String title;
  final String description;
  final int teams;

  /// Teams per league section, in order (e.g. `[4, 3]`). Empty = one league,
  /// no sections. The sizes add up to [teams].
  final List<int> sectionSizes;

  /// Cricket only: players on each team in order, so a scenario can test
  /// unequal squads. Empty = [defaultSquad] for every team.
  final List<int> squadSizes;

  const TestScenario({
    required this.id,
    required this.title,
    required this.description,
    required this.teams,
    this.sectionSizes = const [],
    this.squadSizes = const [],
  });
}

/// One team to create.
class TestTeamSpec {
  final String name;
  final String? section;
  final List<Player> players;

  const TestTeamSpec(this.name, {this.section, this.players = const []});
}

const defaultSquad = 8;

const _firstNames = [
  'Arun', 'Bala', 'Chandru', 'Dinesh', 'Elango', 'Farook', 'Gopi', 'Hari', 'Ilan', 'Jega',
  'Karthi', 'Loga', 'Mani', 'Naren', 'Omar', 'Praveen', 'Ravi', 'Sathya', 'Tamil', 'Uday',
  'Vimal', 'Wilson', 'Yuvan', 'Zakir',
];

const _cricketTeamNames = [
  'Test Lions', 'Test Tigers', 'Test Eagles', 'Test Sharks', 'Test Wolves', 'Test Hawks',
  'Test Bears', 'Test Foxes', 'Test Panthers', 'Test Cobras', 'Test Rhinos', 'Test Falcons',
];

/// The most teams any scenario creates (name pools are sized for this).
const maxTestTeams = 12;

/// Scenarios offered for [sport]. Badminton's league supports at most two
/// sections (that's all its knockout bracket can use), so it gets no 3-section
/// scenario.
List<TestScenario> testScenariosFor(String sport) {
  final common = <TestScenario>[
    const TestScenario(id: 't2', title: '2 teams', description: 'Smallest tournament: 1 league match.', teams: 2),
    const TestScenario(id: 't3', title: '3 teams', description: 'League of 3 matches; try 2 or 3 qualifiers.', teams: 3),
    const TestScenario(id: 't4', title: '4 teams', description: 'League of 6 matches, then the 4-team playoff.', teams: 4),
    const TestScenario(id: 't6', title: '6 teams — one league', description: '15 league matches.', teams: 6),
    const TestScenario(
      id: 't6s',
      title: '6 teams — 2 sections of 3',
      description: '3 + 3 league matches, then a shared knockout.',
      teams: 6,
      sectionSizes: [3, 3],
    ),
    const TestScenario(id: 't8', title: '8 teams — one league', description: '28 league matches.', teams: 8),
    const TestScenario(
      id: 't8s',
      title: '8 teams — 2 sections of 4',
      description: '6 + 6 league matches, top 2 of each section qualify.',
      teams: 8,
      sectionSizes: [4, 4],
    ),
    const TestScenario(
      id: 't7u',
      title: '7 teams — sections 4 + 3 (unequal)',
      description: 'Sections of different sizes: 6 + 3 league matches. Tests the warnings.',
      teams: 7,
      sectionSizes: [4, 3],
    ),
  ];
  if (sport == Sport.cricket) {
    return [
      ...common,
      const TestScenario(
        id: 't12s3',
        title: '12 teams — 3 sections of 4',
        description: '6 league matches per section, 18 in total.',
        teams: 12,
        sectionSizes: [4, 4, 4],
      ),
      const TestScenario(
        id: 't4unequal',
        title: '4 teams — unequal squads (5, 6, 8, 11)',
        description: 'Tests the unequal-squad and not-enough-bowlers warnings.',
        teams: 4,
        squadSizes: [5, 6, 8, 11],
      ),
      const TestScenario(
        id: 't4t20',
        title: '4 teams — 11-player squads',
        description: 'Full squads for T20-style rules.',
        teams: 4,
        squadSizes: [11, 11, 11, 11],
      ),
    ];
  }
  return common;
}

String _initial(int i) => String.fromCharCode(0x41 + i);

/// The teams (and, for cricket, their players) a scenario creates.
List<TestTeamSpec> buildScenarioTeams(String sport, TestScenario s) {
  assert(s.teams <= maxTestTeams);
  // Section letter for each team index, filling sections in order.
  final sections = <String?>[];
  if (s.sectionSizes.isEmpty) {
    sections.addAll(List<String?>.filled(s.teams, null));
  } else {
    for (var i = 0; i < s.sectionSizes.length; i++) {
      sections.addAll(List<String?>.filled(s.sectionSizes[i], _initial(i)));
    }
  }
  assert(sections.length == s.teams, 'section sizes must add up to the team count');

  const roles = [PlayerRole.bat, PlayerRole.bowl, PlayerRole.all, PlayerRole.bowl, PlayerRole.bat, PlayerRole.wk];

  return [
    for (var i = 0; i < s.teams; i++)
      if (sport == Sport.cricket)
        TestTeamSpec(
          _cricketTeamNames[i],
          section: sections[i],
          players: [
            for (var j = 0; j < (s.squadSizes.isEmpty ? defaultSquad : s.squadSizes[i]); j++)
              Player(
                id: Player.newId(),
                name: _firstNames[(i * 3 + j) % _firstNames.length],
                role: roles[j % roles.length],
              ),
          ],
        )
      else
        // Badminton teams are doubles pairs.
        TestTeamSpec(
          '${_firstNames[(i * 2) % _firstNames.length]} & ${_firstNames[(i * 2 + 1) % _firstNames.length]}',
          section: sections[i],
        ),
  ];
}

/// Random-ish but deterministic-when-seeded badminton scores for the league
/// auto-play: the winner gets 21, the loser 0–19. A tie is 21–21.
({int a, int b}) testScores({required bool tie, required bool aWins, required int loserScore}) {
  if (tie) return (a: 21, b: 21);
  final loser = loserScore.clamp(0, 19);
  return aWins ? (a: 21, b: loser) : (a: loser, b: 21);
}

/// The matches auto-play should fill in: those with no result yet and both
/// teams known. Anything already played is never overwritten, and a match
/// still waiting on an earlier round (a TBD team) can't be played.
List<Match> unplayedMatches(List<Match> all) => [
      for (final m in all)
        if (m.result == null && m.teamA.teamId != null && m.teamB.teamId != null) m,
    ];
