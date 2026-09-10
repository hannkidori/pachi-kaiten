import 'package:flutter/material.dart';

/// 遷移アニメーションを持たないページルート。
///
/// 計測の開始/再開のように「前の画面が一瞬見えると残像に見える」経路で使う。
/// 打ちながら片手で操作するアプリなので、待ち時間を作らない意味もある。
Route<T> instantRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, _, _) => builder(context),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}
