import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../models/app_update_info.dart';
import '../routes/app_router.dart';
import '../services/app_update_service.dart';
import '../state/app_update_state.dart';

/// Mounted once around the whole app (see [FlowSportsApp]), so an update
/// prompt can appear regardless of which screen is currently showing.
/// Optional updates get a dismissible dialog shown once per distinct
/// version (not once per launch — [AppUpdateState] now also re-checks on
/// app resume, so a release published while backgrounded should still
/// prompt without re-nagging about a version already dismissed); mandatory
/// ones (`forceUpdate: true` in `version.json`) replace the entire app with
/// a blocking screen until the user updates.
class AppUpdateGate extends StatefulWidget {
  final Widget child;

  const AppUpdateGate({super.key, required this.child});

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  int? _dialogShownForVersionCode;

  @override
  Widget build(BuildContext context) {
    final updateState = context.watch<AppUpdateState>();
    final info = updateState.latest;

    if (updateState.updateAvailable && info!.forceUpdate) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          appBar: AppBar(title: const Text('Update Required'), automaticallyImplyLeading: false),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _UpdateContent(info: info),
            ),
          ),
        ),
      );
    }

    if (updateState.updateAvailable && _dialogShownForVersionCode != info!.latestVersionCode) {
      _dialogShownForVersionCode = info.latestVersionCode;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Can't use this widget's own `context` here — AppUpdateGate wraps
        // `child` (which contains the router's Navigator), so its context
        // sits *above* that Navigator, not inside it, and
        // `Navigator.of(context)` (which showDialog needs) can only find an
        // ancestor Navigator. rootNavigatorKey's context is inside it.
        final navContext = rootNavigatorKey.currentContext;
        if (navContext == null) return;
        showDialog<void>(
          context: navContext,
          builder: (context) => AlertDialog(
            title: const Text('Update available'),
            content: _UpdateContent(info: info, onDismiss: () => Navigator.pop(context)),
          ),
        );
      });
    }

    return widget.child;
  }
}

class _UpdateContent extends StatefulWidget {
  final AppUpdateInfo info;
  final VoidCallback? onDismiss;

  const _UpdateContent({required this.info, this.onDismiss});

  @override
  State<_UpdateContent> createState() => _UpdateContentState();
}

class _UpdateContentState extends State<_UpdateContent> {
  final _service = AppUpdateService();
  double? _progress;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final file = await _service.downloadApk(
        widget.info.apkUrl,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await _service.installApk(file.path);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloading = _progress != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('A new version (${widget.info.latestVersionName}) is available.'),
        if (widget.info.changelog != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(widget.info.changelog!),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: AppSpacing.md),
        if (downloading)
          Column(
            children: [
              LinearProgressIndicator(value: _progress! > 0 ? _progress : null),
              const SizedBox(height: AppSpacing.xs),
              Text('Downloading… ${(_progress! * 100).toStringAsFixed(0)}%'),
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.onDismiss != null)
                TextButton(onPressed: widget.onDismiss, child: const Text('Later')),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(onPressed: _update, child: const Text('Update Now')),
            ],
          ),
      ],
    );
  }
}
