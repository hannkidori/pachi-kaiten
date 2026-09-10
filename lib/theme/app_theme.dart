import 'package:flutter/material.dart';

/// 確定デザイン(design_handoff_pachi_kaiten)から抽出したカラートークン。
///
/// 方針は 3 つ。
/// - 背景は純黒。長時間表示しても電池を食わないよう、面を光らせない。
/// - 発光してよいのは線と文字だけ。塗りは暗い色に留める。
/// - アクセントはミント一色。大当りのアンバーとボーダー未達の赤だけが例外。
class AppColors {
  AppColors._();

  // 背景・面
  static const bg = Color(0xFF000000); // 画面背景(純黒 / OLED 省電力)
  static const surface = Color(0xFF0A0B0D); // ボトムシート
  static const surfaceAlt = Color(0xFF0D0E11); // キー・入力欄・検索欄
  static const keyActive = Color(0xFF1A1C21); // キー押下 / セグメント選択
  static const chipActive = Color(0xFF1A1C21);
  static const sheetKey = Color(0xFF16171B); // シート内キー

  // テキスト
  static const text = Color(0xFFE6E7EA); // 主
  static const textStrong = Color(0xFFC9CBD1); // 準主
  static const textDim = Color(0xFF8A8C93); // 副(戻る矢印など)
  static const muted = Color(0xFF8A8C93); // ラベル・説明
  static const mutedDark = Color(0xFF55575E); // 弱
  static const faint = Color(0xFF33353B); // 最弱・プレースホルダ
  static const subtle = Color(0xFF8A8C93);

  // アクセント(ミント)。面は光らせず、枠線と文字だけに使う。
  static const accent = Color(0xFF38C99A);
  static const accentFill = Color(0xFF0B2A21); // 主要CTAの暗い塗り
  static const accentSoft = Color(0xFF38C99A); // ミント枠内の文字
  static const accentBorderSoft = Color(0xFF2C4A40); // 弱いミント枠
  static const accentGraph = Color(0xFF1F6A53); // グラフのボーダー達成バー
  static const accentHalo = Color(0x0D38C99A); // リング外側の薄いハロー(5%)

  // ボーダー比較: 以上=ミント / 未満=赤
  static const up = accent;
  static const upBorder = accentBorderSoft;
  static const down = Color(0xFFD9736A);
  static const downBorder = Color(0xFF6A342F);
  static const downDim = mutedDark; // グラフ数値(未達)
  static const graphUp = accentGraph;
  static const graphDown = Color(0xFF3A2321);
  static const graphNeutral = Color(0xFF1E2024); // 機種なし(ボーダー不明)

  // 大当り(アンバー)
  static const hit = Color(0xFFF0B64A);
  static const hitBorder = Color(0xFF6A4A0E);
  static const hitText = Color(0xFFF0B64A);
  static const hitButton = Color(0xFFF0B64A);
  static const hitInk = Color(0xFF1C1206);

  // 罫線
  static const border = Color(0xFF2C2E33); // 標準
  static const borderStrong = Color(0xFF33353B); // 強め
  static const hair = Color(0xFF1E2024); // 弱め
  static const hairFaint = Color(0xFF16171B); // 区切り線
}

class AppTheme {
  AppTheme._();

  /// フォントファミリ(pubspec に同梱。通信ゼロなのでランタイム取得はしない)。
  ///
  /// ハンドオフは全文 Noto Sans JP + tabular-nums を指定しているが、数字だけは
  /// IBM Plex Mono を使い続ける。等幅は元から保証されており、既存レイアウトの
  /// 実測値もこの字幅で詰めてあるため、乗り換えると桁揃えと余白を作り直す
  /// ことになる(狙いである「数字が揃う」は同じ形で満たせる)。
  static const fontMono = 'IBM Plex Mono'; // 数字・英字(等幅)
  static const fontJp = 'Noto Sans JP'; // 日本語

  /// 数字・英字が中国語字形へ落ちないよう、日本語は必ず [fontJp] に解決する。
  static const _jpFallback = <String>[fontJp];

  /// 和文フォントが持たない記号(↺ など)を IBM Plex Mono で補うフォールバック。
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

  /// 主要CTA の装飾。暗い塗り + ミント 1.5px 枠(面は光らせない)。
  /// 無効時は塗りを落とし、枠も標準色に戻す。
  static BoxDecoration cta({bool enabled = true, double radius = 16}) {
    return BoxDecoration(
      color: enabled ? AppColors.accentFill : AppColors.surfaceAlt,
      border: Border.all(
          color: enabled ? AppColors.accent : AppColors.border, width: 1.5),
      borderRadius: BorderRadius.circular(radius),
    );
  }

  /// CTA 上の文字色。
  static Color ctaInk(bool enabled) =>
      enabled ? AppColors.text : AppColors.mutedDark;

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.bg,
        primary: AppColors.accent,
        secondary: AppColors.accentGraph,
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
