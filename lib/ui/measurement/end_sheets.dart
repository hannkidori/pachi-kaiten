import 'package:flutter/material.dart';

import '../../logic/rotation_calc.dart';
import '../../models/machine.dart';
import '../../models/session.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../widgets/numpad.dart';

/// 終了/台移動で確定したセッションのサマリー材料。
class SessionSummary {
  final Session session;
  final Machine machine;
  final RotationStats stats;
  const SessionSummary({
    required this.session,
    required this.machine,
    required this.stats,
  });

  int get invest => stats.cashInvest;
  int get recovery => session.recovery ?? 0;
  int get profit => recovery - invest;
  double? get ev => stats.expectedValue;
}

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
          Text('現在のセッションを終了して収支に記録し、次の台の計測を開始します。',
              style:
                  AppTheme.sans(size: 12, color: AppColors.muted, height: 1.7)),
          const SizedBox(height: 6),
          Text('$machineName ・ 投資 $investK ・ $totalSpins回転',
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

// ---------------- 回収額入力 ----------------
Future<int?> showRecoverySheet(
  BuildContext context, {
  required bool forMove,
}) {
  return _showSheet<int>(
    context,
    _RecoverySheet(forMove: forMove),
  );
}

class _RecoverySheet extends StatefulWidget {
  final bool forMove;
  const _RecoverySheet({required this.forMove});

  @override
  State<_RecoverySheet> createState() => _RecoverySheetState();
}

class _RecoverySheetState extends State<_RecoverySheet> {
  String _typed = '';

  @override
  Widget build(BuildContext context) {
    final title = widget.forMove
        ? '台移動 — この台の回収額'
        : 'セッション終了 — 回収額を入力';
    final sub = widget.forMove
        ? '現セッションを終了して収支に記録し、次の台へ進みます'
        : '回収額を入力すると収支レコードが完成します';
    final cta = widget.forMove ? '記録して次の台へ' : '収支を確定';
    final display = _typed.isEmpty ? '0' : _typed;
    return Container(
      decoration: _sheetDeco(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(title,
                  style: AppTheme.sans(size: 14, weight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0x1FFFFFFF)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('✕',
                      style:
                          AppTheme.sans(size: 14, color: AppColors.muted)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(sub, style: AppTheme.sans(size: 11, color: AppColors.muted)),
          const SizedBox(height: 10),
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              border: Border.all(color: const Color(0x596BCBDD)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text('回収',
                    style: AppTheme.sans(size: 10, color: AppColors.muted)),
                const Spacer(),
                Text('$display円',
                    style: AppTheme.mono(size: 24, weight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _outlineButton('回収なし ¥0',
              height: 42, onTap: () => Navigator.pop(context, 0)),
          const SizedBox(height: 10),
          Numpad(
            keyHeight: 44,
            onKey: (k) =>
                setState(() => _typed = applyKey(_typed, k, maxLen: 7)),
          ),
          const SizedBox(height: 12),
          _primaryButton(cta,
              onTap: () =>
                  Navigator.pop(context, int.tryParse(_typed) ?? 0)),
        ],
      ),
    );
  }
}

// ---------------- 機種選択(先頭に同じ機種) ----------------
Future<Machine?> showMachinePick(
  BuildContext context, {
  required List<Machine> machines,
  required Machine sameMachine,
  required double exchangeRate,
}) {
  return _showSheet<Machine>(
    context,
    _MachinePickSheet(
      machines: machines,
      sameMachine: sameMachine,
      exchangeRate: exchangeRate,
    ),
  );
}

class _MachinePickSheet extends StatefulWidget {
  final List<Machine> machines;
  final Machine sameMachine;
  final double exchangeRate;
  const _MachinePickSheet({
    required this.machines,
    required this.sameMachine,
    required this.exchangeRate,
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
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0x1FFFFFFF)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('✕',
                      style:
                          AppTheme.sans(size: 14, color: AppColors.muted)),
                ),
              ),
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
                borderSide: const BorderSide(color: Color(0x596BCBDD)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 先頭に「同じ機種 — ワンタップで開始」。
          _sameMachineRow(),
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

  Widget _sameMachineRow() {
    return GestureDetector(
      onTap: () => Navigator.pop(context, widget.sameMachine),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x146BCBDD),
          border: Border.all(color: const Color(0x736BCBDD)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.sameMachine.name,
                style: AppTheme.sans(size: 13, weight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text('同じ機種 — ワンタップで開始',
                style: AppTheme.sans(size: 10.5, color: AppColors.accent)),
          ],
        ),
      ),
    );
  }

  Widget _machineRow(Machine m) {
    final border = m.borderForRate(widget.exchangeRate);
    return GestureDetector(
      onTap: () => Navigator.pop(context, m),
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
            Text('1/${m.probability} ・ B${border.toStringAsFixed(1)}',
                style: AppTheme.mono(size: 11, color: AppColors.muted)),
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
              border: Border.all(color: const Color(0x596BCBDD)),
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

// ---------------- サマリー ----------------
Future<void> showSummarySheet(BuildContext context, SessionSummary sum) {
  final rate = sum.stats.rotationRate;
  final ev = sum.ev;
  final profit = sum.profit;
  final evColor = (ev ?? 0) >= 0 ? AppColors.up : AppColors.down;
  final balColor = profit >= 0 ? AppColors.up : AppColors.down;
  return _showSheet<void>(
    context,
    Container(
      decoration: _sheetDeco(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('セッションサマリー',
              style: AppTheme.sans(size: 14, weight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(
            children: [
              _statTile('回転率', fmtRate(rate), unit: ' 回/k'),
              const SizedBox(width: 10),
              _statTile('総投資', fmtYen(sum.invest)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statTile('回収', fmtYen(sum.recovery)),
              const SizedBox(width: 10),
              _statTile('総回転', '${sum.stats.totalRotations}', unit: ' 回'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _bigTile('期待値', ev == null ? '--' : fmtYenSigned(ev), evColor),
              const SizedBox(width: 10),
              _bigTile('実収支', fmtYenSigned(profit), balColor),
            ],
          ),
          const SizedBox(height: 12),
          if (ev != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: ev >= 0 ? const Color(0x1A3ECF8E) : const Color(0x1AF06A5D),
                border: Border.all(
                    color: ev >= 0
                        ? const Color(0x403ECF8E)
                        : const Color(0x40F06A5D)),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                ev >= 0
                    ? '判断は期待値プラスでした — 結果と独立に、正しい台選びです'
                    : '期待値マイナスの台でした — 台選びを見直す余地があります',
                style: AppTheme.sans(size: 12, color: evColor, height: 1.5),
              ),
            ),
          if (ev != null) const SizedBox(height: 10),
          if (ev != null)
            Text.rich(TextSpan(children: [
              TextSpan(
                  text: '期待値との乖離 ',
                  style: AppTheme.sans(size: 11, color: AppColors.muted)),
              TextSpan(
                  text: fmtYenSigned(profit - ev.round()),
                  style: AppTheme.mono(size: 11, color: AppColors.textStrong)),
            ])),
          const SizedBox(height: 14),
          _outlineButton('閉じる',
              height: 44, onTap: () => Navigator.pop(context)),
        ],
      ),
    ),
  );
}

Widget _statTile(String label, String value, {String unit = ''}) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.hair),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.sans(size: 9.5, color: AppColors.muted)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: value,
                  style: AppTheme.mono(size: 17, weight: FontWeight.w600)),
              TextSpan(
                  text: unit,
                  style: AppTheme.sans(size: 10, color: AppColors.muted)),
            ])),
          ),
        ],
      ),
    ),
  );
}

Widget _bigTile(String label, String value, Color color) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(color: const Color(0x1AFFFFFF)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.sans(size: 9.5, color: AppColors.muted)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: AppTheme.mono(
                    size: 21, weight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    ),
  );
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
              size: 14.5, weight: FontWeight.w700, color: AppColors.lightInk)),
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
