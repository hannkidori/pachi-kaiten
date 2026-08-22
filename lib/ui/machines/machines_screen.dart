import 'package:flutter/material.dart';

import '../../models/machine.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../start/machine_sheets.dart';
import '../widgets/dashed_border.dart';
import '../widgets/glow_background.dart';

/// 機種マスタの管理画面。登録・編集・削除をここに集約する。
///
/// スタート画面は「今から打つ台を選ぶ」ことに専念させ、マスタの世話(改名・
/// 両スロットの編集・削除)はこの画面に置く。設定からは機種一覧を外した。
class MachinesScreen extends StatefulWidget {
  final AppServices services;
  const MachinesScreen({super.key, required this.services});

  @override
  State<MachinesScreen> createState() => _MachinesScreenState();
}

class _MachinesScreenState extends State<MachinesScreen> {
  AppServices get s => widget.services;

  List<Machine> _machines = [];
  String _query = '';
  double _ballPrice = 4.0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final machines = await s.machines.all();
    final ballPrice = await s.settings.ballPrice();
    if (!mounted) return;
    setState(() {
      _machines = machines;
      _ballPrice = ballPrice;
      _loading = false;
    });
  }

  /// 検索(名前の部分一致)。並びは取得順のまま = 登録の新しい順。
  /// マスタ管理画面なので「最近使った順」は使わず、登録順で安定させる。
  List<Machine> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _machines;
    return _machines.where((m) => m.name.toLowerCase().contains(q)).toList();
  }

  String _stamp() => DateTime.now().toIso8601String();

  Future<void> _register() async {
    final res = await showRegisterMachine(
      context,
      ballPrice: _ballPrice,
      initialName: _query.trim().isEmpty ? null : _query.trim(),
      existingNames: _machines.map((m) => m.name).toList(),
    );
    if (res == null) return;
    final base = Machine(name: res.name, updatedAt: _stamp());
    await s.machines.insert(applyBorder(base, _ballPrice, res.border, _stamp()));
    await _load();
  }

  Future<void> _edit(Machine m) async {
    final res = await showMachineEdit(
      context,
      machine: m,
      existingNames:
          _machines.where((x) => x.id != m.id).map((x) => x.name).toList(),
    );
    if (res == null) return;
    if (res.deleted) {
      if (m.id != null) await s.machines.delete(m.id!);
    } else if (res.saved != null) {
      await s.machines.update(res.saved!);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: GlowBackground.list(
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
                    Expanded(child: _list()),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: AppColors.textDim),
          ),
          Text('機種', style: AppTheme.sans(size: 16, weight: FontWeight.w700)),
          const Spacer(),
          if (_machines.isNotEmpty)
            Text('${_machines.length}件',
                style: AppTheme.mono(size: 11, color: AppColors.faint)),
        ],
      ),
    );
  }

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
    // 検索ヒット0件のときは検索文字列を登録名に引き継ぐ(スタート画面と同じ挙動)。
    final q = _query.trim();
    final noHit = q.isNotEmpty && _visible.isEmpty;
    final label = noHit ? '「$q」で登録' : '新しい機種を登録';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
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

  Widget _list() {
    final list = _visible;
    if (list.isEmpty) {
      return Center(
        child: Text(
          _machines.isEmpty ? '打つ台を登録しておきましょう' : '該当する機種がありません',
          style: AppTheme.sans(size: 12, color: AppColors.mutedDark),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _row(list[i]),
    );
  }

  Widget _row(Machine m) {
    String slot(double? v) => v == null ? '--' : v.toStringAsFixed(1);
    return GestureDetector(
      onTap: () => _edit(m),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        // 2 段組み(履歴と同じ形)。マスタ管理は名前の見分けが最優先なので、
        // 機種名に横幅を全部使わせ、ボーダーは 2 段目に小さく置く。
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(m.name,
                      style: AppTheme.sans(size: 13.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.mutedDark),
              ],
            ),
            const SizedBox(height: 5),
            Text('4円 ${slot(m.border4)} ・ 1円 ${slot(m.border1)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.mono(size: 11, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}
