import 'dart:async';

import 'package:flutter/material.dart';

import '../../logic/rotation_calc.dart';
import '../../models/machine.dart';
import '../../models/session.dart';
import '../../models/trace.dart';
import '../../services/app_services.dart';
import '../../state/measurement_controller.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../history/history_screen.dart';
import '../measurement/measurement_screen.dart';
import '../settings/settings_screen.dart';
import '../start/quick_start_screen.dart';
import '../start/start_screen.dart';
import '../widgets/glow_background.dart';

/// ホーム。計測開始までの通過点。計測中セッションがあれば復帰カードを最優先表示し、
/// なければ前回比ヒーロー + 円形「計測スタート」を出す。
class HomeScreen extends StatefulWidget {
  final AppServices services;
  const HomeScreen({super.key, required this.services});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _ActiveSummary {
  final Session session;
  final Machine? machine; // null=クイック計測
  final String consumedK;
  final int totalSpins;
  final double? rate;
  final String lastLabel;
  const _ActiveSummary(this.session, this.machine, this.consumedK,
      this.totalSpins, this.rate, this.lastLabel);
}

class _HomeScreenState extends State<HomeScreen> {
  AppServices get s => widget.services;
  _ActiveSummary? _active;
  Trace? _latest; // 前回の計測(最新の足跡)
  bool _loading = true;

  // 「破棄」の 2 度タップ確認。1 回目で armed → 2.6s で解除。
  bool _discardArmed = false;
  Timer? _discardTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _discardTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final session = await s.sessions.active();
    _ActiveSummary? summary;
    if (session != null) {
      // machineId が null ならクイック計測。非 null でも機種削除済みなら null。
      final machine = session.machineId == null
          ? null
          : await s.machines.byId(session.machineId!);
      final entries = await s.sessionService.entriesOf(session.id!);
      final stats = computeStats(
        entries: entries,
        border: machine?.borderFor(session.ballPrice) ?? 0,
      );
      final last = entries.isNotEmpty
          ? DateTime.tryParse(entries.last.createdAt)
          : null;
      summary = _ActiveSummary(session, machine, fmtK(stats.consumedYen),
          stats.totalRotations, stats.rotationRate, _lastInputLabel(last));
    }
    final traces = await s.traces.allDesc();
    if (!mounted) return;
    setState(() {
      _active = summary;
      _latest = traces.isEmpty ? null : traces.first;
      _loading = false;
    });
  }

  /// 「最終入力 21:34」。前日以前は日付も付ける。
  String _lastInputLabel(DateTime? t) {
    if (t == null) return '--:--';
    final hhmm = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? hhmm : '${t.month}/${t.day} $hhmm';
  }

  Future<void> _openMeasurement(Session session, Machine? machine,
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

  /// 主役: 機種選択を経由せず直接カウンタ入力へ(クイック計測)。
  Future<void> _startQuick() async {
    final result = await Navigator.of(context).push<StartResult>(
      MaterialPageRoute(builder: (_) => QuickStartScreen(services: s)),
    );
    if (result != null) {
      await _openMeasurement(result.session, result.machine);
    }
  }

  /// 従: 機種を選んで計測(ボーダー比較・期待値が要るとき)。
  Future<void> _startWithMachine() async {
    final result = await Navigator.of(context).push<StartResult>(
      MaterialPageRoute(builder: (_) => StartScreen(services: s)),
    );
    if (result != null) {
      await _openMeasurement(result.session, result.machine);
    }
  }

  /// 「破棄」= 2 度タップ確認。1 回目は arm するだけ、2 回目で実行。
  void _tapDiscard(Session session) {
    if (!_discardArmed) {
      setState(() => _discardArmed = true);
      _discardTimer?.cancel();
      _discardTimer = Timer(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() => _discardArmed = false);
      });
      return;
    }
    _discardTimer?.cancel();
    _discardArmed = false;
    _discard(session);
  }

  Future<void> _discard(Session session) async {
    await s.sessionService.discard(session.id!);
    _refresh();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: GlowBackground.home(
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 14),
                    _appTitle(),
                    Expanded(
                      child: _active != null
                          ? _restoreCard(_active!)
                          : _heroAndStart(),
                    ),
                    _bottomLinks(),
                    const SizedBox(height: 8),
                  ],
                ),
        ),
      ),
      ),
    );
  }

  // ---------- タイトル ----------
  Widget _appTitle() {
    return Center(
      child: Text('パチ回転計',
          style: AppTheme.mono(
              size: 14, weight: FontWeight.w600, letterSpacing: 0.34 * 14)),
    );
  }

  // ---------- 前回比ヒーロー + 機種選択カード + 主役の円形スタート ----------
  Widget _heroAndStart() {
    return Column(
      children: [
        Expanded(child: Center(child: _hero())),
        // 従: 機種を選んで計測(横長カード)。シアンを使わず明度差で立たせる。
        _machineSelectCard(),
        const SizedBox(height: 20),
        // 主役: 機種選択を経由せず直接カウンタ入力へ。
        _circleButton(
          label: '計測スタート',
          sub: 'START',
          size: 218,
          onTap: _startQuick,
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _machineSelectCard() {
    return GestureDetector(
      onTap: _startWithMachine,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: const Color(0x12FFFFFF), // rgba(255,255,255,0.07)
          border: Border.all(color: const Color(0x24FFFFFF)), // 0.14
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('機種を選んで計測',
                      style: AppTheme.sans(
                          size: 15,
                          weight: FontWeight.w700,
                          color: const Color(0xFFF1ECE3))),
                  const SizedBox(height: 4),
                  Text('ボーダーとの比較・期待値がでます',
                      style: AppTheme.sans(
                          size: 11, height: 1.5, color: AppColors.subtle)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.subtle),
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    final t = _latest;
    return GestureDetector(
      onTap: _openHistory,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('前回の計測',
              style: AppTheme.sans(
                  size: 10, color: AppColors.faint, letterSpacing: 0.24 * 10)),
          const SizedBox(height: 10),
          if (t == null) ...[
            Text('--.-',
                style: AppTheme.mono(
                    size: 52, weight: FontWeight.w600, color: AppColors.mutedDark)),
            const SizedBox(height: 10),
            Text('計測を終えると、ここに足跡が残ります',
                style: AppTheme.sans(size: 12, color: AppColors.mutedDark)),
          ] else ...[
            Text(t.machineName ?? '計測',
                style: AppTheme.sans(
                    size: 14,
                    color: t.machineName == null
                        ? AppColors.muted
                        : AppColors.textStrong),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(fmtRate(t.rotationRate),
                    style: AppTheme.mono(
                        size: 52, weight: FontWeight.w600, height: 1.0)),
                const SizedBox(width: 6),
                Text('回/k',
                    style: AppTheme.mono(size: 14, color: AppColors.muted)),
                if (t.borderDiff != null) ...[
                  const SizedBox(width: 12),
                  _diffBadge(t.borderDiff!),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text('${fmtShortDate(t.date)}・${t.totalRotations}回転',
                style: AppTheme.mono(size: 11.5, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }

  Widget _diffBadge(double diff) {
    final up = diff >= 0;
    final color = up ? AppColors.up : AppColors.down;
    return Text('${up ? '▲' : '▼'} B${fmtDiff(diff)}',
        style: AppTheme.mono(size: 15, weight: FontWeight.w700, color: color));
  }

  // ---------- 復帰カード ----------
  Widget _restoreCard(_ActiveSummary a) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: AppColors.accent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text('計測中のセッションがあります',
                          style: AppTheme.sans(
                              size: 12,
                              color: AppColors.muted,
                              letterSpacing: 0.04 * 12)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(a.machine?.name ?? '計測',
                      style: AppTheme.sans(
                          size: 21,
                          weight: FontWeight.w600,
                          color: a.machine == null
                              ? AppColors.muted
                              : AppColors.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  _restoreMeta(a),
                  const SizedBox(height: 4),
                  Text('最終入力 ${a.lastLabel}',
                      style:
                          AppTheme.mono(size: 11, color: AppColors.mutedDark)),
                  const SizedBox(height: 22),
                  _circleButton(
                    label: '再開',
                    sub: 'RESUME',
                    size: 164,
                    onTap: () => _openMeasurement(a.session, a.machine),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 終了して記録(アウトライン46px)
        _outlineButton('終了して記録',
            () => _openMeasurement(a.session, a.machine,
                intent: MeasureIntent.end)),
        const SizedBox(height: 10),
        // 破棄(テキスト。1 回目タップで確認文言に変化)
        GestureDetector(
          onTap: () => _tapDiscard(a.session),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              _discardArmed ? 'もう一度タップで破棄' : 'このセッションを破棄',
              textAlign: TextAlign.center,
              style: AppTheme.sans(
                  size: 12.5,
                  color: _discardArmed ? AppColors.down : AppColors.mutedDark),
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _restoreMeta(_ActiveSummary a) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(
            text: '消化 ${a.consumedK}分 ・ 総回転 ${a.totalSpins} ・ ',
            style: AppTheme.mono(size: 12, color: AppColors.muted)),
        TextSpan(
            text: '${fmtRate(a.rate)}回/k',
            style: AppTheme.mono(
                size: 12, weight: FontWeight.w600, color: AppColors.up)),
      ]),
    );
  }

  // ---------- 円形ボタン(グラデ + グロー) ----------
  Widget _circleButton({
    required String label,
    String? sub,
    required double size,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.28),
              blurRadius: 34,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: AppTheme.sans(
                    size: size >= 200 ? 20 : 18,
                    weight: FontWeight.w700,
                    color: AppColors.accentInk)),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub,
                  style: AppTheme.mono(
                      size: 10,
                      weight: FontWeight.w600,
                      letterSpacing: 0.3 * 10,
                      color: const Color(0xB304262E))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _outlineButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: AppTheme.sans(size: 13.5, color: AppColors.textStrong)),
      ),
    );
  }

  /// 最下部の 2 リンク(足跡 | 設定)。控えめだが 44px 以上で確実に押せる。
  Widget _bottomLinks() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _bottomLink(Icons.history, '足跡', _openHistory),
        Container(
          width: 1,
          height: 14,
          color: AppColors.border,
        ),
        _bottomLink(Icons.settings_outlined, '設定', _openSettings),
      ],
    );
  }

  Widget _bottomLink(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.muted),
            const SizedBox(width: 6),
            Text(label,
                style: AppTheme.sans(size: 12, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}
