import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_match_edit_screen.dart';
import '../screens/admin/admin_match_form_screen.dart';
import '../screens/admin/admin_match_list_screen.dart';
import '../screens/admin/admin_seasons_screen.dart';
import '../screens/admin/admin_teams_screen.dart';
import '../screens/admin/generate_bracket_screen.dart';
import '../screens/admin/generate_schedule_screen.dart';
import '../screens/admin/login_screen.dart';
import '../screens/viewer/bracket_screen.dart';
import '../screens/viewer/chat_screen.dart';
import '../screens/viewer/home_screen.dart';
import '../screens/viewer/match_detail_screen.dart';
import '../screens/viewer/match_list_screen.dart';
import '../screens/viewer/standings_screen.dart';
import '../state/auth_state.dart';
import '../state/season_state.dart';
import '../widgets/chat_fab.dart';

GoRouter buildRouter(AuthState authState) {
  // Every screen that reads/writes teams or matches needs to know which
  // season is active. The router already has a BuildContext when it builds
  // each screen, so it reads SeasonState once here and passes it down as a
  // plain constructor param — same pattern as the existing `category` query
  // param — rather than every screen reaching into Provider itself.
  String season(BuildContext context) => context.watch<SeasonState>().activeSeasonId ?? '';

  return GoRouter(
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
              category: state.uri.queryParameters['category'] ?? '',
              season: season(context),
            ),
          ),
          GoRoute(
            path: '/bracket',
            builder: (context, state) => BracketScreen(
              category: state.uri.queryParameters['category'] ?? '',
              season: season(context),
            ),
          ),
        ],
      ),
      GoRoute(path: '/chat', builder: (context, state) => const ChatScreen()),
      GoRoute(path: '/admin/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/admin', builder: (context, state) => const AdminDashboardScreen()),
      GoRoute(path: '/admin/seasons', builder: (context, state) => const AdminSeasonsScreen()),
      GoRoute(
        path: '/admin/teams',
        builder: (context, state) => AdminTeamsScreen(
          category: state.uri.queryParameters['category'] ?? '',
          season: season(context),
        ),
      ),
      GoRoute(
        path: '/admin/matches',
        builder: (context, state) => AdminMatchListScreen(
          category: state.uri.queryParameters['category'] ?? '',
          season: season(context),
        ),
      ),
      GoRoute(
        path: '/admin/matches/new',
        builder: (context, state) => AdminMatchFormScreen(
          category: state.uri.queryParameters['category'] ?? '',
          season: season(context),
        ),
      ),
      GoRoute(
        path: '/admin/matches/:id/edit',
        builder: (context, state) => AdminMatchEditScreen(matchId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/admin/schedule/generate',
        builder: (context, state) => GenerateScheduleScreen(
          category: state.uri.queryParameters['category'] ?? '',
          season: season(context),
        ),
      ),
      GoRoute(
        path: '/admin/bracket/generate',
        builder: (context, state) => GenerateBracketScreen(
          category: state.uri.queryParameters['category'] ?? '',
          season: season(context),
        ),
      ),
    ],
  );
}
