import 'package:flutter/material.dart';

import 'pages/connection_page.dart';
import 'pages/input_page.dart';
import 'pages/settings_page.dart';

class BtInputApp extends StatelessWidget {
  const BtInputApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BT Input',
      theme: ThemeData(useMaterial3: true),
      initialRoute: '/',
      routes: {
        '/': (_) => const ConnectionPage(),
        '/input': (_) => const InputPage(),
        '/settings': (_) => const SettingsPage(),
      },
    );
  }
}
