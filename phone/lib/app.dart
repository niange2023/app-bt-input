import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/connection_page.dart';
import 'pages/input_page.dart';
import 'pages/settings_page.dart';

class BtInputApp extends StatelessWidget {
  const BtInputApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BT Input',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.blue,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blue,
      ),
      themeMode: ThemeMode.system,
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      initialRoute: '/',
      routes: {
        '/': (_) => const ConnectionPage(),
        '/input': (_) => const InputPage(),
        '/settings': (_) => const SettingsPage(),
      },
    );
  }
}
