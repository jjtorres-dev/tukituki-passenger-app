import 'package:flutter/material.dart';

import 'features/health/health_screen.dart';

class TukiTukiApp extends StatelessWidget {
  const TukiTukiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TukiTuki',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.amber,
      ),
      home: const HealthScreen(),
    );
  }
}