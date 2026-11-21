import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps the inspector's background and system navigation area consistent.
class InspectorSurface extends StatelessWidget {
  const InspectorSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).scaffoldBackgroundColor;
    final dark =
        ThemeData.estimateBrightnessForColor(surface) == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: surface,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: surface,
        systemNavigationBarContrastEnforced: false,
      ),
      child: ColoredBox(color: surface, child: child),
    );
  }
}
