import 'package:flutter/material.dart';

/// Shows a lightweight top-positioned banner using an [OverlayEntry]. This
/// avoids relying on [ScaffoldMessenger] placement rules and guarantees the
/// notification appears near the top (below status bar / app bar).
void showTopSnackBar(
  BuildContext context,
  String message, {
  Duration? duration,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlayState = Overlay.of(context);

  final double topPadding = MediaQuery.of(context).padding.top;
  final double top = topPadding + kToolbarHeight + 8.0;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (BuildContext ctx) {
      final ColorScheme colors = Theme.of(ctx).colorScheme;
      final Color background = colors.primaryContainer;
      final Color foreground = colors.onPrimaryContainer;

      return Positioned(
        top: top,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            top: false,
            bottom: false,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: -8, end: 0),
              duration: const Duration(milliseconds: 250),
              builder: (BuildContext _, double dy, Widget? child) {
                return Transform.translate(
                  offset: Offset(0, dy),
                  child: Opacity(opacity: 1.0, child: child),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    )
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        message,
                        style: Theme.of(ctx)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: foreground),
                      ),
                    ),
                    if (actionLabel != null && onAction != null) ...<Widget>[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          try {
                            onAction();
                          } finally {
                            entry.remove();
                          }
                        },
                        child: Text(actionLabel, style: TextStyle(color: foreground)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlayState.insert(entry);
  Future<void>.delayed(duration ?? const Duration(seconds: 3), () {
    try {
      entry.remove();
    } catch (_) {}
  });
}
