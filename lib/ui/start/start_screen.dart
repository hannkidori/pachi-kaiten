import 'package:flutter/material.dart';

import '../../models/machine.dart';
import '../../models/session.dart';
import '../../models/store.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../widgets/numpad.dart';
import 'store_edit_sheet.dart';

/// 計測開始の結果。呼び出し側(ホーム)がこれを受けて計測画面を開く。
class StartResult {
  final Session session;
  final Machine machine;
  const StartResult(this.session, this.machine);
}

/// 機種リストの並び替え。検索クエリがあれば名前部分一致(大文字小文字無視)、
/// 空なら最近使った機種([recentIds] 順)を先頭に、残りを名前順で返す。
List<Machine> orderMachines({
  required List<Machine> all,
  required List<String> recentIds,
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

/// スタート画面: 店舗(前回値デフォルト・その場編集)→ 機種インクリメンタル検索
/// (最近使った機種が先頭)→ 打ち始めカウンタ → 計測開始。
class StartScreen extends StatefulWidget {
  final AppServices services;
  const StartScreen({super.key, required this.services});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  AppServices get s => widget.services;

  List<Store> _stores = [];
  Store? _store;
  List<Machine> _machines = [];
  List<String> _recentIds = [];
  Machine? _machine;
  String _query = '';
  String _counter = '';
  int _addUnit = 1000;
  bool _loading = true;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stores = await s.stores.all();
    final recentStoreId = await s.sessions.recentStoreId();
    final machines = await s.machines.all();
    final recentIds = await s.sessions.recentMachineIds();
    final addUnit = await s.settings.addUnitDefault();
    setState(() {
      _addUnit = addUnit;
      _stores = stores;
      _store = stores.firstWhere(
        (st) => st.id == recentStoreId,
        orElse: () => stores.isNotEmpty ? stores.first : _placeholderStore(),
      );
      if (stores.isEmpty) _store = null;
      _machines = machines;
      _recentIds = recentIds;
      _loading = false;
    });
  }

  Store _placeholderStore() =>
      const Store(name: '', exchangeRate: 3.57, ballPrice: 4.0);

  /// 検索/最近順に並べた機種リスト。
  List<Machine> get _visibleMachines =>
      orderMachines(all: _machines, recentIds: _recentIds, query: _query);

  bool get _canStart => _store?.id != null && _machine != null && !_starting;

  Future<void> _addStore() async {
    final res = await showStoreEditSheet(context, repo: s.stores);
    if (res?.store != null) {
      await _load();
      setState(() => _store = res!.store);
    }
  }

  Future<void> _editStore(Store store) async {
    final res =
        await showStoreEditSheet(context, repo: s.stores, initial: store);
    if (res == null) return;
    await _load();
    if (res.deleted) return;
    setState(() => _store = res.store);
  }

  Future<void> _start() async {
    if (!_canStart) return;
    setState(() => _starting = true);
    final counter = int.tryParse(_counter) ?? 0;
    final session = await s.sessionService.start(
      store: _store!,
      machine: _machine!,
      startCounter: counter,
      addUnit: _addUnit,
    );
    if (!mounted) return;
    Navigator.of(context).pop(StartResult(session, _machine!));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _topBar(),
                  _storeSection(),
                  const SizedBox(height: 8),
                  _searchField(),
                  Expanded(child: _machineList()),
                  _counterSection(),
                  _startButton(),
                ],
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
          Text('計測を開始',
              style: AppTheme.sans(size: 17, weight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ---------- 店舗 ----------
  Widget _storeSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('店舗',
              style: AppTheme.sans(size: 11, color: AppColors.muted)),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final st in _stores) _storeChip(st),
                _addChip(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _storeChip(Store st) {
    final selected = st.id == _store?.id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _store = st),
        onLongPress: () => _editStore(st),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0x296BCBDD) : AppColors.surfaceAlt,
            border: Border.all(
                color:
                    selected ? const Color(0x666BCBDD) : AppColors.border),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(st.name,
                  style: AppTheme.sans(
                      size: 13,
                      weight: FontWeight.w600,
                      color: selected
                          ? AppColors.accentSoft
                          : AppColors.textStrong)),
              Text('  ${_rateLabel(st.exchangeRate)}',
                  style: AppTheme.mono(size: 10, color: AppColors.muted)),
              if (selected) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _editStore(st),
                  child: const Icon(Icons.edit,
                      size: 13, color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _addChip() {
    return GestureDetector(
      onTap: _addStore,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 15, color: AppColors.muted),
            const SizedBox(width: 4),
            Text('店舗',
                style: AppTheme.sans(size: 12, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  String _rateLabel(double rate) => rate >= 3.99 ? '等価' : rate.toString();

  // ---------- 機種検索 ----------
  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: TextField(
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
    );
  }

  Widget _machineList() {
    final list = _visibleMachines;
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
    final rate = _store?.exchangeRate ?? 4.0;
    final border = m.borderForRate(rate);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => _machine = m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? const Color(0x146BCBDD) : Colors.transparent,
            border: Border.all(
                color:
                    selected ? const Color(0x736BCBDD) : AppColors.border),
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
          Container(
            height: 50,
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
                Text(_counter.isEmpty ? '0' : _counter,
                    style: AppTheme.mono(size: 22, weight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Numpad(
            keyHeight: 44,
            onKey: (k) => setState(() => _counter = applyKey(_counter, k)),
          ),
        ],
      ),
    );
  }

  Widget _startButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Opacity(
        opacity: _canStart ? 1 : 0.35,
        child: GestureDetector(
          onTap: _canStart ? _start : null,
          child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentDeep,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _machine == null ? '機種を選択してください' : '計測開始',
              style: AppTheme.sans(
                  size: 16,
                  weight: FontWeight.w700,
                  color: AppColors.accentInk),
            ),
          ),
        ),
      ),
    );
  }
}
