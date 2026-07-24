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
import '../start/machine_sheets.dart';
import '../widgets/counter_field.dart';
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

  /// 文脈内オンボーディングを有効にするか(テストでは false にしてDB読込を避ける)。
  final bool enableOnboarding;

  const MeasurementScreen({
    super.key,
    required this.controller,
    required this.services,
    this.keepAwake = true,
    this.initialIntent = MeasureIntent.normal,
    this.enableOnboarding = true,
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

  // 文脈内オンボーディング。0=なし / 1=カウンタ説明 / 2=大当り説明。
  int _onbStep = 0;
  bool _onbHitDone = true; // フラグ読込までは発火させない

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
      if (widget.initialIntent == MeasureIntent.end) {
        _endFlow();
      } else if (widget.enableOnboarding) {
        _loadOnboarding();
      }
    });
  }

  /// オンボーディングの表示済みフラグを読み込む。未表示なら初回スポットを出す。
  Future<void> _loadOnboarding() async {
    final counterDone = await s.settings.onbCounterDone();
    final hitDone = await s.settings.onbHitDone();
    if (!mounted) return;
    setState(() {
      _onbHitDone = hitDone;
      // 初回の計測画面表示時、カウンタ+決定をスポット。
      if (!counterDone) _onbStep = 1;
    });
  }

  Future<void> _dismissOnbCounter() async {
    setState(() => _onbStep = 0);
    await s.settings.setOnbCounterDone();
  }

  Future<void> _dismissOnbHit() async {
    setState(() {
      _onbStep = 0;
      _onbHitDone = true;
    });
    await s.settings.setOnbHitDone();
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
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
          // 初セッションの決定5回目で大当りボタンの説明を1回だけ出す。
          if (!_onbHitDone && _onbStep == 0 && c.commitCount == 5) {
            setState(() => _onbStep = 2);
          }
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

  String _stamp() => DateTime.now().toIso8601String();

  // ---------- 終了 / 台移動フロー ----------

  void _backHome() {
    if (mounted) Navigator.of(context).pop();
  }

  /// 終了 → 任意回収額(スキップ可)→ 足跡を自動保存 → ホームへ。
  /// count 0 件のセッションは endAndLog 側で足跡を残さず破棄される。
  Future<void> _endFlow() async {
    if (_flowBusy || c.isHit) return;
    final st = c.stats;
    final result = await showRecoverySheet(
      context,
      forMove: false,
      machineName: c.machine?.name ?? '計測',
      rateStr: fmtRate(st.rotationRate),
      totalSpins: st.totalRotations,
    );
    if (result == null || !mounted) return; // dismiss = 中断
    _flowBusy = true;
    await s.sessionService
        .endAndLog(c.session, c.machine, recovery: result.recovery);
    _flowBusy = false;
    if (!mounted) return;
    _backHome();
  }

  /// 台移動 → 確認 → 任意回収額 → 足跡保存 → 機種選択(登録/スロット入力対応)
  /// → 新カウンタ → 新セッションに差し替え。
  Future<void> _moveFlow() async {
    if (_flowBusy || c.isHit) return;
    final st = c.stats;
    final go = await showMoveConfirm(
      context,
      machineName: c.machine?.name ?? '計測',
      investK: fmtK(st.consumedYen),
      totalSpins: st.totalRotations,
    );
    if (go != true || !mounted) return;
    final result = await showRecoverySheet(
      context,
      forMove: true,
      machineName: c.machine?.name ?? '計測',
      rateStr: fmtRate(st.rotationRate),
      totalSpins: st.totalRotations,
    );
    if (result == null || !mounted) return;

    _flowBusy = true;
    final ballPrice = c.session.ballPrice;
    final addUnit = c.session.addUnit;
    await s.sessionService
        .endAndLog(c.session, c.machine, recovery: result.recovery);

    final machines = await s.machines.all();
    if (!mounted) {
      _flowBusy = false;
      return;
    }
    final pick = await showMachinePick(
      context,
      machines: machines,
      sameMachine: c.machine,
      ballPrice: ballPrice,
    );
    if (pick == null || !mounted) {
      _flowBusy = false;
      _backHome();
      return;
    }

    final picked = await _resolvePickedMachine(pick, ballPrice);
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

    final newSession = await s.sessionService.start(
      machine: picked,
      ballPrice: ballPrice,
      startCounter: counter,
      addUnit: addUnit,
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

  /// 機種選択結果を「開始できる Machine」に解決する。
  /// 新規登録 or 該当スロット未入力なら、その場で入力を求めて保存する(育つマスタ)。
  Future<Machine?> _resolvePickedMachine(
      MachinePick pick, double ballPrice) async {
    if (pick.register) {
      final reg = await showRegisterMachine(context, ballPrice: ballPrice);
      if (reg == null) return null;
      final base = Machine(name: reg.name, updatedAt: _stamp());
      return s.machines
          .insert(applyBorder(base, ballPrice, reg.border, _stamp()));
    }
    var picked = pick.machine!;
    if (picked.borderFor(ballPrice) == null) {
      final entered = await showBorderPrompt(
        context,
        machineName: picked.name,
        ballPrice: ballPrice,
        current: null,
      );
      if (entered == null) return null;
      picked = applyBorder(picked, ballPrice, entered, _stamp());
      await s.machines.update(picked);
    }
    return picked;
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
                if (_onbStep == 1)
                  _onbOverlay(
                    align: Alignment.bottomCenter,
                    text: '1000円分打ったら、台の上の回転数を入力して決定。'
                        'それだけで回転率が出ます。',
                    button: 'はじめる',
                    onTap: _dismissOnbCounter,
                  ),
                if (_onbStep == 2)
                  _onbOverlay(
                    align: Alignment.topCenter,
                    text: '大当りしたら打ち終わるまでそのまま。通常に戻ったら'
                        '『大当り』を押して、台の上の回転数を入れ直すだけ。',
                    button: 'OK',
                    onTap: _dismissOnbHit,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 文脈内オンボーディングのスポットライト(対象方向に説明カードを浮かせる)。
  /// 実画面を暗幕で覆い、指定方向にメッセージ + ボタンを出す。
  Widget _onbOverlay({
    required Alignment align,
    required String text,
    required String button,
    required VoidCallback onTap,
  }) {
    return Positioned.fill(
      child: Container(
        color: const Color(0xD6040507), // rgba(4,5,7,0.84)
        padding: const EdgeInsets.all(28),
        child: Align(
          alignment: align,
          child: Container(
            margin: const EdgeInsets.only(bottom: 24, top: 24),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: const Color(0x5956D9F0)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(text,
                    style: AppTheme.sans(
                        size: 13.5, color: AppColors.text, height: 1.7)),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppColors.accentGradient,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(button,
                        style: AppTheme.sans(
                            size: 15,
                            weight: FontWeight.w700,
                            color: AppColors.accentInk)),
                  ),
                ),
              ],
            ),
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
        label: '大当り',
        labelColor: AppColors.hitText,
        note: '— 復帰後のカウンタ値を入力',
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
          const SizedBox(width: 6),
          Text(note, style: AppTheme.sans(size: 11, color: AppColors.muted)),
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
              Expanded(
                child: Text(
                  c.isQuick ? '計測' : c.machine!.name,
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
            ('消化', '${fmtK(st.consumedYen)}分'),
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
          _operationRow(),
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
                  _chip('大当り — 復帰値入力中 ✕',
                      onTap: c.cancelHit,
                      active: true,
                      borderColor: const Color(0xB3E3B168))
                else
                  _chip('★ 大当り',
                      onTap: () { _haptic(); c.startHit(); },
                      borderColor: const Color(0x59E3B168),
                      textColor: AppColors.hitText),
                const SizedBox(width: 8),
                _chip('⇄ 台移動',
                    onTap: c.isHit ? null : _moveFlow,
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
