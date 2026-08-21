import 'package:flutter/material.dart';

import '../../models/machine.dart';
import '../../models/session.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../widgets/counter_field.dart';
import '../widgets/dashed_border.dart';
import '../widgets/glow_background.dart';
import '../widgets/numpad.dart';
import 'machine_sheets.dart';

/// 計測開始の結果。呼び出し側(ホーム)がこれを受けて計測画面を開く。
/// [machine] が null ならクイック計測(機種を選ばず計測)。
class StartResult {
  final Session session;
  final Machine? machine;
  const StartResult(this.session, this.machine);
}

/// 機種リストの並び替え。検索クエリがあれば名前部分一致(大文字小文字無視)、
/// 空なら最近使った機種([recentIds] 順)を先頭に、残りを名前順で返す。
List<Machine> orderMachines({
  required List<Machine> all,
  required List<int> recentIds,
  required String query,
}) {
  final q = query.trim();
  if (q.isNotEmpty) {
    final lower = q.toLowerCase();
    return all.where((m) => m.name.toLowerCase().contains(lower)).toList();
  }
  final byId = {for (final m in all) m.id: m};
  final recent = <Machine>[];
  for (final id in recentIds) {
    final m = byId.remove(id);
    if (m != null) recent.add(m);
  }
  final rest = byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  return [...recent, ...rest];
}

/// スタート画面: 機種インクリメンタル検索(最近使った機種が先頭)/新規登録
/// → 打ち始めカウンタ → 計測開始。貸玉はグローバル設定を使う。
class StartScreen extends StatefulWidget {
  final AppServices services;
  const StartScreen({super.key, required this.services});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  AppServices get s => widget.services;

  List<Machine> _machines = [];
  List<int> _recentIds = [];
  Machine? _machine;
  String _query = '';
  String _counter = '';
  int _addUnit = 1000;
  double _ballPrice = 4.0;
  bool _loading = true;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 短い画面(iPhone SE 第1世代 / iPhone 8 相当)ではテンキー等を詰める。
  bool get _compact => MediaQuery.sizeOf(context).height < 620;

  Future<void> _load({int? keepSelectedId}) async {
    final machines = await s.machines.all();
    final recentIds = await s.sessions.recentMachineIds();
    final addUnit = await s.settings.addUnitDefault();
    final ballPrice = await s.settings.ballPrice();
    if (!mounted) return; // 読み込み中に「←」で離脱した場合
    setState(() {
      _addUnit = addUnit;
      _ballPrice = ballPrice;
      _machines = machines;
      _recentIds = recentIds;
      if (keepSelectedId != null) {
        _machine = machines.firstWhere((m) => m.id == keepSelectedId,
            orElse: () => _machine ?? machines.first);
      }
      _loading = false;
    });
  }

  /// 検索/最近順に並べた機種リスト。
  List<Machine> get _visibleMachines =>
      orderMachines(all: _machines, recentIds: _recentIds, query: _query);

  bool get _canStart => _machine != null && !_starting;

  String _stamp() => DateTime.now().toIso8601String();

  /// 新しい機種を登録(名前 + 現在の貸玉スロットのボーダー)→ 選択状態にする。
  /// 検索文字列は名前欄に引き継ぐ(「「◯◯」で登録」の表示どおりに動かす)。
  Future<void> _register() async {
    final res = await showRegisterMachine(
      context,
      ballPrice: _ballPrice,
      initialName: _query.trim().isEmpty ? null : _query.trim(),
      existingNames: _machines.map((m) => m.name).toList(),
    );
    if (res == null) return;
    final base = Machine(name: res.name, updatedAt: _stamp());
    final saved =
        await s.machines.insert(applyBorder(base, _ballPrice, res.border, _stamp()));
    await _load(keepSelectedId: saved.id);
  }

  /// 選択中機種の現在スロットのボーダーを上書き編集。
  Future<void> _editBorder(Machine m) async {
    final entered = await showBorderPrompt(
      context,
      machineName: m.name,
      ballPrice: _ballPrice,
      current: m.borderFor(_ballPrice),
    );
    if (entered == null) return;
    await s.machines.update(applyBorder(m, _ballPrice, entered, _stamp()));
    await _load(keepSelectedId: m.id);
  }

  Future<void> _start() async {
    if (!_canStart) return;
    var machine = _machine!;
    // 現在の貸玉スロットが未入力なら、その場で入力を求めて保存(育つマスタ)。
    if (machine.borderFor(_ballPrice) == null) {
      final entered = await showBorderPrompt(
        context,
        machineName: machine.name,
        ballPrice: _ballPrice,
        current: null,
      );
      if (entered == null) return;
      machine = applyBorder(machine, _ballPrice, entered, _stamp());
      await s.machines.update(machine);
    }
    setState(() => _starting = true);
    final counter = int.tryParse(_counter) ?? 0;
    final session = await s.sessionService.start(
      machine: machine,
      ballPrice: _ballPrice,
      startCounter: counter,
      addUnit: _addUnit,
    );
    if (!mounted) return;
    Navigator.of(context).pop(StartResult(session, machine));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      // テンキーはアプリ独自入力でシステムキーボードと同時使用しない。キーボード
      // 降下の過渡で本文が縮み、出現直後のカウンタ欄+テンキーが一瞬溢れるのを防ぐ。
      resizeToAvoidBottomInset: false,
      body: GlowBackground.start(
        child: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _topBar(),
                  _searchField(),
                  _registerRow(),
                  const SizedBox(height: 8),
                  Expanded(child: _machineList()),
                  // 機種を選ぶまで打ち始め入力欄・テンキーは出さない
                  // (機種を選ぶ → 打ち始め → 開始 の順序を視覚的に強制)。
                  if (_machine != null) _counterSection(),
                  _startButton(),
                ],
              ),
      ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: AppColors.textDim),
          ),
          Text('計測開始',
              style: AppTheme.sans(size: 16, weight: FontWeight.w700)),
          const Spacer(),
          // 貸玉はグローバル設定。ここでは適用スロットの目安として読み取り専用表示。
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(ballLabel(_ballPrice),
                style: AppTheme.mono(size: 11, color: AppColors.textDim)),
          ),
        ],
      ),
    );
  }

  // ---------- 機種検索 ----------
  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
      child: TextField(
        style: AppTheme.sans(size: 14),
        cursorColor: AppColors.accent,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon:
              const Icon(Icons.search, size: 18, color: AppColors.muted),
          hintText: '機種名で検索',
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
    );
  }

  Widget _registerRow() {
    // 検索ヒット0件のときは検索文字列を登録名に引き継ぐ。
    final q = _query.trim();
    final noHit = q.isNotEmpty && _visibleMachines.isEmpty;
    final label = noHit ? '「$q」で登録' : '新しい機種を登録';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: GestureDetector(
        onTap: _register,
        behavior: HitTestBehavior.opaque,
        child: DashedBorderBox(
          color: const Color(0x8C56D9F0),
          radius: 10,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                const Icon(Icons.add, size: 17, color: AppColors.accent),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.sans(
                          size: 13,
                          weight: FontWeight.w600,
                          color: AppColors.accentSoft)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _machineList() {
    final list = _visibleMachines;
    if (list.isEmpty) {
      final zeroMachines = _machines.isEmpty;
      return Center(
        child: Text(
          zeroMachines
              ? '打つ台を登録して始めましょう'
              : (_query.trim().isEmpty ? '機種がありません' : '該当する機種がありません'),
          style: AppTheme.sans(size: 12, color: AppColors.mutedDark),
        ),
      );
    }
    final showRecentLabel = _query.trim().isEmpty && _recentIds.isNotEmpty;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final m = list[i];
        final isRecentHead =
            showRecentLabel && i == 0 && _recentIds.contains(m.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isRecentHead)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Text('最近使った機種',
                    style:
                        AppTheme.sans(size: 10, color: AppColors.mutedDark)),
              ),
            _machineRow(m),
          ],
        );
      },
    );
  }

  Widget _machineRow(Machine m) {
    final selected = m.id == _machine?.id;
    final border = m.borderFor(_ballPrice);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => setState(() => _machine = m),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: selected ? const Color(0x1456D9F0) : Colors.transparent,
                border: Border.all(
                    color:
                        selected ? const Color(0x7356D9F0) : AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
            children: [
              if (selected) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: AppColors.accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(m.name,
                    style: AppTheme.sans(size: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              if (selected)
                // 選択中はボーダーの現在値を表示し、その場で上書き編集可能。
                GestureDetector(
                  onTap: () => _editBorder(m),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        border == null
                            ? 'B --'
                            : 'B ${border.toStringAsFixed(1)}',
                        style: AppTheme.mono(
                            size: 11,
                            color: border == null
                                ? AppColors.down
                                : AppColors.textDim),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit, size: 13, color: AppColors.muted),
                    ],
                  ),
                )
              else
                Text(border == null ? 'B --' : 'B ${border.toStringAsFixed(1)}',
                    style: AppTheme.mono(
                        size: 11,
                        color: border == null
                            ? AppColors.faint
                            : AppColors.muted)),
                ],
              ),
            ),
          ),
          // 選択したが現在の貸玉スロットが未登録: その場入力を促すアンバー注記。
          if (selected && border == null)
            GestureDetector(
              onTap: () => _editBorder(m),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
                child: Text(
                  '${ballLabel(_ballPrice)}のボーダー未登録 — タップして入力',
                  style: AppTheme.sans(size: 10.5, color: AppColors.hit),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- 打ち始めカウンタ ----------
  Widget _counterSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('台のデータ表示機の回転数をそのまま入力',
              style: AppTheme.sans(size: 9.5, color: AppColors.muted)),
          const SizedBox(height: 6),
          CounterField(
            typed: _counter,
            prevCounter: null, // 打ち始め=前回「—」
            placeholder: '打ち始めの数字',
            height: _compact ? 52 : 58,
          ),
          const SizedBox(height: 8),
          Numpad(
            keyHeight: _compact ? 40 : 44,
            spacing: _compact ? 6 : 8,
            onKey: (k) => setState(() => _counter = applyKey(_counter, k)),
          ),
        ],
      ),
    );
  }

  Widget _startButton() {
    final enabled = _canStart;
    final label = enabled ? '計測スタート' : '機種を選択してください';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: GestureDetector(
        onTap: enabled ? _start : null,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // 有効=シアングラデ、無効=暗いグレー(押せないことを配色で明示)。
            gradient: enabled ? AppColors.accentGradient : null,
            color: enabled ? null : AppColors.surface,
            border:
                enabled ? null : Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: AppTheme.sans(
                size: 16,
                weight: FontWeight.w700,
                color: enabled ? AppColors.accentInk : AppColors.mutedDark),
          ),
        ),
      ),
    );
  }
}
