import 'package:flutter/material.dart';

import '../core/design/app_spacing.dart';

/// The one confirmation window every sport uses before an action that others
/// will see or that can't be taken back. Three levels:
///  * plain — say what will happen ([danger] false)
///  * danger — red button, for deleting things ([danger] true)
///  * type-to-confirm — danger plus the admin must type [typeToConfirm]
///    (e.g. RESET) before the button turns on, for wiping a lot at once.
///
/// Returns true only when the admin confirms.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? message,
  List<String> bullets = const [],
  required String confirmLabel,
  bool danger = false,
  String? typeToConfirm,
  String cancelLabel = 'Cancel',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _ConfirmDialog(
      title: title,
      message: message,
      bullets: bullets,
      confirmLabel: confirmLabel,
      danger: danger || typeToConfirm != null,
      typeToConfirm: typeToConfirm,
      cancelLabel: cancelLabel,
    ),
  );
  return ok == true;
}

class _ConfirmDialog extends StatefulWidget {
  final String title;
  final String? message;
  final List<String> bullets;
  final String confirmLabel;
  final bool danger;
  final String? typeToConfirm;
  final String cancelLabel;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.bullets,
    required this.confirmLabel,
    required this.danger,
    required this.typeToConfirm,
    required this.cancelLabel,
  });

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _unlocked =>
      widget.typeToConfirm == null ||
      _typed.text.trim().toUpperCase() == widget.typeToConfirm!.toUpperCase();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) Text(widget.message!),
            for (final b in widget.bullets)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [const Text('•  '), Expanded(child: Text(b))],
                ),
              ),
            if (widget.typeToConfirm != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text('Type ${widget.typeToConfirm} to confirm:'),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _typed,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(widget.cancelLabel)),
        FilledButton(
          style: widget.danger ? FilledButton.styleFrom(backgroundColor: scheme.error) : null,
          onPressed: _unlocked ? () => Navigator.pop(context, true) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
