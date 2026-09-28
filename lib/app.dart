import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'routes/app_router.dart';
import 'state/app_update_state.dart';
import 'state/auth_state.dart';
import 'state/chat_settings_state.dart';
import 'state/connectivity_state.dart';
import 'state/season_state.dart';
import 'widgets/app_update_gate.dart';
import 'widgets/offline_banner.dart';

class FlowSportsApp extends StatefulWidget {
  const FlowSportsApp({super.key});

  @override
  State<FlowSportsApp> createState() => _FlowSportsAppState();
}

class _FlowSportsAppState extends State<FlowSportsApp> with WidgetsBindingObserver {
  final _authState = AuthState();
  final _connectivityState = ConnectivityState();
  final _seasonState = SeasonState();
  final _chatSettingsState = ChatSettingsState();
  final _appUpdateState = AppUpdateState();
  late final _router = buildRouter(_authState);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Fire-and-forget: a failed check just means no prompt shows, never
    // blocks app startup.
    _appUpdateState.checkForUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Also re-check when the app comes back to the foreground (not just on
    // a fresh cold start) — catches a release published while the app was
    // simply backgrounded, without ever polling while actively in use.
    if (state == AppLifecycleState.resumed) {
      _appUpdateState.checkForUpdate();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authState.dispose();
    _connectivityState.dispose();
    _seasonState.dispose();
    _chatSettingsState.dispose();
    _appUpdateState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authState),
        ChangeNotifierProvider.value(value: _connectivityState),
        ChangeNotifierProvider.value(value: _seasonState),
        ChangeNotifierProvider.value(value: _chatSettingsState),
        ChangeNotifierProvider.value(value: _appUpdateState),
      ],
      child: MaterialApp.router(
        title: 'FLOW Arena',
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        routerConfig: _router,
        builder: (context, child) => AppUpdateGate(
          child: OfflineBanner(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
