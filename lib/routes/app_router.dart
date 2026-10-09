import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../screens/admin/admin_cricket_match_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_match_edit_screen.dart';
import '../screens/admin/admin_match_form_screen.dart';
import '../screens/admin/admin_match_list_screen.dart';
import '../screens/admin/admin_players_screen.dart';
import '../screens/admin/admin_seasons_screen.dart';
import '../screens/admin/admin_teams_screen.dart';
import '../screens/admin/admin_test_lab_screen.dart';
import '../screens/admin/cricket_rules_screen.dart';
import '../screens/admin/generate_bracket_screen.dart';
import '../screens/admin/generate_schedule_screen.dart';
import '../screens/admin/login_screen.dart';
import '../screens/viewer/bracket_screen.dart';
import '../screens/viewer/chat_screen.dart';
import '../screens/viewer/home_screen.dart';
import '../screens/viewer/match_detail_screen.dart';
import '../screens/viewer/match_list_screen.dart';
import '../screens/viewer/standings_screen.dart';
import '../core/sports.dart';
import '../state/auth_state.dart';
import '../state/season_state.dart';
import '../widgets/chat_fab.dart';

/// Exposed so widgets built outside the routed tree (e.g. [AppUpdateGate],
/// which wraps the Navigator rather than sitting inside it) can still reach
/// a valid Navigator — `Navigator.of(context)` fails from a context that's
/// an ancestor of the Navigator rather than a descendant of it.
final rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter(AuthState authState) {
  // Every screen that reads/writes teams or matches needs to know which
  // season is active. The router already has a BuildContext when it builds
  // each screen, so it reads SeasonState once here and passes it down as a
  // plain constructor param — same pattern as the existing `category` query
  // param — rather than every screen reaching into Provider itself.
  String season(BuildContext context) => context.watch<SeasonState>().activeSeasonId ?? '';

  // Which sport a sport-scoped screen shows. Read from the `sport` query
  // param next to `category`; a missing/unknown value means badminton so
  // links that predate the param keep working.
  String sport(GoRouterState state) => sportFromQuery(state.uri.queryParameters['sport']);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: authState,
    redirect: (context, state) {
      final goingToAdmin = state.matchedLocation.startsWith('/admin');
      final goingToLogin = state.matchedLocation == '/admin/login';

      if (!goingToAdmin) return null;
      if (authState.isLoading) return null; // wait for auth state to resolve

      if (!authState.isAdmin && !goingToLogin) return '/admin/login';
      if (authState.isAdmin && goingToLogin) return '/admin';
      return null;
    },
    routes: [
      // Viewer screens share a floating chat entry point (with an unread
      // badge) via this shell, so it appears everywhere a viewer browses
      // without any individual screen needing to know about it. `/chat`
      // itself and all `/admin/*` routes stay outside the shell — chat
      // shouldn't float over itself, and admin screens already have their
      // own FloatingActionButtons that a second FAB would collide with.
      ShellRoute(
        builder: (context, state, child) => Stack(
          children: [child, const ChatFab()],
        ),
        routes: [
          GoRoute(path: '/', builder: (context, state) => HomeScreen(season: season(context))),
          GoRoute(
            path: '/matches',
            builder: (context, state) => MatchListScreen(
              sport: sport(state),
              category: state.uri.queryParameters['category'] ?? '',
              season: season(context),
            ),
          ),
          GoRoute(
            path: '/matches/:id',
            builder: (context, state) => MatchDetailScreen(matchId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/standings',
            builder: (context, state) => StandingsScreen(
              sport: sport(state),
              category: state.uri.queryParameters['category'] ?? '',
              season: season(context),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) => ChatScreen(season: season(context)),
      ),
      // Kept outside the shell too (like /chat), but for a different reason:
      // this is the one viewer screen an admin screen (/admin/bracket/generate,
      // itself outside the shell) also pushes straight into. Pushing from
      // outside a ShellRoute into a route inside it is a known go_router bug
      // — '!keyReservation.contains(key)' — that reproduces on a second such
      // push (https://github.com/flutter/flutter/issues/156585). Viewers
      // still reach it the same way as before via MatchListScreen's Bracket
      // button, just without the floating chat button on this one screen.
      GoRoute(
        path: '/bracket',
        builder: (context, state) => BracketScreen(
          sport: sport(state),
          category: state.uri.queryParameters['category'] ?? '',
          season: season(context),
        ),
      ),
      GoRoute(path: '/admin/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/admin', builder: (context, state) => const AdminDashboardScreen()),
      GoRoute(path: '/admin/seasons', builder: (context, state) => const AdminSeasonsScreen()),
      GoRoute(path: '/admin/test-lab', builder: (context, state) => const AdminTestLabScreen()),
      GoRoute(path: '/admin/cricket/rules', builder: (context, state) => const CricketRulesScreen()),
      GoRoute(
        path: '/admin/teams/:id/players',
        builder: (context, state) => AdminPlayersScreen(teamId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/admin/teams',
        builder: (context, state) => AdminTeamsScreen(
          sport: sport(state),
          category: state.uri.queryParameters['category'] ?? '',
          season: season(context),
        ),
      ),
      GoRoute(
        path: '/admin/matches',
        builder: (context, state) => AdminMatchListScreen(
          sport: sport(state),
          category: state.uri.queryParameters['category'] ?? '',
          season: season(context),
        ),
      ),
      GoRoute(
        path: '/admin/matches/new',
        builder: (context, state) => AdminMatchFormScreen(
          sport: sport(state),
          category: state.uri.queryParameters['category'] ?? '',
          season: season(context),
        ),
      ),
      GoRoute(
        path: '/admin/matches/:id/edit',
        // Cricket matches have their own admin page; every other sport uses
        // the original score-entry screen. The list passes `sport` along.
        builder: (context, state) => sport(state) == Sport.cricket
            ? AdminCricketMatchScreen(matchId: state.pathParameters['id']!)
            : AdminMatchEditScreen(matchId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/admin/schedule/generate',
        builder: (context, state) => GenerateScheduleScreen(
          sport: sport(state),
          category: state.uri.queryParameters['category'] ?? '',
          season: season(context),
        ),
      ),
      GoRoute(
        path: '/admin/bracket/generate',
        builder: (context, state) => GenerateBracketScreen(
          sport: sport(state),
          category: state.uri.queryParameters['category'] ?? '',
          season: season(context),
        ),
      ),
    ],
  );
}
