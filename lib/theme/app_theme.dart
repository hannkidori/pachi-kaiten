import 'package:flutter/material.dart';

/// 確定デザイン(Claude Design ハンドオフ v2)から抽出したカラートークン。
/// ダークテーマのみ。数字は等幅(IBM Plex Mono)、和文は Noto Sans JP。
class AppColors {
  AppColors._();

  // 背景・面
  static const bg = Color(0xFF08090B); // 画面背景(ほぼ純黒)
  static const surface = Color(0xFF11161A); // キー / シート / カード面
  static const surfaceAlt = Color(0xFF0E1214); // 入力欄 / チップ内背景
  static const keyActive = Color(0xFF1E262C); // キー押下
  static const chipActive = Color(0xFF1E262C);

  // テキスト
  static const text = Color(0xFFE9EEF1); // 主
  static const textStrong = Color(0xFFC6CDD3);
  static const textDim = Color(0xFFB7C0C8);
  static const muted = Color(0xFF7E8A96); // ラベル・説明
  static const mutedDark = Color(0xFF5A646E); // 最弱
  static const faint = Color(0xFF3A424B); // プレースホルダ
  static const subtle = Color(0xFF8A94A0);

  // アクセント(氷青シアン)
  static const accent = Color(0xFF56D9F0); // カーソル・選択・最新棒・ドット
  static const accentDeep = Color(0xFF35C3DF); // 塗りボタン(決定・保存)
  static const accentInk = Color(0xFF04262E); // シアンボタン上の文字(on-accent)
  static const accentSoft = Color(0xFFA9E7F2); // シアン枠内の文字(tintText)
  // 主役ボタン(計測スタート・終了する)のグラデーション(180deg)。
  static const accentGradTop = Color(0xFF66E0F5);
  static const accentGradBottom = Color(0xFF2FBBD9);

  // ボーダー上=緑 / 下=赤
  static const up = Color(0xFF3ECF8E);
  static const down = Color(0xFFF06A5D);
  static const downDim = Color(0xFF9C5B54); // ボーダー未満の減光赤(グラフ数字)

  // 大当り(金)
  static const hit = Color(0xFFE3B168);
  static const hitText = Color(0xFFF0D5A8);
  static const hitButton = Color(0xFFD9A85C);
  static const hitInk = Color(0xFF1C1206);

  // 台移動 / 計測開始(明色ボタン)
  static const light = Color(0xFFE9EDF0);
  static const lightInk = Color(0xFF0B0D10);

  // 罫線
  static const hair = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
  static const hairFaint = Color(0x0FFFFFFF); // 0.06
  static const border = Color(0x17FFFFFF); // 0.09

  /// 主役ボタンのグラデーション(上→下)。
  static const accentGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [accentGradTop, accentGradBottom],
  );
}

class AppTheme {
  AppTheme._();

  /// フォントファミリ(pubspec に同梱。通信ゼロなのでランタイム取得はしない)。
  static const fontMono = 'IBM Plex Mono'; // 数字・英字(等幅)
  static const fontJp = 'Noto Sans JP'; // 日本語

  /// 数字・英字が中国語字形へ落ちないよう、日本語は必ず [fontJp] に解決する。
  static const _jpFallback = <String>[fontJp];

  /// 和文フォントが持たない記号(↺ など)を IBM Plex Mono で補うフォールバック。
  /// 日本語は [fontJp] が全て持つため mono へ落ちることはない。
  static const _monoFallback = <String>[fontMono];

  /// 等幅(数字用)。IBM Plex Mono。日本語混在時は Noto Sans JP にフォールバック。
  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.text,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: fontMono,
      fontFamilyFallback: _jpFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// 和文用。Noto Sans JP。
  static TextStyle sans({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.text,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: fontJp,
      fontFamilyFallback: _monoFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.bg,
        primary: AppColors.accent,
        secondary: AppColors.accentDeep,
      ),
      // 既定フォントも日本語(Noto Sans JP)にし、素の Text も中国語字形へ落ちない。
      textTheme: base.textTheme.apply(
        fontFamily: fontJp,
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      splashFactory: InkRipple.splashFactory,
    );
  }
}
