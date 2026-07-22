import 'package:flutter/material.dart';

import 'services/app_services.dart';
import 'theme/app_theme.dart';
import 'ui/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.open();
  runApp(PachiApp(services: services));
}

class PachiApp extends StatelessWidget {
  final AppServices services;
  const PachiApp({super.key, required this.services});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'パチ回転計',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: HomeScreen(services: services),
    );
  }
}
