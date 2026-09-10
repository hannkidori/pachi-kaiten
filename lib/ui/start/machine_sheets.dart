import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/machine.dart';
import '../../theme/app_theme.dart';
import '../widgets/counter_field.dart';
import '../widgets/numpad.dart';

/// 貸玉単価の表示ラベル。4.0→「4円」, 1.0→「1円」。
String ballLabel(double ballPrice) => ballPrice <= 1.5 ? '1円' : '4円';

/// ボーダー(回/k)の上限。1円パチでも 90 程度なので十分な余裕を見た値。
const double kBorderMax = 200;

/// 機種名の最大文字数(長すぎる名前によるレイアウト破綻を防ぐ)。
const int kMachineNameMaxLength = 40;

/// ボーダー入力の解析。不正値は null を返す。
///
/// `double.tryParse('Infinity')` は Infinity を返すため、`> 0` だけの検査では
/// 素通りしてしまい、期待値計算が NaN になって計測画面・ホームが落ちる
/// (ホームは _loading のまま復帰不能になる)。isFinite と上限で必ず弾く。
double? parseBorder(String text) {
  final v = double.tryParse(text.trim());
  if (v == null || !v.isFinite || v <= 0 || v > kBorderMax) return null;
  return v;
}

/// ボーダー入力欄の入力制限(数字と小数点のみ・桁数制限)。
final List<TextInputFormatter> borderInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  LengthLimitingTextInputFormatter(5), // 例: 199.9
];

/// 機種名入力欄の入力制限(長さのみ)。
final List<TextInputFormatter> machineNameInputFormatters = [
  LengthLimitingTextInputFormatter(kMachineNameMaxLength),
];

/// 機種に対し、貸玉に応じたスロットへボーダーを書き込んだコピーを返す。
/// 自動換算はしない(4円用・1円用は独立)。
Machine applyBorder(Machine m, double ballPrice, double value, String stamp) {
  return ballPrice <= 1.5
      ? m.copyWith(border1: value, updatedAt: stamp)
      : m.copyWith(border4: value, updatedAt: stamp);
}

/// 機種登録シートの結果。
/// [startNow] が true なら「登録して計測スタート」、false なら「登録のみ」。
class RegisterMachineResult {
  final String name;
  final double border;
  final bool startNow;
  const RegisterMachineResult({
    required this.name,
    required this.border,
    required this.startNow,
  });
}

/// 新しい機種を登録する(名前 + 現在の貸玉スロットのボーダー1値)。
/// キャンセルは null。
///
/// [initialName] は検索文字列の引き継ぎ(「「◯◯」で登録」の約束を果たす)。
/// [existingNames] は重複登録を防ぐための既存機種名。
/// [allowStart] が false のとき(機種の管理画面)は、そのまま計測に入る導線を
/// 出さず「登録する」だけにする。
Future<RegisterMachineResult?> showRegisterMachine(
  BuildContext context, {
  required double ballPrice,
  String? initialName,
  List<String> existingNames = const [],
  bool allowStart = true,
}) {
  return showModalBottomSheet<RegisterMachineResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xA6000000),
    builder: (_) => _MachineFormSheet(
      ballPrice: ballPrice,
      initialName: initialName,
      existingNames: existingNames,
      allowStart: allowStart,
    ),
  );
}

/// 機種名が既存と重複しているか(前後空白と大小文字を無視して比較)。
bool isDuplicateName(String name, List<String> existingNames) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty) return false;
  return existingNames.any((e) => e.trim().toLowerCase() == n);
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
  List<String> existingNames = const [], // 改名時の重複チェック用(自分は除く)
}) {
  return showModalBottomSheet<MachineEditResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _MachineEditSheet(machine: machine, existingNames: existingNames),
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
      // 有効=暗い塗り+ミント枠、無効=枠も文字も落とす(押せないことを配色で明示)。
      decoration: AppTheme.cta(enabled: enabled, radius: 12),
      child: Text(label,
          style: AppTheme.sans(
              size: 15,
              weight: FontWeight.w700,
              color: AppTheme.ctaInk(enabled))),
    ),
  );
}

/// 新規登録フォーム(名前 + ボーダー1値)。
class _MachineFormSheet extends StatefulWidget {
  final double ballPrice;
  final String? initialName;
  final List<String> existingNames;
  final bool allowStart;
  const _MachineFormSheet({
    required this.ballPrice,
    this.initialName,
    this.existingNames = const [],
    this.allowStart = true,
  });

  @override
  State<_MachineFormSheet> createState() => _MachineFormSheetState();
}

class _MachineFormSheetState extends State<_MachineFormSheet> {
  /// ステッパーの下限・上限・刻み。現実的なボーダーの範囲に収める。
  static const _min = 10.0;
  static const _max = 40.0;
  static const _step = 0.1;
  static const _presets = [17.0, 18.0, 19.0, 20.0, 22.0];

  late final TextEditingController _name = TextEditingController(
    // 検索文字列を引き継ぐ(カーソルは末尾に置く)。
    text: widget.initialName ?? '',
  )..selection = TextSelection.collapsed(
      offset: (widget.initialName ?? '').length);

  double _border = 18.5;
  Timer? _repeat;

  @override
  void dispose() {
    _repeat?.cancel();
    _name.dispose();
    super.dispose();
  }

  bool get _duplicate => isDuplicateName(_name.text, widget.existingNames);
  bool get _canSubmit => _name.text.trim().isNotEmpty && !_duplicate;

  void _nudge(double delta) {
    setState(() {
      // 0.1 刻みの加算で誤差が溜まらないよう、毎回丸め直す。
      final next = (_border + delta).clamp(_min, _max);
      _border = (next * 10).roundToDouble() / 10;
    });
  }

  /// 長押しで連続。押している間だけ繰り返す。
  void _startRepeat(double delta) {
    _nudge(delta);
    _repeat?.cancel();
    _repeat = Timer.periodic(
        const Duration(milliseconds: 90), (_) => _nudge(delta));
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  void _submit({required bool startNow}) {
    if (!_canSubmit) return;
    Navigator.pop(
      context,
      RegisterMachineResult(
        name: _name.text.trim(),
        border: _border,
        startNow: startNow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // キーボードのぶんだけ持ち上げる(シート内の入力欄を覆わせない)。
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('新しい機種を登録',
                  style: AppTheme.sans(size: 16, weight: FontWeight.w700)),
              const SizedBox(height: 20),
              _label('機種名'),
              const SizedBox(height: 8),
              _nameField(),
              if (_duplicate) ...[
                const SizedBox(height: 6),
                Text('同じ名前の機種がすでにあります',
                    style: AppTheme.sans(size: 11, color: AppColors.down)),
              ],
              const SizedBox(height: 20),
              _label('ボーダー（回/k・${ballLabel(widget.ballPrice)}）'),
              const SizedBox(height: 8),
              _stepperRow(),
              const SizedBox(height: 10),
              _presetRow(),
              const SizedBox(height: 20),
              _cta(),
              if (widget.allowStart) ...[
                const SizedBox(height: 12),
                Center(
                  child: GestureDetector(
                    onTap: _canSubmit ? () => _submit(startNow: false) : null,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('登録のみ',
                          style: AppTheme.sans(
                              size: 13, color: AppColors.mutedDark)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: AppTheme.sans(
          size: 11, color: AppColors.mutedDark, letterSpacing: 0.15 * 11));

  Widget _nameField() {
    return SizedBox(
      height: 52,
      child: TextField(
        controller: _name,
        autofocus: true,
        style: AppTheme.sans(size: 16),
        cursorColor: AppColors.accent,
        cursorWidth: 2,
        inputFormatters: machineNameInputFormatters,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          filled: true,
          fillColor: AppColors.surfaceAlt,
          hintText: '機種名',
          hintStyle: AppTheme.sans(size: 16, color: AppColors.faint),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _stepperRow() {
    return Row(
      children: [
        _stepKey('−', -_step),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(_border.toStringAsFixed(1),
                    style: AppTheme.mono(size: 32, weight: FontWeight.w700)),
                const SizedBox(width: 6),
                Text('±0.1',
                    style:
                        AppTheme.mono(size: 12, color: AppColors.mutedDark)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        _stepKey('＋', _step),
      ],
    );
  }

  /// −／＋ キー。押しっぱなしで連続して動く。
  Widget _stepKey(String label, double delta) {
    return GestureDetector(
      onTap: () => _nudge(delta),
      onLongPressStart: (_) => _startRepeat(delta),
      onLongPressEnd: (_) => _stopRepeat(),
      onLongPressCancel: _stopRepeat,
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style: AppTheme.sans(size: 22, color: AppColors.textStrong)),
      ),
    );
  }

  Widget _presetRow() {
    return Row(
      children: [
        for (var i = 0; i < _presets.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _border = _presets[i]),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_presets[i].toStringAsFixed(1),
                      style:
                          AppTheme.mono(size: 12, color: AppColors.muted)),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _cta() {
    final on = _canSubmit;
    return GestureDetector(
      onTap: on ? () => _submit(startNow: widget.allowStart) : null,
      child: Opacity(
        opacity: on ? 1 : 0.4,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: AppTheme.cta(enabled: on),
          child: Text(widget.allowStart ? '登録して計測スタート' : '登録する',
              style: AppTheme.sans(
                  size: 16,
                  weight: FontWeight.w700,
                  letterSpacing: 0.1 * 16,
                  color: AppTheme.ctaInk(on))),
        ),
      ),
    );
  }
}

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

  bool get _valid => parseBorder(_border.text) != null;

  void _submit() {
    final b = parseBorder(_border.text);
    if (b == null) return;
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
        // キーボードが出た状態でも収まらない場合はスクロールで逃がす
        // (小さい画面 / 文字拡大でシートが溢れるのを防ぐ)。
        child: SingleChildScrollView(child: Column(
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
              inputFormatters: borderInputFormatters,
              style: AppTheme.mono(size: 18),
              cursorColor: AppColors.accent,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: _fieldDeco('例: 18.3'),
            ),
            const SizedBox(height: 20),
            _primaryButton('保存', _valid ? _submit : null),
          ],
        )),
      ),
    );
  }
}

/// 機種の編集・削除フォーム(名前 + 4円/1円ボーダーの両スロット)。
class _MachineEditSheet extends StatefulWidget {
  final Machine machine;
  final List<String> existingNames;
  const _MachineEditSheet({required this.machine, this.existingNames = const []});

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
    return parseBorder(t);
  }

  /// 他の機種と同名へ改名しようとしていないか。
  bool get _duplicate => isDuplicateName(_name.text, widget.existingNames);

  bool get _valid {
    final name = _name.text.trim();
    // ボーダー欄が入力されている場合は正の数であること。少なくとも1スロット必須。
    final b4ok = _b4.text.trim().isEmpty || _parse(_b4) != null;
    final b1ok = _b1.text.trim().isEmpty || _parse(_b1) != null;
    final atLeastOne = _parse(_b4) != null || _parse(_b1) != null;
    return name.isNotEmpty && !_duplicate && b4ok && b1ok && atLeastOne;
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
          inputFormatters: borderInputFormatters,
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
        // キーボードが出た状態でも収まらない場合はスクロールで逃がす
        // (小さい画面 / 文字拡大でシートが溢れるのを防ぐ)。
        child: SingleChildScrollView(child: Column(
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
              inputFormatters: machineNameInputFormatters,
              style: AppTheme.sans(size: 14),
              cursorColor: AppColors.accent,
              onChanged: (_) => setState(() {}),
              decoration: _fieldDeco('機種名'),
            ),
            if (_duplicate) ...[
              const SizedBox(height: 6),
              Text('同じ名前の機種が既に登録されています',
                  style: AppTheme.sans(size: 11, color: AppColors.down)),
            ],
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
              child: Text('削除しても履歴は消えません',
                  style: AppTheme.sans(size: 10.5, color: AppColors.mutedDark)),
            ),
          ],
        )),
      ),
    );
  }
}

// ---------------- 打ち始めの数字入力(ボトムシート) ----------------

/// 台のデータ表示機に出ている回転数をそのまま入れて計測を始める。
///
/// 戻り値は打ち始めの回転数。「数字を入れずにスタート」は 0。
/// シート外タップ・下スワイプ・「変更」は null(= 機種選びに戻る)。
Future<int?> showStartCounterSheet(
  BuildContext context, {
  required Machine machine,
  required double ballPrice,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xA6000000),
    builder: (_) =>
        _StartCounterSheet(machine: machine, ballPrice: ballPrice),
  );
}

class _StartCounterSheet extends StatefulWidget {
  final Machine machine;
  final double ballPrice;
  const _StartCounterSheet({required this.machine, required this.ballPrice});

  @override
  State<_StartCounterSheet> createState() => _StartCounterSheetState();
}

class _StartCounterSheetState extends State<_StartCounterSheet> {
  String _typed = '';

  @override
  Widget build(BuildContext context) {
    final border = widget.machine.borderFor(widget.ballPrice);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.machine.name,
                          style: AppTheme.sans(
                              size: 16, weight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                          'B ${border == null ? '--' : border.toStringAsFixed(1)}'
                          ' · ${ballLabel(widget.ballPrice)}',
                          style: AppTheme.mono(
                              size: 12, color: AppColors.mutedDark)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 機種を選び直す = このシートを閉じる。
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  behavior: HitTestBehavior.opaque,
                  child: Text('変更',
                      style:
                          AppTheme.sans(size: 13, color: AppColors.muted)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('台のデータ表示機の回転数をそのまま入力',
                style: AppTheme.sans(size: 12, color: AppColors.mutedDark)),
            const SizedBox(height: 14),
            CounterField(
              typed: _typed,
              prevCounter: null, // 打ち始め=前回「—」
              placeholder: '打ち始めの数字',
              height: 56,
            ),
            const SizedBox(height: 14),
            Numpad(
              keyHeight: 52,
              onKey: (k) => setState(() => _typed = applyKey(_typed, k)),
              commit: NumpadCommit(
                label: '計測\nスタート',
                onTap: () =>
                    Navigator.pop(context, int.tryParse(_typed) ?? 0),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: GestureDetector(
                onTap: () => Navigator.pop(context, 0),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('数字を入れずにスタート（0から）',
                      style: AppTheme.sans(
                          size: 12, color: AppColors.mutedDark)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
