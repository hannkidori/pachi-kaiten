import 'package:flutter/material.dart';

import '../../logic/rotation_calc.dart';
import '../../models/machine.dart';
import '../../models/session.dart';
import '../../services/app_services.dart';
import '../../state/measurement_controller.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../history/history_screen.dart';
import '../measurement/measurement_screen.dart';
import '../settings/settings_screen.dart';
import '../start/start_screen.dart';

/// ホーム。計測中セッションがあれば復帰カードを最優先表示し、
/// なければ計測開始(スタート画面)へ導く。
class HomeScreen extends StatefulWidget {
  final AppServices services;
  const HomeScreen({super.key, required this.services});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _ActiveSummary {
  final Session session;
  final Machine machine;
  final String investK;
  final int totalSpins;
  final String lastTime;
  const _ActiveSummary(this.session, this.machine, this.investK,
      this.totalSpins, this.lastTime);
}

class _HomeScreenState extends State<HomeScreen> {
  AppServices get s => widget.services;
  _ActiveSummary? _active;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final session = await s.sessions.active();
    _ActiveSummary? summary;
    if (session != null) {
      final machine = await s.machines.byId(session.machineId);
      final entries = await s.sessionService.entriesOf(session.id!);
      if (machine != null) {
        final stats = computeStats(
          entries: entries,
          border: machine.borderFor(session.ballPrice) ?? 0,
          ballPrice: session.ballPrice,
        );
        final last = entries.isNotEmpty
            ? DateTime.tryParse(entries.last.createdAt)
            : null;
        final hhmm = last == null
            ? '--:--'
            : '${last.hour.toString().padLeft(2, '0')}:'
                '${last.minute.toString().padLeft(2, '0')}';
        summary = _ActiveSummary(session, machine, fmtK(stats.cashInvest),
            stats.totalRotations, hhmm);
      }
    }
    if (!mounted) return;
    setState(() {
      _active = summary;
      _loading = false;
    });
  }

  Future<void> _openMeasurement(Session session, Machine machine,
      {MeasureIntent intent = MeasureIntent.normal}) async {
    final controller = MeasurementController(
      service: s.sessionService,
      session: session,
      machine: machine,
    );
    await controller.load();
    final keepAwake = await s.settings.keepAwake();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MeasurementScreen(
        controller: controller,
        services: s,
        keepAwake: keepAwake,
        initialIntent: intent,
      ),
    ));
    _refresh();
  }

  Future<void> _startNew() async {
    final result = await Navigator.of(context).push<StartResult>(
      MaterialPageRoute(builder: (_) => StartScreen(services: s)),
    );
    if (result != null) {
      await _openMeasurement(result.session, result.machine);
    }
  }

  Future<void> _discard(Session session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('このセッションを破棄しますか?',
            style: AppTheme.sans(size: 15, weight: FontWeight.w700)),
        content: Text('計測中のデータは削除され、足跡には残りません。',
            style: AppTheme.sans(size: 13, color: AppColors.textStrong)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('やめる',
                style: AppTheme.sans(size: 13, color: AppColors.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('破棄する',
                style: AppTheme.sans(size: 13, color: AppColors.down)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await s.sessionService.discard(session.id!);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Text('パチ回転計',
                        style:
                            AppTheme.sans(size: 22, weight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('回転率を計って足跡を残す',
                        style:
                            AppTheme.sans(size: 12, color: AppColors.muted)),
                    const SizedBox(height: 24),
                    if (_active != null) _restoreCard(_active!),
                    const Spacer(),
                    _primaryButton('計測開始', _startNew),
                    const SizedBox(height: 12),
                    // 足跡・設定は控えめに(計器が主役)。テキストリンク相当の細い導線。
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _subtleLink('足跡', _openHistory),
                        _dotSeparator(),
                        _subtleLink('設定', _openSettings),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
        ),
      ),
    );
  }

  void _openHistory() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HistoryScreen(services: s),
    ));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(services: s),
    ));
    _refresh();
  }

  Widget _restoreCard(_ActiveSummary a) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: const Color(0x336BCBDD)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: AppColors.accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text('計測中のセッションがあります',
                  style: AppTheme.sans(size: 13.5, weight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          Text(a.machine.name,
              style: AppTheme.sans(size: 14, weight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
            '投資 ${a.investK} ・ ${a.totalSpins}回転 ・ 最終入力 ${a.lastTime}',
            style: AppTheme.mono(size: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          _primaryButton(
            '計測を再開',
            () => _openMeasurement(a.session, a.machine),
            height: 48,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                // 終了 = 足跡保存 + 任意回収額シートへ直行する。
                child: _navButton(
                  '終了',
                  () => _openMeasurement(a.session, a.machine,
                      intent: MeasureIntent.end),
                  height: 44,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _navButton('破棄', () => _discard(a.session),
                    height: 44, danger: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback onTap, {double height = 56}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accentDeep,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: AppTheme.sans(
                size: 16,
                weight: FontWeight.w700,
                color: AppColors.accentInk)),
      ),
    );
  }

  /// 控えめなテキストリンク(足跡・設定)。計器を主役にするため目立たせない。
  Widget _subtleLink(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(label,
            style: AppTheme.sans(size: 13, color: AppColors.muted)),
      ),
    );
  }

  Widget _dotSeparator() => Text('・',
      style: AppTheme.sans(size: 13, color: AppColors.mutedDark));

  Widget _navButton(String label, VoidCallback onTap,
      {double height = 52, bool danger = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(
              color: danger ? const Color(0x40F06A5D) : AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: AppTheme.sans(
                size: 13.5,
                color: danger ? AppColors.down : AppColors.textStrong)),
      ),
    );
  }
}
