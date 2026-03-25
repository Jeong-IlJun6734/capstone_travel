import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'pages/root_page.dart';

class FocusFlowApp extends StatelessWidget {
  const FocusFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    const canvas = Color(0xFFF4F1EA);
    const ink = Color(0xFF1B1B1B);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Focus Flow',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFCC5A2B),
          brightness: Brightness.light,
          surface: canvas,
        ),
        scaffoldBackgroundColor: canvas,
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
        ),
      ),
      builder: (context, child) {
        final appChild = child ?? const SizedBox.shrink();

        return LayoutBuilder(
          builder: (context, constraints) {
            final platform = Theme.of(context).platform;
            final isDesktopPlatform =
                !kIsWeb &&
                (platform == TargetPlatform.windows ||
                    platform == TargetPlatform.linux ||
                    platform == TargetPlatform.macOS);

            if (!isDesktopPlatform || constraints.maxWidth < 520) {
              return appChild;
            }

            const phoneAspectRatio = 9 / 19.5;
            final availableWidth = math.max(0.0, constraints.maxWidth - 32);
            final availableHeight = math.max(0.0, constraints.maxHeight - 32);
            final widthFromHeight = availableHeight * phoneAspectRatio;
            final frameWidth = math.min(
              430.0,
              math.min(availableWidth, widthFromHeight),
            );
            final frameHeight = math.min(
              availableHeight,
              frameWidth / phoneAspectRatio,
            );

            return ColoredBox(
              color: const Color(0xFFE6E0D5),
              child: Center(
                child: Container(
                  width: frameWidth,
                  height: frameHeight,
                  decoration: BoxDecoration(
                    color: canvas,
                    borderRadius: BorderRadius.circular(36),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 30,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: appChild,
                ),
              ),
            );
          },
        );
      },
      home: const RootPage(),
    );
  }
}
