import 'package:flutter/material.dart';

import 'core/router/app_router.dart';
import 'core/theme/passenger_theme.dart';

class TukiTukiApp extends StatelessWidget {
  const TukiTukiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TukiTuki',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: PassengerTheme.light,
    );
  }
}