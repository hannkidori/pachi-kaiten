import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 確定デザイン(Claude Design プロトタイプ)から抽出したカラートークン。
/// ダークテーマのみ。数字は等幅(IBM Plex Mono)、和文は IBM Plex Sans JP。
class AppColors {
  AppColors._();

  // 背景・面
  static const bg = Color(0xFF0A0C0E); // 画面背景(純黒近く)
  static const surface = Color(0xFF14171B); // カード / キー
  static const surfaceAlt = Color(0xFF101317); // 入力枠 / トグル地
  static const keyActive = Color(0xFF232A32); // キー押下
  static const chipActive = Color(0xFF1E242B);

  // テキスト
  static const text = Color(0xFFE7ECEF); // 主
  static const textStrong = Color(0xFFC6CDD3);
  static const textDim = Color(0xFFB7C0C8);
  static const muted = Color(0xFF7E8A96);
  static const mutedDark = Color(0xFF5A646E);
  static const subtle = Color(0xFF8A94A0);

  // アクセント(氷青)
  static const accent = Color(0xFF6BCBDD);
  static const accentDeep = Color(0xFF2FA8BF); // 決定ボタン地
  static const accentInk = Color(0xFF06171B); // 決定ボタン文字
  static const accentSoft = Color(0xFFA8E0EC);

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
}

class AppTheme {
  AppTheme._();

  /// 等幅(数字用)。google_fonts で IBM Plex Mono。
  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.text,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.ibmPlexMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// 和文用。IBM Plex Sans JP。
  static TextStyle sans({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.text,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.ibmPlexSansJp(
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
      textTheme: GoogleFonts.ibmPlexSansJpTextTheme(base.textTheme)
          .apply(bodyColor: AppColors.text, displayColor: AppColors.text),
      splashFactory: InkRipple.splashFactory,
    );
  }
}
