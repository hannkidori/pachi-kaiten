import 'package:flutter/material.dart';

import '../../models/machine.dart';
import '../../models/session.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../widgets/dashed_border.dart';
import 'machine_sheets.dart';

/// 計測開始の結果。呼び出し側(ホーム)がこれを受けて計測画面を開く。
/// [machine] が null ならクイック計測(機種を選ばず計測)。
class StartResult {
  final Session session;
  final Machine? machine;
  const StartResult(this.session, this.machine);
}

/// 機種リストの並び替え。検索クエリがあれば名前部分一致(大文字小文字無視)、
/// 空なら最近使った機種([recentIds] 順)を先頭に、残りは [all] の順
/// (= 登録の新しい順)で返す。名前順は使わない。
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
  // 残りは取得順のまま = 登録の新しい順(名前順にはしない)。
  final rest = byId.values.toList();
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
  int _addUnit = 1000;
  double _ballPrice = 4.0;
  bool _loading = true;
  bool _starting = false;
  bool _picking = false; // 打ち始めシートを開いている最中

  /// 機種名検索の入力欄。テンキーとシステムキーボードは同時に使わないので、
  /// 打ち始めの入力に移るときに閉じる必要がある(閉じないとキーボードが
  /// テンキーを覆ったままになり、打ち始めを入力できない)。
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // カーソルの出し分けのため、フォーカスの変化で描き直す。
    _searchFocus.addListener(_onSearchFocusChanged);
    _load();
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  /// システムキーボードを閉じる(テンキーを覆わせない)。
  void _dismissKeyboard() => FocusScope.of(context).unfocus();


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
        // 対象 → 選択中 → 先頭、の順にフォールバック。全部無い(機種 0 件)なら
        // null のまま(machines.first で StateError を投げないようにする)。
        final found = machines.where((m) => m.id == keepSelectedId);
        _machine = found.isNotEmpty
            ? found.first
            : (_machine ?? (machines.isEmpty ? null : machines.first));
      }
      _loading = false;
    });
  }

  /// 検索/最近順に並べた機種リスト。
  List<Machine> get _visibleMachines =>
      orderMachines(all: _machines, recentIds: _recentIds, query: _query);

  String _stamp() => DateTime.now().toIso8601String();

  /// 新しい機種を登録し、そのまま打ち始め入力へ進む。
  /// 検索文字列は名前欄に引き継ぐ(「「◯◯」で登録」の表示どおりに動かす)。
  Future<void> _register() async {
    final res = await showRegisterMachine(
      context,
      ballPrice: _ballPrice,
      initialName: _query.trim().isEmpty ? null : _query.trim(),
      existingNames: _machines.map((m) => m.name).toList(),
    );
    if (res == null || !mounted) return;
    final base = Machine(name: res.name, updatedAt: _stamp());
    final saved = await s.machines
        .insert(applyBorder(base, _ballPrice, res.border, _stamp()));
    if (!mounted) return;
    await _load();
    if (!mounted || !res.startNow) return; // 「登録のみ」はリストに戻るだけ
    await _pickAndStart(saved);
  }

  /// 貸玉を切り替える。設定と同じグローバル値を書き換えるので、
  /// 設定画面から変えたときと結果は同じになる。
  Future<void> _setBallPrice(double price) async {
    if (price == _ballPrice) return;
    await s.settings.setBallPrice(price);
    if (!mounted) return;
    setState(() => _ballPrice = price);
  }

  /// 機種を選ぶ → (ボーダー未登録ならその場で入力) → 打ち始めシート → 計測開始。
  Future<void> _pickAndStart(Machine m) async {
    if (_starting || _picking) return; // 行の連打でシートを重ねない
    _picking = true;
    try {
      await _pickAndStartInner(m);
    } finally {
      if (mounted) _picking = false;
    }
  }

  Future<void> _pickAndStartInner(Machine m) async {
    _dismissKeyboard();
    var machine = m;
    // 現在の貸玉スロットが未入力なら、その場で入力を求めて保存(育つマスタ)。
    if (machine.borderFor(_ballPrice) == null) {
      final entered = await showBorderPrompt(
        context,
        machineName: machine.name,
        ballPrice: _ballPrice,
        current: null,
      );
      if (entered == null || !mounted) return;
      machine = applyBorder(machine, _ballPrice, entered, _stamp());
      await s.machines.update(machine);
      if (!mounted) return;
    }
    final counter = await showStartCounterSheet(
      context,
      machine: machine,
      ballPrice: _ballPrice,
    );
    if (counter == null || !mounted) return;
    setState(() => _starting = true);
    try {
      final session = await s.sessionService.start(
        machine: machine,
        ballPrice: _ballPrice,
        startCounter: counter,
        addUnit: _addUnit,
      );
      if (!mounted) return;
      Navigator.of(context).pop(StartResult(session, machine));
    } catch (_) {
      // 失敗しても押せないままにしない(成功時は画面ごと閉じるので触らない)。
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topBar(),
                    _searchField(),
                    Expanded(child: _machineList()),
                    _registerRow(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 20),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              behavior: HitTestBehavior.opaque,
              child: Text('‹',
                  style: AppTheme.sans(size: 20, color: AppColors.muted)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('機種を選んで計測',
                  style:
                      AppTheme.sans(size: 16, weight: FontWeight.w700)),
            ),
            _ballSegment(),
          ],
        ),
      ),
    );
  }

  /// 貸玉の切替。設定と同じ値を書き換える(表示だけの飾りにはしない)。
  Widget _ballSegment() {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ballOption('4円', 4.0, _ballPrice > 1.5),
          _ballOption('1円', 1.0, _ballPrice <= 1.5),
        ],
      ),
    );
  }

  Widget _ballOption(String label, double price, bool on) {
    return GestureDetector(
      onTap: on ? null : () => _setBallPrice(price),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.keyActive : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style: AppTheme.mono(
                size: 12,
                color: on ? AppColors.text : AppColors.mutedDark)),
      ),
    );
  }

  // ---------- 機種検索 ----------
  Widget _searchField() {
    return SizedBox(
      height: 48,
      child: TextField(
        focusNode: _searchFocus,
        style: AppTheme.sans(size: 14),
        cursorColor: AppColors.accent,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          prefixIcon:
              const Icon(Icons.search, size: 18, color: AppColors.mutedDark),
          hintText: '機種名で検索',
          hintStyle: AppTheme.sans(size: 14, color: AppColors.mutedDark),
          filled: true,
          fillColor: AppColors.surfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.accentBorderSoft),
          ),
        ),
      ),
    );
  }

  /// 「＋ 新しい機種を登録」。リストの下に固定で置く。
  Widget _registerRow() {
    final q = _query.trim();
    final noHit = q.isNotEmpty && _visibleMachines.isEmpty;
    return GestureDetector(
      onTap: _register,
      behavior: HitTestBehavior.opaque,
      child: DashedBorderBox(
        color: AppColors.accentBorderSoft,
        radius: 16,
        strokeWidth: 1.5,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('＋',
                  style: AppTheme.sans(size: 18, color: AppColors.accent)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(noHit ? '「$q」で登録' : '新しい機種を登録',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppTheme.sans(size: 15, color: AppColors.accent)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _machineList() {
    final list = _visibleMachines;
    if (list.isEmpty) {
      return Center(
        child: Text(
          _machines.isEmpty
              ? 'まだ機種がありません'
              : (_query.trim().isEmpty ? '機種がありません' : '該当する機種がありません'),
          style: AppTheme.sans(size: 12, color: AppColors.mutedDark),
        ),
      );
    }
    final showRecentLabel = _query.trim().isEmpty && _recentIds.isNotEmpty;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (showRecentLabel)
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Text('最近使った機種',
                style: AppTheme.sans(
                    size: 11,
                    color: AppColors.mutedDark,
                    letterSpacing: 0.15 * 11)),
          )
        else
          const SizedBox(height: 12),
        for (final m in list) _machineRow(m),
        const SizedBox(height: 12),
      ],
    );
  }

  /// 1 行 = 機種名 + ボーダー + ▶。タップで打ち始めシートへ。
  Widget _machineRow(Machine m) {
    final border = m.borderFor(_ballPrice);
    return GestureDetector(
      onTap: () => _pickAndStart(m),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 60,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.hairFaint)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(m.name,
                  style: AppTheme.sans(size: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 12),
            Text('B ${border == null ? '--' : border.toStringAsFixed(1)}',
                style: AppTheme.mono(size: 13, color: AppColors.muted)),
            const SizedBox(width: 12),
            Text('▶', style: AppTheme.sans(size: 12, color: AppColors.accent)),
          ],
        ),
      ),
    );
  }
}
