import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/machine.dart';
import '../../theme/app_theme.dart';

/// 貸玉単価の表示ラベル。4.0→「4円」, 1.0→「1円」。
String ballLabel(double ballPrice) => ballPrice <= 1.5 ? '1円' : '4円';

/// 機種に対し、貸玉に応じたスロットへボーダーを書き込んだコピーを返す。
/// 自動換算はしない(4円用・1円用は独立)。
Machine applyBorder(Machine m, double ballPrice, double value, String stamp) {
  return ballPrice <= 1.5
      ? m.copyWith(border1: value, updatedAt: stamp)
      : m.copyWith(border4: value, updatedAt: stamp);
}

/// 新しい機種を登録する(名前 + 現在の貸玉スロットのボーダー1値)。
/// 確定すると (name, border) を返す。キャンセルは null。
Future<({String name, double border})?> showRegisterMachine(
  BuildContext context, {
  required double ballPrice,
}) {
  return showModalBottomSheet<({String name, double border})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MachineFormSheet(ballPrice: ballPrice),
  );
}

/// 機種編集の結果(設定画面)。[saved] は保存後の機種、[deleted] なら削除された。
class MachineEditResult {
  final Machine? saved;
  final bool deleted;
  const MachineEditResult({this.saved, this.deleted = false});
}

/// 機種の編集・削除(設定画面)。名前 + 4円/1円ボーダーの両スロットを編集できる。
Future<MachineEditResult?> showMachineEdit(
  BuildContext context, {
  required Machine machine,
}) {
  return showModalBottomSheet<MachineEditResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MachineEditSheet(machine: machine),
  );
}

/// 既存機種の該当スロットのボーダーを入力/上書きする。
/// [current] があれば初期値に。確定すると入力値を返す。キャンセルは null。
Future<double?> showBorderPrompt(
  BuildContext context, {
  required String machineName,
  required double ballPrice,
  double? current,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BorderPromptSheet(
      machineName: machineName,
      ballPrice: ballPrice,
      current: current,
    ),
  );
}

BoxDecoration _sheetDeco() => const BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    );

Widget _grip() => Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );

InputDecoration _fieldDeco(String hint) => InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: AppTheme.sans(size: 13, color: AppColors.mutedDark),
      filled: true,
      fillColor: AppColors.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: Color(0x596BCBDD)),
      ),
    );

Widget _primaryButton(String label, VoidCallback? onTap) {
  final enabled = onTap != null;
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // 有効=シアン、無効=暗いグレー(押せないことを配色で明示)。
        color: enabled ? AppColors.accentDeep : AppColors.surface,
        border: enabled ? null : Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: AppTheme.sans(
              size: 15,
              weight: FontWeight.w700,
              color: enabled ? AppColors.accentInk : AppColors.mutedDark)),
    ),
  );
}

/// 新規登録フォーム(名前 + ボーダー1値)。
class _MachineFormSheet extends StatefulWidget {
  final double ballPrice;
  const _MachineFormSheet({required this.ballPrice});

  @override
  State<_MachineFormSheet> createState() => _MachineFormSheetState();
}

class _MachineFormSheetState extends State<_MachineFormSheet> {
  final _name = TextEditingController();
  final _border = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _border.dispose();
    super.dispose();
  }

  bool get _valid {
    final b = double.tryParse(_border.text.trim());
    return _name.text.trim().isNotEmpty && b != null && b > 0;
  }

  void _submit() {
    final b = double.tryParse(_border.text.trim());
    if (_name.text.trim().isEmpty || b == null || b <= 0) return;
    Navigator.of(context).pop((name: _name.text.trim(), border: b));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: _sheetDeco(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grip(),
            Text('新しい機種を登録',
                style: AppTheme.sans(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('ボーダーは今の貸玉(${ballLabel(widget.ballPrice)})用として保存されます',
                style: AppTheme.sans(size: 11, color: AppColors.muted)),
            const SizedBox(height: 16),
            Text('機種名', style: AppTheme.sans(size: 11, color: AppColors.muted)),
            const SizedBox(height: 6),
            TextField(
              controller: _name,
              autofocus: true,
              style: AppTheme.sans(size: 14),
              cursorColor: AppColors.accent,
              onChanged: (_) => setState(() {}),
              decoration: _fieldDeco('例: ハネデリ'),
            ),
            const SizedBox(height: 14),
            Text('ボーダー (回/k・${ballLabel(widget.ballPrice)})',
                style: AppTheme.sans(size: 11, color: AppColors.muted)),
            const SizedBox(height: 6),
            TextField(
              controller: _border,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: AppTheme.mono(size: 16),
              cursorColor: AppColors.accent,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: _fieldDeco('例: 18.3'),
            ),
            const SizedBox(height: 20),
            _primaryButton('登録して計測開始', _valid ? _submit : null),
          ],
        ),
      ),
    );
  }
}

/// 既存機種のスロット別ボーダー入力(未設定時の要求・上書き編集で共用)。
class _BorderPromptSheet extends StatefulWidget {
  final String machineName;
  final double ballPrice;
  final double? current;
  const _BorderPromptSheet({
    required this.machineName,
    required this.ballPrice,
    required this.current,
  });

  @override
  State<_BorderPromptSheet> createState() => _BorderPromptSheetState();
}

class _BorderPromptSheetState extends State<_BorderPromptSheet> {
  late final TextEditingController _border =
      TextEditingController(text: widget.current?.toString() ?? '');

  @override
  void dispose() {
    _border.dispose();
    super.dispose();
  }

  bool get _valid {
    final b = double.tryParse(_border.text.trim());
    return b != null && b > 0;
  }

  void _submit() {
    final b = double.tryParse(_border.text.trim());
    if (b == null || b <= 0) return;
    Navigator.of(context).pop(b);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final label = ballLabel(widget.ballPrice);
    final title = widget.current == null
        ? '$label のボーダーを入力'
        : '$label のボーダーを編集';
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: _sheetDeco(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grip(),
            Text(title, style: AppTheme.sans(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(widget.machineName,
                style: AppTheme.sans(size: 12, color: AppColors.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            TextField(
              controller: _border,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: AppTheme.mono(size: 18),
              cursorColor: AppColors.accent,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: _fieldDeco('例: 18.3'),
            ),
            const SizedBox(height: 20),
            _primaryButton('保存', _valid ? _submit : null),
          ],
        ),
      ),
    );
  }
}

/// 機種の編集・削除フォーム(名前 + 4円/1円ボーダーの両スロット)。
class _MachineEditSheet extends StatefulWidget {
  final Machine machine;
  const _MachineEditSheet({required this.machine});

  @override
  State<_MachineEditSheet> createState() => _MachineEditSheetState();
}

class _MachineEditSheetState extends State<_MachineEditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.machine.name);
  late final TextEditingController _b4 =
      TextEditingController(text: widget.machine.border4?.toString() ?? '');
  late final TextEditingController _b1 =
      TextEditingController(text: widget.machine.border1?.toString() ?? '');

  // 「この機種を削除」の 2 度タップ確認。1 回目で arm → 2.6s で解除。
  bool _deleteArmed = false;
  Timer? _deleteTimer;

  @override
  void dispose() {
    _deleteTimer?.cancel();
    _name.dispose();
    _b4.dispose();
    _b1.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    return (v != null && v > 0) ? v : null;
  }

  bool get _valid {
    final name = _name.text.trim();
    // ボーダー欄が入力されている場合は正の数であること。少なくとも1スロット必須。
    final b4ok = _b4.text.trim().isEmpty || _parse(_b4) != null;
    final b1ok = _b1.text.trim().isEmpty || _parse(_b1) != null;
    final atLeastOne = _parse(_b4) != null || _parse(_b1) != null;
    return name.isNotEmpty && b4ok && b1ok && atLeastOne;
  }

  void _save() {
    if (!_valid) return;
    final saved = Machine(
      id: widget.machine.id,
      name: _name.text.trim(),
      border4: _parse(_b4),
      border1: _parse(_b1),
      updatedAt: widget.machine.updatedAt,
    );
    Navigator.of(context).pop(MachineEditResult(saved: saved));
  }

  /// 削除 = 2 度タップ確認。1 回目は arm するだけ、2 回目で実行。
  void _tapDelete() {
    if (!_deleteArmed) {
      setState(() => _deleteArmed = true);
      _deleteTimer?.cancel();
      _deleteTimer = Timer(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() => _deleteArmed = false);
      });
      return;
    }
    _deleteTimer?.cancel();
    Navigator.of(context).pop(const MachineEditResult(deleted: true));
  }

  Widget _borderField(String label, TextEditingController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.sans(size: 11, color: AppColors.muted)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTheme.mono(size: 16),
          cursorColor: AppColors.accent,
          onChanged: (_) => setState(() {}),
          decoration: _fieldDeco('未設定'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: _sheetDeco(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grip(),
            Text('機種を編集',
                style: AppTheme.sans(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: 16),
            Text('機種名', style: AppTheme.sans(size: 11, color: AppColors.muted)),
            const SizedBox(height: 6),
            TextField(
              controller: _name,
              style: AppTheme.sans(size: 14),
              cursorColor: AppColors.accent,
              onChanged: (_) => setState(() {}),
              decoration: _fieldDeco('機種名'),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _borderField('ボーダー (4円)', _b4)),
                const SizedBox(width: 12),
                Expanded(child: _borderField('ボーダー (1円)', _b1)),
              ],
            ),
            const SizedBox(height: 20),
            _primaryButton('保存', _valid ? _save : null),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _tapDelete,
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      _deleteArmed ? const Color(0x1FF06A5D) : Colors.transparent,
                  border: Border.all(color: const Color(0x40F06A5D)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_deleteArmed ? 'もう一度タップで削除' : 'この機種を削除',
                    style: AppTheme.sans(
                        size: 14, weight: FontWeight.w600, color: AppColors.down)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('削除しても足跡は消えません',
                  style: AppTheme.sans(size: 10.5, color: AppColors.mutedDark)),
            ),
          ],
        ),
      ),
    );
  }
}
