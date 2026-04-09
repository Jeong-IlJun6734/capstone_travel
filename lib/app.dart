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
      home: const RootPage(),
    );
  }
}
