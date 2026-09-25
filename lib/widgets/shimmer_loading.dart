import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';

/// Skeleton placeholders shown while a StreamBuilder is waiting on its first
/// snapshot, instead of a bare spinner — gives the screen visible structure
/// immediately, which reads as faster on a slow courtside connection.
class ShimmerList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;

  const ShimmerList({super.key, this.itemCount = 6, this.itemHeight = 78});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHigh,
      highlightColor: scheme.surfaceContainerHighest,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: itemCount,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          child: Container(
            height: itemHeight,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
      ),
    );
  }
}
