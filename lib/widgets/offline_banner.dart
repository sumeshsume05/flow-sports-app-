import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../core/design/app_colors.dart';
import '../core/design/app_spacing.dart';
import '../state/connectivity_state.dart';

/// A slim banner shown above every screen while the device is offline.
/// Mounted once in [FlowSportsApp] (via `MaterialApp.router`'s `builder`) so
/// it appears app-wide without touching each screen individually.
class OfflineBanner extends StatelessWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isOffline = context.watch<ConnectivityState>().isOffline;
    return Column(
      children: [
        if (isOffline)
          Material(
            color: AppColors.warningAmber,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 16, color: Colors.black87),
                    SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        "You're offline — showing saved data. It'll sync automatically.",
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ).animate().slideY(begin: -1, end: 0, duration: 250.ms).fadeIn(),
        Expanded(child: child),
      ],
    );
  }
}
