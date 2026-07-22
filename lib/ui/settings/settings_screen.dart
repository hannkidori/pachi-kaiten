import 'package:flutter/material.dart';

import '../../logic/backup_files.dart';
import '../../models/store.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../start/store_edit_sheet.dart';

/// 設定。店舗マスタ CRUD / 加算単位デフォルト / スリープ防止 /
/// バックアップ(エクスポート・インポート)。
class SettingsScreen extends StatefulWidget {
  final AppServices services;
  const SettingsScreen({super.key, required this.services});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppServices get s => widget.services;

  List<Store> _stores = [];
  int _addUnit = 1000;
  bool _keepAwake = true;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stores = await s.stores.all();
    final addUnit = await s.settings.addUnitDefault();
    final keepAwake = await s.settings.keepAwake();
    if (!mounted) return;
    setState(() {
      _stores = stores;
      _addUnit = addUnit;
      _keepAwake = keepAwake;
      _loading = false;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addStore() async {
    final res = await showStoreEditSheet(context, repo: s.stores);
    if (res != null) _load();
  }

  Future<void> _editStore(Store store) async {
    final res = await showStoreEditSheet(context, repo: s.stores, initial: store);
    if (res != null) _load();
  }

  Future<void> _setAddUnit(int unit) async {
    await s.settings.setAddUnitDefault(unit);
    setState(() => _addUnit = unit);
  }

  Future<void> _setKeepAwake(bool on) async {
    await s.settings.setKeepAwake(on);
    setState(() => _keepAwake = on);
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

  Future<void> _import() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('データをインポートしますか?',
            style: AppTheme.sans(size: 15, weight: FontWeight.w700)),
        content: Text(
            '現在のデータは上書きされます。上書き前に自動でバックアップを取ってから取り込みます。',
            style: AppTheme.sans(size: 13, color: AppColors.textStrong)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('やめる',
                style: AppTheme.sans(size: 13, color: AppColors.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('ファイルを選ぶ',
                style: AppTheme.sans(size: 13, color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (ok != true || _busy) return;
    setState(() => _busy = true);
    try {
      final res = await pickAndImport(s.backup);
      if (res == ImportResult.success) {
        _toast('インポートが完了しました');
        await _load();
      }
    } catch (e) {
      _toast('インポートに失敗しました(データは変更されていません)');
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
                  _section('店舗マスタ'),
                  for (final st in _stores) _storeRow(st),
                  _addStoreRow(),
                  _section('計測'),
                  _addUnitRow(),
                  _keepAwakeRow(),
                  _section('バックアップ'),
                  _actionRow('エクスポート(共有)', Icons.ios_share, _export),
                  _actionRow('インポート(復元)', Icons.download, _import),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'インポートは上書き前に自動でバックアップを取ります。',
                      style: AppTheme.sans(size: 10.5, color: AppColors.mutedDark),
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

  Widget _storeRow(Store st) {
    return InkWell(
      onTap: () => _editStore(st),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(st.name,
                  style: AppTheme.sans(size: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            Text(
              '${st.exchangeRate >= 3.99 ? '等価' : st.exchangeRate} ・ '
              '${st.ballPrice.toInt()}円',
              style: AppTheme.mono(size: 11, color: AppColors.muted),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.mutedDark),
          ],
        ),
      ),
    );
  }

  Widget _addStoreRow() {
    return InkWell(
      onTap: _addStore,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.add, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Text('店舗を追加',
                style: AppTheme.sans(size: 14, color: AppColors.accent)),
          ],
        ),
      ),
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
