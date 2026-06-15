import 'package:flutter/material.dart';

class AlertBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const AlertBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.backgroundColor,
    this.foregroundColor,
  });

  factory AlertBanner.error({
    Key? key,
    required String message,
  }) {
    return AlertBanner(
      key: key,
      message: message,
      icon: Icons.error_outline,
      backgroundColor: const Color(0xFFFDE7EC),
      foregroundColor: const Color(0xFFE60F41),
    );
  }

  factory AlertBanner.success({
    Key? key,
    required String message,
  }) {
    return AlertBanner(
      key: key,
      message: message,
      icon: Icons.check_circle_outline,
      backgroundColor: const Color(0xFFE6F3F0),
      foregroundColor: const Color(0xFF048665),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = backgroundColor ?? theme.colorScheme.surfaceContainerHighest;
    final fg = foregroundColor ?? theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
