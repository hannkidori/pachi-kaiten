import 'package:flutter/material.dart';

import '../../logic/backup_files.dart';
import '../../models/machine.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../start/machine_sheets.dart';

/// 設定。加算単位 / 貸玉(4円・1円) / スリープ防止 / 機種の編集・削除 /
/// エクスポート。店舗プロファイルと収支インポートは廃止した。
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
  bool _busy = false;

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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _setAddUnit(int unit) async {
    await s.settings.setAddUnitDefault(unit);
    setState(() => _addUnit = unit);
  }

  Future<void> _setBallPrice(double price) async {
    await s.settings.setBallPrice(price);
    setState(() => _ballPrice = price);
  }

  Future<void> _setKeepAwake(bool on) async {
    await s.settings.setKeepAwake(on);
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

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await exportAndShare(s.backup);
    } catch (e) {
      _toast('エクスポートに失敗しました');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _topBar(),
                  _section('計測'),
                  _addUnitRow(),
                  _ballPriceRow(),
                  _keepAwakeRow(),
                  _section('機種マスタ'),
                  if (_machines.isEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Text('登録された機種はありません',
                          style: AppTheme.sans(
                              size: 12, color: AppColors.mutedDark)),
                    ),
                  for (final m in _machines) _machineRow(m),
                  _section('バックアップ'),
                  _actionRow('エクスポート(共有)', Icons.ios_share, _export),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      '登録機種と足跡を JSON で書き出します(機種変更時の持ち出し用)。',
                      style:
                          AppTheme.sans(size: 10.5, color: AppColors.mutedDark),
                    ),
                  ),
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
          Text('設定', style: AppTheme.sans(size: 17, weight: FontWeight.w700)),
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
          color: on ? const Color(0x296BCBDD) : AppColors.surfaceAlt,
          border: Border.all(
              color: on ? const Color(0x666BCBDD) : AppColors.border),
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
    String slot(double? v) => v == null ? '−' : v.toStringAsFixed(1);
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
            Text('4円 ${slot(m.border4)} ・ 1円 ${slot(m.border1)}',
                style: AppTheme.mono(size: 11, color: AppColors.muted)),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.mutedDark),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: _busy ? null : onTap,
      child: Opacity(
        opacity: _busy ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textDim),
              const SizedBox(width: 10),
              Text(label, style: AppTheme.sans(size: 14)),
            ],
          ),
        ),
      ),
    );
  }
}
