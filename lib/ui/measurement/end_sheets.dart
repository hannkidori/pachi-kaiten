import 'package:flutter/material.dart';

import '../../models/machine.dart';
import '../../theme/app_theme.dart';
import '../widgets/counter_field.dart';
import '../widgets/numpad.dart';

BoxDecoration _sheetDeco() => const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    );

Future<T?> _showSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xC2060810),
    builder: (_) => child,
  );
}


// ---------------- リセット(次の台へ急ぐ出口) ----------------

/// リセットシートの選択。
/// - [sameCondition]: 同条件(同 machine_id / クイックなら null)で新セッション。
/// - [changeMachine]: 機種を変えて(機種選択画面へ)。
/// - [quick]: 機種なしで(クイックとして)。
enum ResetChoice { sameCondition, changeMachine, quick }

/// リセットシート。回収額は一切聞かない(記録は「終了」から)。
/// シート外タップ = キャンセル(null)。確認ダイアログは挟まない。
Future<ResetChoice?> showResetSheet(
  BuildContext context, {
  required String machineName,
  required bool isQuick,
}) {
  return _showSheet<ResetChoice>(
    context,
    Container(
      decoration: _sheetDeco(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 主役: 最大。同条件でリセット。
          _gradientButton(
            isQuick ? 'カウントをリセット' : '$machineNameのままリセット',
            height: 58,
            onTap: () => Navigator.pop(context, ResetChoice.sameCondition),
          ),
          const SizedBox(height: 10),
          // 従: 機種を変えて。
          _outlineButton('機種を変えてリセット',
              height: 50,
              onTap: () => Navigator.pop(context, ResetChoice.changeMachine)),
          // 従(小): 機種なしで。クイック中は主役と同義のため出さない。
          if (!isQuick) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => Navigator.pop(context, ResetChoice.quick),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('機種なしでリセット',
                    textAlign: TextAlign.center,
                    style: AppTheme.sans(size: 12.5, color: AppColors.textDim)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Center(
            child: Text('ここまでの計測は足跡に残ります',
                style: AppTheme.sans(size: 10.5, color: AppColors.mutedDark)),
          ),
        ],
      ),
    ),
  );
}

// ---------------- 回収額入力(任意・スキップ可) ----------------

/// 回収額シートの結果。[recovery] が null なら「スキップ」(P/L を記録しない)。
/// シート自体が dismiss された場合は null(= 終了フローを中断)。
class RecoveryResult {
  final int? recovery;
  const RecoveryResult(this.recovery);
}

Future<RecoveryResult?> showRecoverySheet(
  BuildContext context, {
  required String machineName,
  required String rateStr,
  required int totalSpins,
}) {
  return _showSheet<RecoveryResult>(
    context,
    _RecoverySheet(
      machineName: machineName,
      rateStr: rateStr,
      totalSpins: totalSpins,
    ),
  );
}

class _RecoverySheet extends StatefulWidget {
  final String machineName;
  final String rateStr;
  final int totalSpins;
  const _RecoverySheet({
    required this.machineName,
    required this.rateStr,
    required this.totalSpins,
  });

  @override
  State<_RecoverySheet> createState() => _RecoverySheetState();
}

class _RecoverySheetState extends State<_RecoverySheet> {
  String _typed = '';
  bool _expanded = false; // 「＋ 回収額を記録」を展開したか

  @override
  Widget build(BuildContext context) {
    final hasInput = _typed.isNotEmpty;
    // 主役 CTA。回収額を入力していればラベルに (＋回収額を記録) を足す。
    final ctaLabel = hasInput ? '終了する(＋回収額を記録)' : '終了する';
    return Container(
      decoration: _sheetDeco(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('計測を終了',
              style: AppTheme.sans(size: 14, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          // 要約 1 行。
          Text('${widget.machineName} ・ ${widget.rateStr}回/k ・ ${widget.totalSpins}回転',
              style: AppTheme.mono(size: 12, color: AppColors.textStrong)),
          const SizedBox(height: 16),
          // 「＋ 回収額を記録 任意」の折りたたみ行。
          if (!_expanded)
            GestureDetector(
              onTap: () => setState(() => _expanded = true),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.add, size: 15, color: AppColors.muted),
                    const SizedBox(width: 6),
                    Text('回収額を記録',
                        style:
                            AppTheme.sans(size: 12.5, color: AppColors.textDim)),
                    const SizedBox(width: 6),
                    Text('任意',
                        style: AppTheme.sans(
                            size: 10.5, color: AppColors.mutedDark)),
                  ],
                ),
              ),
            )
          else ...[
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                border: Border.all(color: const Color(0x5956D9F0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text('回収',
                      style: AppTheme.sans(size: 10, color: AppColors.muted)),
                  const Spacer(),
                  Text('${_typed.isEmpty ? '0' : _typed}円',
                      style: AppTheme.mono(size: 24, weight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Numpad(
              keyHeight: 44,
              onKey: (k) =>
                  setState(() => _typed = applyKey(_typed, k, maxLen: 7)),
            ),
          ],
          const SizedBox(height: 14),
          // 主役 = 終了する(回収額なしで足跡保存)。入力があれば P/L も記録。
          _gradientButton(
            ctaLabel,
            height: 58,
            onTap: () => Navigator.pop(
                context,
                RecoveryResult(hasInput ? (int.tryParse(_typed) ?? 0) : null)),
          ),
        ],
      ),
    );
  }
}

// ---------------- 新カウンタ入力(リセットの同条件) ----------------
/// [machine] が null ならクイック計測の打ち始め。
Future<int?> showNewCounterSheet(
  BuildContext context, {
  required Machine? machine,
}) {
  return _showSheet<int>(context, _NewCounterSheet(machine: machine));
}

class _NewCounterSheet extends StatefulWidget {
  final Machine? machine;
  const _NewCounterSheet({required this.machine});

  @override
  State<_NewCounterSheet> createState() => _NewCounterSheetState();
}

class _NewCounterSheetState extends State<_NewCounterSheet> {
  String _typed = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _sheetDeco(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.machine?.name ?? '計測',
              style: AppTheme.sans(
                  size: 13,
                  weight: FontWeight.w500,
                  color: widget.machine == null
                      ? AppColors.muted
                      : AppColors.text)),
          const SizedBox(height: 8),
          CounterField(
            typed: _typed,
            prevCounter: null, // 打ち始め=前回「—」
            placeholder: '打ち始めの数字',
          ),
          const SizedBox(height: 10),
          Numpad(
            keyHeight: 44,
            onKey: (k) => setState(() => _typed = applyKey(_typed, k)),
          ),
          const SizedBox(height: 12),
          _primaryButton('この台で計測開始',
              onTap: () => Navigator.pop(context, int.tryParse(_typed) ?? 0)),
        ],
      ),
    );
  }
}

// ---------------- 共有ボタン ----------------
Widget _primaryButton(String label,
    {required VoidCallback onTap, double height = 52}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accentDeep,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(label,
          style: AppTheme.sans(
              size: 16, weight: FontWeight.w700, color: AppColors.accentInk)),
    ),
  );
}

/// 主役ボタン(シアングラデ)。v2 の「終了する」等に使う。
Widget _gradientButton(String label,
    {required VoidCallback onTap, double height = 58}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: AppColors.accentGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      // 機種名を含むラベル(「〇〇のままリセット」)は長くなり得るので、
      // ボタンの外へはみ出さないよう 1 行に収める。
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.sans(
                size: 16, weight: FontWeight.w700, color: AppColors.accentInk)),
      ),
    ),
  );
}

Widget _outlineButton(String label,
    {required VoidCallback onTap, double height = 50}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0x2EFFFFFF)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: AppTheme.sans(size: 13.5, color: AppColors.textStrong)),
    ),
  );
}
