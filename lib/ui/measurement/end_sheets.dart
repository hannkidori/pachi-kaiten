import 'package:flutter/material.dart';

import '../../models/machine.dart';
import '../../theme/app_theme.dart';
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

Widget _closeButton(BuildContext context) => GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0x1FFFFFFF)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('✕', style: AppTheme.sans(size: 14, color: AppColors.muted)),
      ),
    );

// ---------------- 台移動の確認 ----------------
Future<bool?> showMoveConfirm(
  BuildContext context, {
  required String machineName,
  required String investK,
  required int totalSpins,
}) {
  return _showSheet<bool>(
    context,
    Container(
      decoration: _sheetDeco(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('台移動しますか?',
              style: AppTheme.sans(size: 14, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text('現在のセッションを終了して足跡に記録し、次の台の計測を開始します。',
              style:
                  AppTheme.sans(size: 12, color: AppColors.muted, height: 1.7)),
          const SizedBox(height: 6),
          Text('$machineName ・ 消化 $investK分 ・ $totalSpins回転',
              style: AppTheme.mono(size: 12, color: AppColors.textStrong)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 13,
                child: _lightButton('台移動する',
                    onTap: () => Navigator.pop(context, true)),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 10,
                child: _outlineButton('続ける',
                    onTap: () => Navigator.pop(context, false)),
              ),
            ],
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
  required bool forMove,
  required String machineName,
  required String rateStr,
  required int totalSpins,
}) {
  return _showSheet<RecoveryResult>(
    context,
    _RecoverySheet(
      forMove: forMove,
      machineName: machineName,
      rateStr: rateStr,
      totalSpins: totalSpins,
    ),
  );
}

class _RecoverySheet extends StatefulWidget {
  final bool forMove;
  final String machineName;
  final String rateStr;
  final int totalSpins;
  const _RecoverySheet({
    required this.forMove,
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
    final base = widget.forMove ? '終了して移動' : '終了する';
    final ctaLabel = hasInput ? '$base(＋回収額を記録)' : base;
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

// ---------------- 機種選択(台移動時) ----------------

/// 機種選択の結果。[register] が true なら「新しい機種を登録」を要求。
/// それ以外は [machine] が選択された機種。
class MachinePick {
  final Machine? machine;
  final bool register;
  const MachinePick.select(Machine this.machine) : register = false;
  const MachinePick.registerNew()
      : machine = null,
        register = true;
}

Future<MachinePick?> showMachinePick(
  BuildContext context, {
  required List<Machine> machines,
  required Machine? sameMachine, // null=クイック計測からの移動(同じ機種なし)
  required double ballPrice,
}) {
  return _showSheet<MachinePick>(
    context,
    _MachinePickSheet(
      machines: machines,
      sameMachine: sameMachine,
      ballPrice: ballPrice,
    ),
  );
}

class _MachinePickSheet extends StatefulWidget {
  final List<Machine> machines;
  final Machine? sameMachine;
  final double ballPrice;
  const _MachinePickSheet({
    required this.machines,
    required this.sameMachine,
    required this.ballPrice,
  });

  @override
  State<_MachinePickSheet> createState() => _MachinePickSheetState();
}

class _MachinePickSheetState extends State<_MachinePickSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.machines
        : widget.machines
            .where((m) => m.name.toLowerCase().contains(q))
            .toList();
    return Container(
      decoration: _sheetDeco(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('次の台 — 機種を選択',
                  style: AppTheme.sans(size: 14, weight: FontWeight.w700)),
              const Spacer(),
              _closeButton(context),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            style: AppTheme.sans(size: 14),
            cursorColor: AppColors.accent,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon:
                  const Icon(Icons.search, size: 18, color: AppColors.muted),
              hintText: '機種名を検索…',
              hintStyle: AppTheme.sans(size: 13, color: AppColors.mutedDark),
              filled: true,
              fillColor: AppColors.surfaceAlt,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Color(0x5956D9F0)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (widget.sameMachine != null) ...[
            _sameMachineRow(widget.sameMachine!),
            const SizedBox(height: 8),
          ],
          _registerRow(),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _machineRow(list[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sameMachineRow(Machine sameMachine) {
    return GestureDetector(
      onTap: () =>
          Navigator.pop(context, MachinePick.select(sameMachine)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x1456D9F0),
          border: Border.all(color: const Color(0x7356D9F0)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sameMachine.name,
                style: AppTheme.sans(size: 13, weight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text('同じ機種 — ワンタップで開始',
                style: AppTheme.sans(size: 10.5, color: AppColors.accent)),
          ],
        ),
      ),
    );
  }

  Widget _registerRow() {
    return GestureDetector(
      onTap: () => Navigator.pop(context, const MachinePick.registerNew()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0x396BCBDD)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.add, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Text('新しい機種を登録',
                style: AppTheme.sans(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: AppColors.accentSoft)),
          ],
        ),
      ),
    );
  }

  Widget _machineRow(Machine m) {
    final border = m.borderFor(widget.ballPrice);
    return GestureDetector(
      onTap: () => Navigator.pop(context, MachinePick.select(m)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(m.name,
                  style: AppTheme.sans(size: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Text(border == null ? '未設定' : 'B${border.toStringAsFixed(1)}',
                style: AppTheme.mono(
                    size: 11,
                    color:
                        border == null ? AppColors.mutedDark : AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

// ---------------- 新カウンタ入力 ----------------
Future<int?> showNewCounterSheet(
  BuildContext context, {
  required Machine machine,
}) {
  return _showSheet<int>(context, _NewCounterSheet(machine: machine));
}

class _NewCounterSheet extends StatefulWidget {
  final Machine machine;
  const _NewCounterSheet({required this.machine});

  @override
  State<_NewCounterSheet> createState() => _NewCounterSheetState();
}

class _NewCounterSheetState extends State<_NewCounterSheet> {
  String _typed = '';

  @override
  Widget build(BuildContext context) {
    final display = _typed.isEmpty ? '0' : _typed;
    return Container(
      decoration: _sheetDeco(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.machine.name,
              style: AppTheme.sans(size: 13, weight: FontWeight.w500)),
          const SizedBox(height: 8),
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
                Text('打ち始めカウンタ',
                    style: AppTheme.sans(size: 10, color: AppColors.muted)),
                const Spacer(),
                Text(display,
                    style: AppTheme.mono(size: 24, weight: FontWeight.w500)),
              ],
            ),
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
      child: Text(label,
          style: AppTheme.sans(
              size: 16, weight: FontWeight.w700, color: AppColors.accentInk)),
    ),
  );
}

Widget _lightButton(String label,
    {required VoidCallback onTap, double height = 50}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: AppTheme.sans(
              size: 15, weight: FontWeight.w700, color: AppColors.lightInk)),
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
