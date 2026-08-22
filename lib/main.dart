import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/app_services.dart';
import 'theme/app_theme.dart';
import 'ui/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 縦持ち専用。計測画面は下部にテンキー+決定を固定で積むため、横向きでは
  // 必要な高さを確保できずレイアウトが破綻する。
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  try {
    final services = await AppServices.open();
    // 旧バグで残った空履歴(総回転0)を一掃する(起動時に一度)。
    await services.traces.deleteEmpty();
    runApp(PachiApp(services: services));
  } catch (e) {
    // DB を開けない(破損・容量不足など)場合に無言で落ちると原因が分からない。
    // 最低限の説明を出す。
    runApp(const _StartupErrorApp());
  }
}

/// 起動に失敗したときの最小画面(データを開けなかったことだけ伝える)。
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'データを開けませんでした。\nアプリを再起動してください。',
              textAlign: TextAlign.center,
              style: AppTheme.sans(size: 14, color: AppColors.textDim, height: 1.8),
            ),
          ),
        ),
      ),
    );
  }
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
      // 端末の文字サイズ設定は 1.3 倍までを上限にする。計測画面は固定高の
      // テンキー+決定を積むため、それ以上に拡大すると画面に収まらない。
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: child ?? const SizedBox.shrink(),
      ),
      home: HomeScreen(services: services),
    );
  }
}
