import 'package:flutter/material.dart';

import 'pages/login_page.dart';
import 'pages/root_page.dart';
import 'theme/route_in_palette.dart';

class RouteInApp extends StatelessWidget {
  const RouteInApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RouteIn',
      theme: ThemeData(
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: RouteInPalette.denim,
          onPrimary: RouteInPalette.white,
          primaryContainer: RouteInPalette.sky,
          onPrimaryContainer: RouteInPalette.navy,
          secondary: RouteInPalette.coral,
          onSecondary: RouteInPalette.white,
          secondaryContainer: RouteInPalette.mist,
          onSecondaryContainer: RouteInPalette.ink,
          tertiary: RouteInPalette.sky,
          onTertiary: RouteInPalette.navy,
          tertiaryContainer: RouteInPalette.denim,
          onTertiaryContainer: RouteInPalette.white,
          error: RouteInPalette.coral,
          onError: RouteInPalette.white,
          errorContainer: RouteInPalette.mist,
          onErrorContainer: RouteInPalette.ink,
          surface: RouteInPalette.white,
          onSurface: RouteInPalette.ink,
          shadow: RouteInPalette.ink,
          scrim: RouteInPalette.ink,
        ),
        scaffoldBackgroundColor: RouteInPalette.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: RouteInPalette.white,
          foregroundColor: RouteInPalette.ink,
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: RouteInPalette.ink,
          displayColor: RouteInPalette.ink,
        ),
      ),
      home: const _AppEntryPage(),
    );
  }
}

class _AppEntryPage extends StatefulWidget {
  const _AppEntryPage();

  @override
  State<_AppEntryPage> createState() => _AppEntryPageState();
}

class _AppEntryPageState extends State<_AppEntryPage> {
  bool _isLoggedIn = false;

  @override
  Widget build(BuildContext context) {
    if (_isLoggedIn) {
      return const RootPage();
    }

    return LoginPage(
      onLogin: () {
        setState(() {
          _isLoggedIn = true;
        });
      },
    );
  }
}
