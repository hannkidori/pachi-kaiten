import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../logic/anomaly.dart';
import '../../logic/rotation_calc.dart';
import '../../models/machine.dart';
import '../../services/app_services.dart';
import '../../state/measurement_controller.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../models/session.dart';
import '../start/quick_start_screen.dart';
import '../start/start_screen.dart';
import '../widgets/counter_field.dart';
import '../widgets/glow_background.dart';
import '../widgets/numpad.dart';
import 'end_sheets.dart';
import 'rotation_chart.dart';

/// 計測画面を開いた意図。end は復帰カードの「終了して収支入力」から回収額シート直行。
enum MeasureIntent { normal, end }

/// 計測画面(確定デザイン準拠)。決定フロー / 大当り / 戻す / 異常確認 /
/// 加算単位トグル / 千円ごとの回転グラフ / 終了・台移動。
/// 決定は常に「1 単位消化」の申告(現金/持ち玉の区別なし)。
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
    _c.dispose(); // 画面と寿命を共にする(遅延通知のタイマーもここで止まる)
    if (widget.keepAwake) WakelockPlus.disable();
    _shake.dispose();
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

    // コミットのフィードバック(ハプティクス)。
    if (c.feedbackTick != _lastFeedbackTick) {
      _lastFeedbackTick = c.feedbackTick;
      switch (c.lastFeedback) {
        case CommitFeedback.rebase:
          HapticFeedback.heavyImpact();
        case CommitFeedback.commit:
          HapticFeedback.selectionClick();
        case CommitFeedback.none:
          break;
      }
    }

    // バー本数が増えたら末尾へスクロール。
    final len = c.stats.segments.length;
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

  // ---------- 終了 / リセットフロー ----------

  /// ホームへ戻る。[discarded] が true なら「履歴を残さず破棄した」ことを
  /// 呼び出し元(ホーム)に伝え、ホーム側で理由を通知する。
  void _backHome({bool discarded = false}) {
    if (mounted) Navigator.of(context).pop(discarded);
  }

  /// 終了 → 任意回収額(スキップ可)→ 履歴を自動保存 → ホームへ。
  /// 総回転 0 以下のセッションは endAndLog 側で履歴を残さず破棄される
  /// (黙って消えないよう、破棄したことをホームで通知する)。
  Future<void> _endFlow() async {
    if (_flowBusy || c.isHit) return;
    // ガードはシートを開く前に立て、finally で必ず下ろす(リセットと同様)。
    _flowBusy = true;
    try {
      final st = c.stats;
      final result = await showSettlementSheet(
        context,
        machineName: c.machine?.name ?? '計測',
        rateStr: fmtRate(st.rotationRate),
        totalSpins: st.totalRotations,
      );
      if (result == null || !mounted) return; // dismiss = 中断
      final trace = await s.sessionService.endAndLog(c.session, c.machine,
          invest: result.invest, recovery: result.recovery);
      if (!mounted) return;
      _backHome(discarded: trace == null);
    } finally {
      _flowBusy = false;
    }
  }

  /// リセット → シートで 3 択 → 履歴を自動保存(回収額は聞かない)→ 新セッションへ。
  /// 実戦での「次の台へ急ぐ」出口。丁寧な出口は「終了」が担う。
  /// count 0 件のセッションは endAndLog 側で履歴を残さず破棄される。
  Future<void> _resetFlow() async {
    if (_flowBusy || c.isHit) return;
    // ガードはシートを開く前に立てる(終了とリセットの同時タップを防ぐ)。
    // 途中で例外が出ても finally で必ず下ろす(下ろし損ねると終了もリセットも
    // 二度と押せなくなる)。
    _flowBusy = true;
    try {
      final choice = await showResetSheet(
        context,
        machineName: c.machine?.name ?? '計測',
        isQuick: c.isQuick,
      );
      if (choice == null || !mounted) return; // シート外タップ = キャンセル

      final ballPrice = c.session.ballPrice;
      final addUnit = c.session.addUnit;
      final sameMachine = c.machine;
      // リセット経路は回収額を一切聞かない(記録したい人は「終了」から)。
      await s.sessionService.endAndLog(c.session, c.machine, recovery: null);
      if (!mounted) return;

      Session? newSession;
      Machine? newMachine;
      switch (choice) {
        case ResetChoice.sameCondition:
          // 同条件(同 machine_id / クイックなら null のまま)で新セッション。
          final counter =
              await showNewCounterSheet(context, machine: sameMachine);
          if (counter == null || !mounted) {
            _backHome();
            return;
          }
          newSession = await s.sessionService.start(
            machine: sameMachine,
            ballPrice: ballPrice,
            startCounter: counter,
            addUnit: addUnit,
          );
          newMachine = sameMachine;
        case ResetChoice.changeMachine:
          final result = await Navigator.of(context).push<StartResult>(
            MaterialPageRoute(builder: (_) => StartScreen(services: s)),
          );
          if (result == null || !mounted) {
            _backHome();
            return;
          }
          newSession = result.session;
          newMachine = result.machine;
        case ResetChoice.quick:
          final result = await Navigator.of(context).push<StartResult>(
            MaterialPageRoute(builder: (_) => QuickStartScreen(services: s)),
          );
          if (result == null || !mounted) {
            _backHome();
            return;
          }
          newSession = result.session;
          newMachine = result.machine;
      }

      final nc = MeasurementController(
        service: s.sessionService,
        session: newSession,
        machine: newMachine,
      );
      await nc.load();
      if (!mounted) {
        nc.dispose();
        return;
      }
      final old = _c;
      old.removeListener(_onChange);
      setState(() => _c = nc);
      _c.addListener(_onChange);
      old.dispose(); // 差し替えた旧コントローラは破棄する
      _lastLen = -1;
      _lastFeedbackTick = _c.feedbackTick; // 新コントローラに同期
      _wasError = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _snapChart());
    } finally {
      _flowBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: GlowBackground.measurement(
        child: SafeArea(
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
      ),
    );
  }

  // ---------- バナー ----------
  Widget _banner() {
    if (c.isHit) {
      return _bannerBar(
        dot: AppColors.hit,
        label: '大当り終了後、計測を開始する回転数を入力',
        labelColor: AppColors.hitText,
        note: '',
        bg: const Color(0x22E3B168),
        border: const Color(0x73E3B168),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _bannerBar({
    required Color dot,
    required String label,
    required Color labelColor,
    required String note,
    required Color bg,
    required Color border,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: border)),
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
          if (note.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(note, style: AppTheme.sans(size: 11, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }

  // ---------- ヘッダー ----------
  Widget _header() {
    final st = c.stats;
    final borderText =
        st.border > 0 ? st.border.toStringAsFixed(1) : '--';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // ブランド(シアン・10px)｜区切り線｜機種名 … 終了。クイックも同じ。
              Text('パチ回転計',
                  style: AppTheme.mono(
                      size: 10,
                      weight: FontWeight.w600,
                      color: AppColors.accent,
                      letterSpacing: 0.12 * 10)),
              Container(
                width: 1,
                height: 11,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: AppColors.border,
              ),
              Expanded(
                child: Text(
                  c.isQuick ? '機種なし' : c.machine!.name,
                  style: AppTheme.sans(
                      size: 14,
                      weight: FontWeight.w500,
                      letterSpacing: 0.02 * 14,
                      color: c.isQuick ? AppColors.muted : AppColors.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _endGhostButton(),
            ],
          ),
          const SizedBox(height: 8),
          _statLine([
            if (c.hasBorder) ('B', borderText),
            ('計測', '${fmtYen(st.consumedYen)}分'),
            ('総回転', '${st.totalRotations}'),
          ]),
        ],
      ),
    );
  }

  /// ヘッダー右端の「終了」ゴーストボタン(30px高)。大当り中は無効。
  Widget _endGhostButton() {
    final enabled = !c.isHit;
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: GestureDetector(
        onTap: enabled ? _endFlow : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('終了',
              style: AppTheme.sans(size: 12, color: AppColors.textDim)),
        ),
      ),
    );
  }

  Widget _statLine(List<(String, String)> items) {
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
      spans.add(TextSpan(
          text: items[i].$2,
          style: AppTheme.mono(
              size: 14, weight: FontWeight.w600, color: AppColors.textStrong)));
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
          // ボーダー比ボックスは hasBorder のときだけ表示(クイック計測では出さない)。
          if (c.hasBorder) ...[
            const SizedBox(height: 10),
            _diffPill(st),
          ],
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
        ],
      ),
    );
  }

  // ---------- 操作エリア ----------

  /// 短い画面(iPhone SE 第1世代 / iPhone 8 相当)では固定高の合計が画面に
  /// 収まらないため、テンキー・入力欄・決定ボタンと余白を詰める。
  bool get _compact => MediaQuery.sizeOf(context).height < 620;

  Widget _controls() {
    final gap = _compact ? 6.0 : 8.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, _compact ? 8 : 12, 20, _compact ? 10 : 16),
      child: Column(
        children: [
          _operationRow(),
          SizedBox(height: gap),
          _counterInput(),
          SizedBox(height: gap),
          _numpad(),
          SizedBox(height: gap),
          _commitButton(),
        ],
      ),
    );
  }

  /// 操作行: [★大当り] [⇄台移動] [+1000⇅ 単位] …… [↺戻す]。
  /// 左のクラスタは幅が足りなければ横スクロール、戻すは右端に固定(溢れ防止)。
  Widget _operationRow() {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (c.isHit)
                  _chip('大当り — 復帰値入力中 ×',
                      onTap: c.cancelHit,
                      active: true,
                      borderColor: const Color(0xB3E3B168))
                else
                  _chip('★ 大当り',
                      onTap: () { _haptic(); c.startHit(); },
                      borderColor: const Color(0x59E3B168),
                      textColor: AppColors.hitText),
                const SizedBox(width: 8),
                // リセット = 次の台へ急ぐ出口。⊘(禁止/クリア系)で「1つ戻す」と区別。
                _chip('⊘ リセット',
                    onTap: c.isHit ? null : _resetFlow,
                    borderColor: const Color(0x5956D9F0),
                    textColor: AppColors.accentSoft),
                const SizedBox(width: 8),
                _unitButton(),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _undoButton(),
      ],
    );
  }

  Widget _chip(String label,
      {VoidCallback? onTap,
      bool active = false,
      Color? borderColor,
      Color? textColor}) {
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
                color: borderColor ?? const Color(0x1FFFFFFF)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: AppTheme.sans(
                  size: 12,
                  weight: FontWeight.w500,
                  color: active
                      ? AppColors.hitText
                      : (textColor ?? AppColors.subtle))),
        ),
      ),
    );
  }

  Widget _unitButton() {
    // 加算単位トグル「+1000 ⇅」/「+500 ⇅」。
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
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(c.unitChipLabel,
                style: AppTheme.mono(
                    size: 11,
                    weight: FontWeight.w600,
                    color: AppColors.textStrong)),
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
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = _shake.value;
        final dx = t == 0 ? 0.0 : 5 * (1 - t) * _sinish(t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: CounterField(
        typed: c.typed,
        prevCounter: c.isHit ? null : c.lastCounter,
        rebase: c.isHit,
        error: c.isError,
        placeholder: c.isHit ? '復帰後の数字' : '台の数字',
        height: _compact ? 52 : 58,
      ),
    );
  }

  double _sinish(double t) {
    // 0→1 の間で数回振動する簡易シェイク係数。
    return (t * 12).remainder(2) < 1 ? 1 : -1;
  }

  Widget _numpad() => Numpad(
        onKey: c.tapKey,
        keyHeight: _compact ? 42 : 48,
        spacing: _compact ? 6 : 8,
      );

  Widget _commitButton() {
    final hit = c.isHit;
    return GestureDetector(
      // ハプティクスはコミット結果(cash/ball/rebase)に応じて _onChange で発火。
      onTap: () => c.commit(),
      child: Container(
        height: _compact ? 50 : 56,
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
              hit ? '復帰後の値' : c.commitSubLabel,
              style: AppTheme.mono(
                  size: 14,
                  weight: FontWeight.w600,
                  color: hit
                      ? const Color(0xB31C1206)
                      : const Color(0xBF04262E)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 異常確認シート ----------
  Widget _confirmSheet(ConfirmPrompt p) {
    final msg = p.kind == AnomalyKind.negative
        ? '回転数が増えていません。カウンタの打ち間違いの可能性があります。'
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
