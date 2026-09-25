import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'routes/app_router.dart';
import 'state/auth_state.dart';
import 'state/connectivity_state.dart';
import 'state/season_state.dart';
import 'widgets/offline_banner.dart';

class FlowSportsApp extends StatefulWidget {
  const FlowSportsApp({super.key});

  @override
  State<FlowSportsApp> createState() => _FlowSportsAppState();
}

class _FlowSportsAppState extends State<FlowSportsApp> {
  final _authState = AuthState();
  final _connectivityState = ConnectivityState();
  final _seasonState = SeasonState();
  late final _router = buildRouter(_authState);

  @override
  void dispose() {
    _authState.dispose();
    _connectivityState.dispose();
    _seasonState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authState),
        ChangeNotifierProvider.value(value: _connectivityState),
        ChangeNotifierProvider.value(value: _seasonState),
      ],
      child: MaterialApp.router(
        title: 'FLOW Arena',
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        routerConfig: _router,
        builder: (context, child) => OfflineBanner(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
