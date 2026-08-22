import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../models/entry.dart';
import '../models/trace.dart';
import '../repositories/entry_repository.dart';
import '../repositories/settings_repository.dart';

/// レビュー依頼の「資格」を得る、決定(回転数入力)の累計回数。
///
/// 3 段階で打ち止め。iOS は同じアプリのレビュー依頼を 365 日あたり最大 3 回まで
/// しか表示しないため、段数をそれに合わせてある。
const List<int> kReviewMilestones = [50, 500, 1000];

/// 依頼の対象にする最低総回転数。少し回しただけの計測では評価を求めない。
const int kReviewMinRotations = 100;

/// 資格を得たあと、ボーダー超えが来ないまま何回の計測終了で妥協するか。
const int kReviewFallbackEnds = 5;

/// 資格の有無。[count] は決定の累計、[stage] はすでに依頼した回数。
bool hasReviewQualification({required int count, required int stage}) {
  if (stage < 0 || stage >= kReviewMilestones.length) return false;
  return count >= kReviewMilestones[stage];
}

/// 資格がある状態で計測を 1 回終えたときの判断。
/// - [show]   : いま依頼を出す
/// - [wait]   : 見送って次の計測を待つ(待ち回数を 1 消費)
/// - [ignore] : 短すぎる計測。待ち回数にも数えない
enum ReviewAction { show, wait, ignore }

/// 依頼を出すのは「ボーダーを超えた台で終えた直後」= 気分が良く、かつ
/// アプリの手柄と感じられる瞬間。負けた直後に出して星を落とさないための判断。
/// ただし好条件が来ないまま [kReviewFallbackEnds] 回終えたら妥協して出す。
///
/// [borderDiff] は R−B。ボーダー未登録やクイック計測では null。
ReviewAction decideAfterMeasurement({
  required int totalRotations,
  required double? borderDiff,
  required int waited,
}) {
  if (totalRotations < kReviewMinRotations) return ReviewAction.ignore;
  if (borderDiff != null && borderDiff > 0) return ReviewAction.show;
  if (waited + 1 >= kReviewFallbackEnds) return ReviewAction.show;
  return ReviewAction.wait;
}

/// App Store のレビュー依頼(星評価ダイアログ)を出す。iOS 専用。
///
/// OS 側の仕様として「表示されたか」「星を付けたか」「閉じたか」はアプリから
/// 一切取得できない。そのため『拒否されたら次』という分岐は作れず、しきい値に
/// 到達するたびに 1 回ずつ、[kReviewMilestones] の 3 回で打ち止めにしている。
/// (すでに評価を送信した人には OS がダイアログ自体を出さない)
class ReviewPrompt {
  static const MethodChannel channel = MethodChannel('pachi_kaiten/review');

  final EntryRepository entries;
  final SettingsRepository settings;

  ReviewPrompt({required this.entries, required this.settings});

  /// 計測が終わって履歴が 1 件保存された直後に呼ぶ。依頼を投げたら true。
  /// 条件を満たさなければ何もしない(計測中には呼ばない)。
  Future<bool> onMeasurementEnded(Trace trace) async {
    if (!Platform.isIOS) return false; // Android は対象外
    final stage = await settings.reviewStage();
    if (stage >= kReviewMilestones.length) return false; // 打ち止め済み
    final count = await entries.countOfType(EntryType.count);
    if (!hasReviewQualification(count: count, stage: stage)) return false;

    final waited = await settings.reviewWaited();
    final action = decideAfterMeasurement(
      totalRotations: trace.totalRotations,
      borderDiff: trace.borderDiff,
      waited: waited,
    );
    switch (action) {
      case ReviewAction.ignore:
        return false;
      case ReviewAction.wait:
        await settings.setReviewWaited(waited + 1);
        return false;
      case ReviewAction.show:
        // 表示結果を受け取れない以上、投げる前に段を進めておく(失敗しても再試行
        // して何度も出すより、1 段消費して静かにやめる方が害が小さい)。
        await settings.setReviewStage(stage + 1);
        await settings.setReviewWaited(0);
        try {
          await channel.invokeMethod<bool>('requestReview');
        } on PlatformException {
          return false; // OS 側で出せなくても計測の邪魔はしない
        } on MissingPluginException {
          return false;
        }
        return true;
    }
  }
}
