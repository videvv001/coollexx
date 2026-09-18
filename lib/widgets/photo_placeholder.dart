import 'dart:io';

import 'package:flutter/material.dart';

/// A card/cover photo — a real photo when one exists, otherwise a
/// placeholder. Every image in this app is user-taken; there is no stock
/// card art, so the placeholder is the honest default, not an error state.
class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({
    super.key,
    this.path,
    this.aspectRatio = 5 / 7,
    this.dashed = false,
    this.icon = Icons.photo_camera_outlined,
    this.label,
    this.borderRadius = 8,
  });

  final String? path;
  final double aspectRatio;
  final bool dashed;
  final IconData icon;
  final String? label;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget child;
    if (path != null && File(path!).existsSync()) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.file(File(path!), fit: BoxFit.cover, cacheWidth: 400),
      );
    } else {
      child = DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(borderRadius),
          border: dashed ? Border.all(color: scheme.outline, width: 1.5) : null,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: scheme.onSurfaceVariant, size: 28),
              if (label != null) ...[
                const SizedBox(height: 4),
                Text(
                  label!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }
    return AspectRatio(aspectRatio: aspectRatio, child: child);
  }
}
