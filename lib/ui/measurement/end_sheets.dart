import 'package:flutter/material.dart';

import '../../models/machine.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
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
            child: Text('ここまでの計測は履歴に残ります',
                style: AppTheme.sans(size: 10.5, color: AppColors.mutedDark)),
          ),
        ],
      ),
    ),
  );
}

// ---------------- 収支入力(任意・スキップ可) ----------------

/// 収支シートの結果。[invest] / [recovery] は両方揃ったときだけ入る。
/// どちらも null なら「記録しない」(収支なしで履歴だけ残す)。
/// シート自体が dismiss された場合は null(= 終了フローを中断)。
class SettlementResult {
  final int? invest;
  final int? recovery;
  const SettlementResult({this.invest, this.recovery});

  bool get hasSettlement => invest != null && recovery != null;
}

Future<SettlementResult?> showSettlementSheet(
  BuildContext context, {
  required String machineName,
  required String rateStr,
  required int totalSpins,
}) {
  return _showSheet<SettlementResult>(
    context,
    _SettlementSheet(
      machineName: machineName,
      rateStr: rateStr,
      totalSpins: totalSpins,
    ),
  );
}

/// テンキーの入力先。
enum _Field { invest, recovery }

class _SettlementSheet extends StatefulWidget {
  final String machineName;
  final String rateStr;
  final int totalSpins;
  const _SettlementSheet({
    required this.machineName,
    required this.rateStr,
    required this.totalSpins,
  });

  @override
  State<_SettlementSheet> createState() => _SettlementSheetState();
}

class _SettlementSheetState extends State<_SettlementSheet> {
  String _invest = '';
  String _recovery = '';
  _Field _focus = _Field.invest;
  bool _expanded = false; // 「＋ 収支を記録」を展開したか

  /// 収支は「回収 − 投資」。消化額は持ち玉で回した分も含むため基準に使わない。
  /// 片方だけでは意味を成さないので、両方入っているときだけ出す。
  int? get _pl {
    final i = int.tryParse(_invest);
    final r = int.tryParse(_recovery);
    if (i == null || r == null) return null;
    return r - i;
  }

  void _onKey(String k) {
    setState(() {
      if (_focus == _Field.invest) {
        _invest = applyKey(_invest, k, maxLen: 7);
      } else {
        _recovery = applyKey(_recovery, k, maxLen: 7);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pl = _pl;
    final ctaLabel = pl == null ? '終了する' : '終了する(＋収支を記録)';
    return Container(
      decoration: _sheetDeco(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      // 小さい画面でテンキーごと収まらないことがあるためスクロールさせる。
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('計測を終了',
                style: AppTheme.sans(size: 14, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            // 要約 1 行。
            Text(
                '${widget.machineName} ・ ${widget.rateStr}回/k ・ ${widget.totalSpins}回転',
                style: AppTheme.mono(size: 12, color: AppColors.textStrong)),
            const SizedBox(height: 16),
            // 「＋ 収支を記録 任意」の折りたたみ行。
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
                      Text('収支を記録',
                          style: AppTheme.sans(
                              size: 12.5, color: AppColors.textDim)),
                      const SizedBox(width: 6),
                      Text('任意',
                          style: AppTheme.sans(
                              size: 10.5, color: AppColors.mutedDark)),
                    ],
                  ),
                ),
              )
            else ...[
              _amountField(_Field.invest, '投資', _invest),
              const SizedBox(height: 8),
              _amountField(_Field.recovery, '回収', _recovery),
              const SizedBox(height: 8),
              // 両方入るまでは計算しない(片方だけの収支は意味がない)。
              Text(
                pl == null ? '投資と回収の両方で収支を記録します' : '収支 ${fmtYenSigned(pl)}',
                textAlign: TextAlign.right,
                style: pl == null
                    ? AppTheme.sans(size: 10.5, color: AppColors.mutedDark)
                    : AppTheme.mono(
                        size: 14,
                        weight: FontWeight.w600,
                        color: pl >= 0 ? AppColors.up : AppColors.down),
              ),
              const SizedBox(height: 10),
              Numpad(keyHeight: 44, onKey: _onKey),
            ],
            const SizedBox(height: 14),
            // 主役 = 終了する(収支なしで履歴保存)。両方入っていれば収支も記録。
            _gradientButton(
              ctaLabel,
              height: 58,
              onTap: () => Navigator.pop(
                  context,
                  pl == null
                      ? const SettlementResult()
                      : SettlementResult(
                          invest: int.parse(_invest),
                          recovery: int.parse(_recovery))),
            ),
          ],
        ),
      ),
    );
  }

  /// 金額 1 欄。タップで入力先を切り替える(選択中は枠をシアンにする)。
  Widget _amountField(_Field field, String label, String typed) {
    final active = _focus == field;
    return GestureDetector(
      onTap: () => setState(() => _focus = field),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          border: Border.all(
              color: active ? const Color(0x8C56D9F0) : AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(label,
                style: AppTheme.sans(
                    size: 10,
                    color: active ? AppColors.accentSoft : AppColors.muted)),
            const Spacer(),
            Text('${typed.isEmpty ? '0' : typed}円',
                style: AppTheme.mono(
                    size: 22,
                    weight: FontWeight.w500,
                    color: typed.isEmpty ? AppColors.mutedDark : AppColors.text)),
          ],
        ),
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
