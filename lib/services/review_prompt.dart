import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../models/entry.dart';
import '../repositories/entry_repository.dart';
import '../repositories/settings_repository.dart';

/// レビュー依頼を出す「決定(回転数入力)の累計回数」のしきい値。
///
/// 3 段階で打ち止め。iOS は同じアプリのレビュー依頼を 365 日あたり最大 3 回まで
/// しか表示しないため、段数をそれに合わせてある。
const List<int> kReviewMilestones = [50, 500, 1000];

/// 累計入力回数 [count] と消化済み段階 [stage] から、いま依頼を出すかを決める。
///
/// [stage] は「すでに何回依頼したか」。全段消化後は二度と出さない。
bool shouldRequestReview({required int count, required int stage}) {
  if (stage < 0 || stage >= kReviewMilestones.length) return false;
  return count >= kReviewMilestones[stage];
}

/// App Store のレビュー依頼(星評価ダイアログ)を出す。iOS 専用。
///
/// OS 側の仕様として「表示されたか」「星を付けたか」「閉じたか」はアプリから
/// 一切取得できない。そのため『拒否されたら次』という分岐は作れず、しきい値に
/// 到達するたびに 1 回ずつ、[kReviewMilestones] の 3 回で打ち止めにしている。
/// (すでに評価済みのユーザーには OS がダイアログ自体を出さない)
class ReviewPrompt {
  static const MethodChannel channel = MethodChannel('pachi_kaiten/review');

  final EntryRepository entries;
  final SettingsRepository settings;

  ReviewPrompt({required this.entries, required this.settings});

  /// 計測画面から戻ってきた直後などの「区切り」で呼ぶ。条件を満たさなければ何もしない。
  /// 依頼を投げたら true。
  Future<bool> maybeRequest() async {
    if (!Platform.isIOS) return false; // Android は対象外
    final stage = await settings.reviewStage();
    if (stage >= kReviewMilestones.length) return false; // 打ち止め済み
    final count = await entries.countOfType(EntryType.count);
    if (!shouldRequestReview(count: count, stage: stage)) return false;
    // 表示結果を受け取れない以上、投げる前に段を進めておく(失敗しても再試行して
    // 何度も出すより、1 段消費して静かにやめる方が害が小さい)。
    await settings.setReviewStage(stage + 1);
    try {
      await channel.invokeMethod<bool>('requestReview');
    } on PlatformException {
      // OS 側で出せなくても計測の邪魔はしない。
      return false;
    } on MissingPluginException {
      return false;
    }
    return true;
  }
}
