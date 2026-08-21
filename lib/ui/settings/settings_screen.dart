import 'package:flutter/material.dart';

import '../../models/machine.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../start/machine_sheets.dart';
import '../widgets/glow_background.dart';

/// 設定。加算単位 / 貸玉(4円・1円) / スリープ防止 / 機種の編集・削除。
/// エクスポート/インポートは次期バージョンで揃えて実装予定(現状は未提供)。
class SettingsScreen extends StatefulWidget {
  final AppServices services;
  const SettingsScreen({super.key, required this.services});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppServices get s => widget.services;

  List<Machine> _machines = [];
  int _addUnit = 1000;
  double _ballPrice = 4.0;
  bool _keepAwake = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final machines = await s.machines.all();
    final addUnit = await s.settings.addUnitDefault();
    final ballPrice = await s.settings.ballPrice();
    final keepAwake = await s.settings.keepAwake();
    if (!mounted) return;
    setState(() {
      _machines = machines;
      _addUnit = addUnit;
      _ballPrice = ballPrice;
      _keepAwake = keepAwake;
      _loading = false;
    });
  }

  Future<void> _setAddUnit(int unit) async {
    await s.settings.setAddUnitDefault(unit);
    if (!mounted) return; // 書き込み中に画面を離れた場合
    setState(() => _addUnit = unit);
  }

  Future<void> _setBallPrice(double price) async {
    await s.settings.setBallPrice(price);
    if (!mounted) return;
    setState(() => _ballPrice = price);
  }

  Future<void> _setKeepAwake(bool on) async {
    await s.settings.setKeepAwake(on);
    if (!mounted) return;
    setState(() => _keepAwake = on);
  }

  Future<void> _editMachine(Machine m) async {
    final res = await showMachineEdit(context, machine: m);
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
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _topBar(),
                  _section('計測'),
                  _addUnitRow(),
                  _ballPriceRow(),
                  _hint('機種のボーダーは貸玉ごとに登録できます'),
                  _keepAwakeRow(),
                  _hint('計測中、画面を消灯しません'),
                  _section('機種'),
                  if (_machines.isEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Text('登録された機種はありません',
                          style: AppTheme.sans(
                              size: 12, color: AppColors.mutedDark)),
                    ),
                  for (final m in _machines) _machineRow(m),
                  _section('このアプリ'),
                  _hint('広告なし・通信なし。計測データはこの端末の中だけにあります'),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text('パチ回転計 v1.0.0',
                        style: AppTheme.mono(
                            size: 11, color: AppColors.mutedDark)),
                  ),
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
          Text('設定', style: AppTheme.sans(size: 16, weight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Text(title,
          style: AppTheme.sans(
              size: 11, color: AppColors.muted, letterSpacing: 0.1 * 11)),
    );
  }

  /// 説明・注記の 1 行(muted)。
  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
      child: Text(text,
          style: AppTheme.sans(size: 10.5, color: AppColors.mutedDark, height: 1.5)),
    );
  }

  Widget _addUnitRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Text('加算単位のデフォルト', style: AppTheme.sans(size: 14)),
          const Spacer(),
          _segment('1000', _addUnit == 1000, () => _setAddUnit(1000)),
          const SizedBox(width: 6),
          _segment('500', _addUnit == 500, () => _setAddUnit(500)),
        ],
      ),
    );
  }

  Widget _ballPriceRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Text('貸玉', style: AppTheme.sans(size: 14)),
          const Spacer(),
          _segment('4円', _ballPrice > 1.5, () => _setBallPrice(4.0)),
          const SizedBox(width: 6),
          _segment('1円', _ballPrice <= 1.5, () => _setBallPrice(1.0)),
        ],
      ),
    );
  }

  Widget _segment(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: on ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: on ? const Color(0x2956D9F0) : AppColors.surfaceAlt,
          border: Border.all(
              color: on ? const Color(0x6656D9F0) : AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: AppTheme.mono(
                size: 12,
                weight: FontWeight.w600,
                color: on ? AppColors.accentSoft : AppColors.textStrong)),
      ),
    );
  }

  Widget _keepAwakeRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          Text('計測中のスリープ防止', style: AppTheme.sans(size: 14)),
          const Spacer(),
          Switch(
            value: _keepAwake,
            onChanged: _setKeepAwake,
            activeTrackColor: AppColors.accentDeep,
            activeThumbColor: AppColors.accentSoft,
          ),
        ],
      ),
    );
  }

  Widget _machineRow(Machine m) {
    String slot(double? v) => v == null ? '--' : v.toStringAsFixed(1);
    return InkWell(
      onTap: () => _editMachine(m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(m.name,
                  style: AppTheme.sans(size: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            // 文字拡大時でも行からはみ出さないようにする。
            Flexible(
              child: Text('4円 ${slot(m.border4)} ・ 1円 ${slot(m.border1)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(size: 11, color: AppColors.muted)),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.mutedDark),
          ],
        ),
      ),
    );
  }

}
