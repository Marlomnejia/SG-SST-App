import 'package:flutter/material.dart';

class AppMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? background;
  final Color? foreground;
  final Color? borderColor;
  final double? maxWidth;
  final FontWeight fontWeight;
  final double iconSize;
  final double horizontalPadding;
  final double verticalPadding;

  const AppMetaChip({
    super.key,
    required this.icon,
    required this.label,
    this.background,
    this.foreground,
    this.borderColor,
    this.maxWidth,
    this.fontWeight = FontWeight.w600,
    this.iconSize = 14,
    this.horizontalPadding = 10,
    this.verticalPadding = 6,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = background ?? scheme.surfaceContainerHighest;
    final fg = foreground ?? scheme.onSurfaceVariant;
    final resolvedBorder =
        borderColor ??
        (foreground != null
            ? fg.withValues(alpha: 0.2)
            : scheme.outline.withValues(alpha: 0.18));

    return Container(
      constraints: maxWidth == null
          ? const BoxConstraints(minHeight: 30)
          : BoxConstraints(minHeight: 30, maxWidth: maxWidth!),
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: resolvedBorder, width: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: fontWeight,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
