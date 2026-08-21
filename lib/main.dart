import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/app_services.dart';
import 'theme/app_theme.dart';
import 'ui/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.open();
  // 旧バグで残った空足跡(総回転0)を一掃する(起動時に一度)。
  await services.traces.deleteEmpty();
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
      // 端末の言語設定に関わらず日本語で固定する(日本のホール専用アプリ)。
      // テキスト選択メニュー等のシステム文言もこれで日本語になる。
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomeScreen(services: services),
    );
  }
}
