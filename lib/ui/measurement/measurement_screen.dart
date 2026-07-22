import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../logic/anomaly.dart';
import '../../logic/rotation_calc.dart';
import '../../models/entry.dart';
import '../../services/app_services.dart';
import '../../state/measurement_controller.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../widgets/numpad.dart';
import 'end_sheets.dart';
import 'rotation_chart.dart';

/// 計測画面を開いた意図。end は復帰カードの「終了して収支入力」から回収額シート直行。
enum MeasureIntent { normal, end }

/// 計測画面(確定デザイン準拠)。決定フロー / 大当り / 戻す / 異常確認 /
/// 現金・持ち玉 / 加算単位トグル / 千円ごとの回転グラフ / 終了・台移動。
class MeasurementScreen extends StatefulWidget {
  final MeasurementController controller;
  final AppServices services;

  /// 計測画面のスリープ防止(設定でOFF可。デフォルトON)。
  final bool keepAwake;

  /// 開いた直後に回収額シートへ直行するか。
  final MeasureIntent initialIntent;

  const MeasurementScreen({
    super.key,
    required this.controller,
    required this.services,
    this.keepAwake = true,
    this.initialIntent = MeasureIntent.normal,
  });

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen>
    with TickerProviderStateMixin {
  final _chartCtrl = ScrollController();
  late final AnimationController _shake;
  late final AnimationController _bannerFlash; // rebase 時のバナー強調
  late final AnimationController _totalPulse; // 持ち玉決定時の総回転ハイライト
  int _lastLen = -1;
  int _lastFeedbackTick = 0;
  bool _wasError = false;
  bool _flowBusy = false; // 終了/台移動フロー実行中の多重起動防止

  late MeasurementController _c;
  MeasurementController get c => _c;
  AppServices get s => widget.services;

  @override
  void initState() {
    super.initState();
    _c = widget.controller;
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bannerFlash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _totalPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _lastFeedbackTick = _c.feedbackTick;
    if (widget.keepAwake) WakelockPlus.enable();
    _c.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapChart();
      if (widget.initialIntent == MeasureIntent.end) _endFlow();
    });
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    if (widget.keepAwake) WakelockPlus.disable();
    _shake.dispose();
    _bannerFlash.dispose();
    _totalPulse.dispose();
    _chartCtrl.dispose();
    super.dispose();
  }

  void _onChange() {
    // 入力枠のシェイクを error フラグ立ち上がりで発火。
    if (c.isError && !_wasError) {
      _shake.forward(from: 0);
      HapticFeedback.mediumImpact();
    }
    _wasError = c.isError;

    // コミットのフィードバック(ハプティクス + 演出)。
    if (c.feedbackTick != _lastFeedbackTick) {
      _lastFeedbackTick = c.feedbackTick;
      switch (c.lastFeedback) {
        case CommitFeedback.rebase:
          HapticFeedback.heavyImpact();
          _bannerFlash.forward(from: 0);
        case CommitFeedback.ballCommit:
          HapticFeedback.mediumImpact();
          _totalPulse.forward(from: 0);
        case CommitFeedback.cashCommit:
          HapticFeedback.selectionClick();
        case CommitFeedback.none:
          break;
      }
    }

    // バー本数(計測対象=現金+消費玉>0の持ち玉)が増えたら末尾へスクロール。
    final len = c.stats.segments.where((s) => s.measured).length;
    if (len != _lastLen) {
      _lastLen = len;
      WidgetsBinding.instance.addPostFrameCallback((_) => _snapChart());
    }
  }

  void _snapChart() {
    if (_chartCtrl.hasClients) {
      _chartCtrl.jumpTo(_chartCtrl.position.maxScrollExtent);
    }
  }

  void _haptic() => HapticFeedback.selectionClick();

  // ---------- 終了 / 台移動フロー ----------

  /// 現セッションを回収額つきで closed にし、サマリーを組み立てる。
  Future<SessionSummary> _closeCurrent(int recovery) async {
    final closed = await s.sessionService.close(c.session, recovery: recovery);
    final stats = await s.sessionService.stats(closed, c.machine);
    return SessionSummary(session: closed, machine: c.machine, stats: stats);
  }

  void _backHome() {
    if (mounted) Navigator.of(context).pop();
  }

  /// 終了 → 回収額入力 → サマリー → ホームへ。
  Future<void> _endFlow() async {
    if (_flowBusy || c.isHit) return;
    final recovery = await showRecoverySheet(context, forMove: false);
    if (recovery == null || !mounted) return;
    _flowBusy = true;
    final summary = await _closeCurrent(recovery);
    _flowBusy = false;
    if (!mounted) return;
    await showSummarySheet(context, summary);
    _backHome();
  }

  /// 台移動 → 確認 → 回収額 → 機種選択(先頭に同じ機種)→ 新カウンタ → 新セッション。
  /// 旧セッションの closed と新セッションの start が途切れなく繋がる。
  Future<void> _moveFlow() async {
    if (_flowBusy || c.isHit) return;
    final st = c.stats;
    final go = await showMoveConfirm(
      context,
      machineName: c.machine.name,
      investK: fmtK(st.cashInvest),
      totalSpins: st.totalRotations,
    );
    if (go != true || !mounted) return;
    final recovery = await showRecoverySheet(context, forMove: true);
    if (recovery == null || !mounted) return;

    _flowBusy = true;
    final oldSession = c.session;
    await _closeCurrent(recovery); // 旧セッションを収支に記録

    final machines = await s.machines.all();
    if (!mounted) {
      _flowBusy = false;
      return;
    }
    final picked = await showMachinePick(
      context,
      machines: machines,
      sameMachine: c.machine,
      exchangeRate: oldSession.exchangeRate,
    );
    if (picked == null || !mounted) {
      _flowBusy = false;
      _backHome();
      return;
    }
    final counter = await showNewCounterSheet(context, machine: picked);
    if (counter == null || !mounted) {
      _flowBusy = false;
      _backHome();
      return;
    }

    final store = await s.stores.byId(oldSession.storeId);
    final newSession = await s.sessionService.start(
      store: store!,
      machine: picked,
      startCounter: counter,
      addUnit: oldSession.addUnit,
    );
    final nc = MeasurementController(
      service: s.sessionService,
      session: newSession,
      machine: picked,
    );
    await nc.load();
    if (!mounted) {
      _flowBusy = false;
      return;
    }
    _c.removeListener(_onChange);
    setState(() => _c = nc);
    _c.addListener(_onChange);
    _lastLen = -1;
    _flowBusy = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _snapChart());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            return Stack(
              children: [
                Column(
                  children: [
                    _banner(),
                    _header(),
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      color: AppColors.hair,
                    ),
                    Expanded(child: _hero()),
                    _controls(),
                  ],
                ),
                if (c.confirm != null) _confirmSheet(c.confirm!),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------- バナー ----------
  Widget _banner() {
    if (c.isHit) {
      return _bannerBar(
        dot: AppColors.hit,
        label: '大当り',
        labelColor: AppColors.hitText,
        note: '— 復帰後のカウンタ値を入力',
        bg: const Color(0x22E3B168),
        border: const Color(0x73E3B168),
      );
    }
    // rebase 直後の数秒間は「基準を{値}に更新」を強調表示(点滅)。
    final announce = c.rebaseAnnounce;
    if (announce != null) {
      return AnimatedBuilder(
        animation: _bannerFlash,
        builder: (context, _) => _bannerBar(
          dot: AppColors.accent,
          label: '基準を$announceに更新',
          labelColor: AppColors.accentSoft,
          note: '— 持ち玉で継続中',
          bg: const Color(0x1F6BCBDD),
          border: const Color(0x666BCBDD),
          flash: _flashIntensity(),
        ),
      );
    }
    if (c.isBall) {
      return _bannerBar(
        dot: AppColors.accent,
        label: '持ち玉計測中',
        labelColor: AppColors.accentSoft,
        note: '— 消費玉も回転率に算入',
        bg: const Color(0x1F6BCBDD),
        border: const Color(0x666BCBDD),
      );
    }
    return const SizedBox.shrink();
  }

  /// rebase バナーの点滅強度(0..1)。900ms かけて 2 回ほど明滅して収束する。
  double _flashIntensity() {
    final t = _bannerFlash.value;
    if (t <= 0 || t >= 1) return 0;
    final blink = math.cos(t * 4 * math.pi).clamp(0.0, 1.0);
    return (1 - t) * blink;
  }

  Widget _bannerBar({
    required Color dot,
    required String label,
    required Color labelColor,
    required String note,
    required Color bg,
    required Color border,
    double flash = 0,
  }) {
    // flash の分だけ背景・枠を明るく重ねる(強調)。
    final overlay = Color.lerp(bg, const Color(0x556BCBDD), flash)!;
    final overlayBorder =
        Color.lerp(border, const Color(0xCC6BCBDD), flash)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      decoration: BoxDecoration(
        color: overlay,
        border: Border(bottom: BorderSide(color: overlayBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.sans(
                    size: 12, weight: FontWeight.w500, color: labelColor)),
          ),
          const SizedBox(width: 6),
          Text(note, style: AppTheme.sans(size: 11, color: AppColors.muted)),
        ],
      ),
    );
  }

  // ---------- ヘッダー ----------
  Widget _header() {
    final st = c.stats;
    final rate = c.session.exchangeRate.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  c.machine.name,
                  style: AppTheme.sans(
                      size: 14,
                      weight: FontWeight.w500,
                      letterSpacing: 0.02 * 14),
                ),
              ),
              Text('1/${c.machine.probability}',
                  style: AppTheme.mono(size: 13, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 8),
          // 総回転(最後の項目)は持ち玉決定時に短くハイライトする。
          AnimatedBuilder(
            animation: _totalPulse,
            builder: (context, _) {
              final p = _totalPulse.isAnimating ? (1 - _totalPulse.value) : 0.0;
              return _statLine(
                [
                  ('実質B', st.effectiveBorder.toStringAsFixed(1)),
                  ('換金', rate),
                  ('投資', fmtK(st.cashInvest)),
                  ('総回転', '${st.totalRotations}'),
                ],
                highlightLastAmount: p,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _statLine(List<(String, String)> items,
      {double highlightLastAmount = 0}) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        spans.add(TextSpan(
            text: ' ・ ',
            style: AppTheme.mono(size: 12, color: AppColors.muted)));
      }
      spans.add(TextSpan(
          text: '${items[i].$1} ',
          style: AppTheme.mono(size: 12, color: AppColors.muted)));
      final isLast = i == items.length - 1;
      final valueColor = isLast && highlightLastAmount > 0
          ? Color.lerp(AppColors.textStrong, AppColors.accent,
              highlightLastAmount)!
          : AppColors.textStrong;
      spans.add(TextSpan(
          text: items[i].$2,
          style: AppTheme.mono(
              size: 14, weight: FontWeight.w600, color: valueColor)));
    }
    // 1 行に収める(折り返して高さが伸びる/横に溢れるのを防ぐ)。
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(TextSpan(children: spans), maxLines: 1, softWrap: false),
    );
  }

  // ---------- ヒーロー(回転率 + 比較 + グラフ) ----------
  Widget _hero() {
    final st = c.stats;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('回転率',
              style: AppTheme.sans(
                  size: 11, color: AppColors.muted, letterSpacing: 0.22 * 11)),
          const SizedBox(height: 4),
          // 回転率の数字は余地があれば 96px、狭ければ高さ方向にも縮む
          // (FittedBox は幅・高さ両方を縮小)。数字を優先して flex を大きめに。
          Flexible(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(fmtRate(st.rotationRate),
                      style: AppTheme.mono(
                          size: 96,
                          weight: FontWeight.w600,
                          height: 0.95,
                          letterSpacing: -0.02 * 96)),
                  const SizedBox(width: 10),
                  Text('回/k',
                      style: AppTheme.mono(size: 17, color: AppColors.muted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _diffPill(st),
          const SizedBox(height: 14),
          // グラフはヒーローの残り高さに追従して縮む(自身で溢れないよう保証)。
          Flexible(
            flex: 2,
            child: RotationChart(stats: st, controller: _chartCtrl),
          ),
        ],
      ),
    );
  }

  Widget _diffPill(RotationStats st) {
    final diff = st.borderDiff;
    final Color color;
    final Color bg;
    final Color border;
    final String arrow;
    if (diff == null) {
      color = AppColors.mutedDark;
      bg = Colors.transparent;
      border = const Color(0x1AFFFFFF);
      arrow = '';
    } else if (diff >= 0) {
      color = AppColors.up;
      bg = const Color(0x1A3ECF8E);
      border = const Color(0x403ECF8E);
      arrow = '▲ ';
    } else {
      color = AppColors.down;
      bg = const Color(0x1AF06A5D);
      border = const Color(0x40F06A5D);
      arrow = '▼ ';
    }
    final evStr = st.expectedValue == null
        ? '--'
        : fmtYenSigned(st.expectedValue!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(diff == null ? '-- --' : '$arrow${fmtDiff(diff)}',
              style: AppTheme.mono(
                  size: 24, weight: FontWeight.w600, color: color)),
          const SizedBox(width: 12),
          Text('ボーダー比',
              style: AppTheme.sans(size: 11, color: AppColors.muted)),
          const SizedBox(width: 12),
          // 期待値は残り幅に収める(大きな金額でも右端で溢れない)。
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: '期待値 ',
                    style: AppTheme.sans(size: 11, color: AppColors.muted)),
                TextSpan(
                    text: evStr,
                    style: AppTheme.mono(
                        size: 14, weight: FontWeight.w600, color: color)),
              ])),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 操作エリア ----------
  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: [
          _actionChips(),
          const SizedBox(height: 8),
          _modeRow(),
          const SizedBox(height: 8),
          _counterInput(),
          const SizedBox(height: 8),
          _numpad(),
          const SizedBox(height: 8),
          _commitButton(),
        ],
      ),
    );
  }

  Widget _actionChips() {
    return Row(
      children: [
        if (c.isHit)
          _chip(
            '大当り — 復帰値入力中 ✕',
            onTap: c.cancelHit,
            active: true,
          )
        else
          _chip('大当り', onTap: () { _haptic(); c.startHit(); }),
        const SizedBox(width: 8),
        _chip('台移動', onTap: c.isHit ? null : _moveFlow),
        const Spacer(),
        _chip('終了', onTap: c.isHit ? null : _endFlow),
      ],
    );
  }

  Widget _chip(String label, {VoidCallback? onTap, bool active = false}) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0x33E3B168) : Colors.transparent,
            border: Border.all(
                color: active
                    ? const Color(0xB3E3B168)
                    : const Color(0x1FFFFFFF)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: AppTheme.sans(
                  size: 12,
                  weight: FontWeight.w500,
                  color: active ? AppColors.hitText : AppColors.subtle)),
        ),
      ),
    );
  }

  Widget _modeRow() {
    final gated = c.isHit;
    return Row(
      children: [
        Opacity(
          opacity: gated ? 0.35 : 1,
          child: IgnorePointer(
            ignoring: gated,
            child: _modeToggle(),
          ),
        ),
        const SizedBox(width: 6),
        _unitButton(),
        const Spacer(),
        _undoButton(),
      ],
    );
  }

  Widget _modeToggle() {
    Widget seg(String label, bool on, VoidCallback onTap, Color onColor) {
      return GestureDetector(
        onTap: on ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: on
                ? (c.isBall ? const Color(0x296BCBDD) : AppColors.chipActive)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
              style: AppTheme.sans(
                  size: 12.5,
                  weight: on ? FontWeight.w500 : FontWeight.w400,
                  color: on ? onColor : AppColors.mutedDark)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(
            color: c.isBall ? const Color(0x666BCBDD) : AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('現金', c.isCash, () => c.setMode(EntryMode.cash), AppColors.text),
        seg('持ち玉', c.isBall, () => c.setMode(EntryMode.ball),
            AppColors.accentSoft),
      ]),
    );
  }

  Widget _unitButton() {
    // 現金は「+1000/+500」、持ち玉は「250玉/500玉」(貸玉連動)。両モードで有効。
    final gated = c.isHit;
    return Opacity(
      opacity: gated ? 0.35 : 1,
      child: GestureDetector(
        onTap: gated ? null : () { _haptic(); c.cycleUnit(); },
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            border: Border.all(
                color: c.isBall ? const Color(0x666BCBDD) : AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(c.unitChipLabel,
                style: AppTheme.mono(
                    size: 11,
                    weight: FontWeight.w600,
                    color: c.isBall
                        ? AppColors.accentSoft
                        : AppColors.textStrong)),
            const SizedBox(width: 4),
            Text('⇅',
                style: AppTheme.sans(size: 9, color: AppColors.mutedDark)),
          ]),
        ),
      ),
    );
  }

  Widget _undoButton() {
    final enabled = !c.isHit;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        onTap: enabled ? () { _haptic(); c.undo(); } : null,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x26FFFFFF)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('↺', style: AppTheme.sans(size: 15, color: AppColors.textDim)),
            const SizedBox(width: 6),
            Text('戻す',
                style: AppTheme.sans(size: 12.5, color: AppColors.textDim)),
          ]),
        ),
      ),
    );
  }

  Widget _counterInput() {
    final hint = c.isHit ? '復帰後のカウンタ値を入力' : '前回 ${c.lastCounter}';
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = _shake.value;
        final dx = t == 0 ? 0.0 : 5 * (1 - t) * _sinish(t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          border: Border.all(
              color: c.isError
                  ? const Color(0xCCF06A5D)
                  : const Color(0x596BCBDD)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text('カウンタ',
                style: AppTheme.sans(
                    size: 10, color: AppColors.muted, letterSpacing: 0.12 * 10)),
            const SizedBox(width: 10),
            Text(hint, style: AppTheme.mono(size: 11, color: AppColors.mutedDark)),
            const Spacer(),
            Text(c.typed,
                style:
                    AppTheme.mono(size: 22, weight: FontWeight.w500)),
            const _BlinkingCursor(),
          ],
        ),
      ),
    );
  }

  double _sinish(double t) {
    // 0→1 の間で数回振動する簡易シェイク係数。
    return (t * 12).remainder(2) < 1 ? 1 : -1;
  }

  Widget _numpad() => Numpad(onKey: c.tapKey);

  Widget _commitButton() {
    final hit = c.isHit;
    return GestureDetector(
      // ハプティクスはコミット結果(cash/ball/rebase)に応じて _onChange で発火。
      onTap: () => c.commit(),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: hit ? AppColors.hitButton : AppColors.accentDeep,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('決定',
                style: AppTheme.sans(
                    size: 19,
                    weight: FontWeight.w700,
                    letterSpacing: 0.2 * 19,
                    color: hit ? AppColors.hitInk : AppColors.accentInk)),
            const SizedBox(width: 10),
            Text(
              hit ? '復帰後の値 → 持ち玉で継続' : c.commitSubLabel,
              style: AppTheme.mono(
                  size: 14,
                  weight: FontWeight.w600,
                  color: hit
                      ? const Color(0xB31C1206)
                      : const Color(0xBF06171B)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 異常確認シート ----------
  Widget _confirmSheet(ConfirmPrompt p) {
    final msg = p.kind == AnomalyKind.negative
        ? '差分がマイナスです。カウンタの打ち間違いの可能性があります。'
        : '1000円あたりの回転数として異常に大きい値です。打ち間違いがないか確認してください。';
    return Stack(
      children: [
        const ModalBarrier(color: Color(0xC2060810)),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('入力値の確認',
                    style: AppTheme.sans(
                        size: 14,
                        weight: FontWeight.w700,
                        color: AppColors.hitText)),
                const SizedBox(height: 12),
                Text('前回 ${p.prev} → 今回 ${p.next}',
                    style:
                        AppTheme.mono(size: 15, color: AppColors.textStrong)),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('差分',
                        style:
                            AppTheme.sans(size: 11, color: AppColors.muted)),
                    const SizedBox(width: 10),
                    Text(
                        '${p.delta >= 0 ? '+' : '−'}${p.delta.abs()}',
                        style: AppTheme.mono(
                            size: 26,
                            weight: FontWeight.w600,
                            color: AppColors.down)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(msg,
                    style: AppTheme.sans(
                        size: 11.5, color: AppColors.muted, height: 1.6)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 13,
                      child: _sheetButton('入力し直す',
                          primary: true, onTap: c.confirmRetry),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 10,
                      child: _sheetButton('確定する',
                          primary: false, onTap: c.confirmForce),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sheetButton(String label,
      {required bool primary, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? AppColors.accentDeep : Colors.transparent,
          border:
              primary ? null : Border.all(color: const Color(0x2EFFFFFF)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: AppTheme.sans(
                size: primary ? 14.5 : 13.5,
                weight: primary ? FontWeight.w700 : FontWeight.w400,
                color: primary ? AppColors.accentInk : AppColors.textStrong)),
      ),
    );
  }
}

/// カーソルの点滅(1.1s)。
class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Opacity(
          opacity: _ctrl.value < 0.5 ? 1 : 0,
          child: Container(
            width: 2,
            height: 22,
            margin: const EdgeInsets.only(left: 3),
            color: AppColors.accent,
          ),
        );
      },
    );
  }
}
