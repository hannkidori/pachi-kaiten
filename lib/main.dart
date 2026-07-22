import 'package:flutter/material.dart';

import 'config.dart';
import 'logic/backup_files.dart';
import 'services/app_services.dart';
import 'theme/app_theme.dart';
import 'ui/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.open();

  // 機種マスタのリモート同期は起動をブロックしない。失敗しても握り潰す
  // (ユーザーには一切見せない。既存マスタは MachineSync 側で保護)。
  if (AppConfig.machinesUrl.isNotEmpty) {
    unawaited(
        services.machineSync.syncFromRemote(AppConfig.machinesUrl, fetch: httpFetch));
  }

  runApp(PachiApp(services: services));
}

/// 明示的に fire-and-forget することを示す。
void unawaited(Future<void> future) {}

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
