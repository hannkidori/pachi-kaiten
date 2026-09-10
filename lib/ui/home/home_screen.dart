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
  final String consumedYen;
  final int totalSpins;
  final double? rate;
  final String lastLabel;
  const _ActiveSummary(this.session, this.machine, this.consumedYen,
      this.totalSpins, this.rate, this.lastLabel);
}

class _HomeScreenState extends State<HomeScreen> {
  AppServices get s => widget.services;
  _ActiveSummary? _active;
  Trace? _latest; // 前回の計測(最新の履歴)
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

  /// ホームの表示内容を読み直す。
  ///
  /// スピナーは初回だけ([_loading] の初期値 true)。計測画面から戻るたびに
  /// 全画面が点滅しないよう、2 回目以降は前の内容を出したまま差し替える。
  Future<void> _refresh() async {
    if (!mounted) return;
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
      summary = _ActiveSummary(session, machine, fmtYen(stats.consumedYen),
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
    // 履歴が 1 件増えたか(=計測を終えたか)を id で見分ける。単に「戻る」で
    // 抜けた場合と区別してレビュー依頼の判定に使う。
    final beforeTraceId = _latest?.id;
    final discarded = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => MeasurementScreen(
        controller: controller,
        services: s,
        keepAwake: keepAwake,
        initialIntent: intent,
      ),
    ));
    if (!mounted) return;
    // 回転が記録されていないセッションは履歴を残さず破棄される。黙って消えた
    // ように見えないよう理由を伝える。
    if (discarded == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('回転が記録されていないため、履歴は残しませんでした',
            style: AppTheme.sans(size: 12.5, color: AppColors.text)),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    }
    await _refresh();
    // 計測中は割り込まず、計測を終えた区切りでだけレビュー依頼を検討する
    // (条件を満たさなければ何も起きない)。
    final trace = _latest;
    if (trace != null && trace.id != beforeTraceId) {
      await s.reviewPrompt.onMeasurementEnded(trace);
    }
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

  /// 従: 機種を選んで計測(ボーダーとの比較が要るとき)。
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
      // 丸ボタンは色しか変わらず armed が伝わりにくいので、文字でも知らせる。
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('もう一度押すと破棄します',
            style: AppTheme.sans(size: 12.5, color: AppColors.text)),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2600),
      ));
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _appTitle(),
                    Expanded(
                      child: _active != null
                          ? _restoreCard(_active!)
                          : _heroAndStart(),
                    ),
                    _footer(),
                  ],
                ),
        ),
      ),
    );
  }

  /// 縦に余裕のない端末(小型 Android など)。リングと固定余白をそのまま置くと
  /// フッターがはみ出すため、まとめて一段小さくする。
  bool get _short => MediaQuery.sizeOf(context).height < 720;

  /// リングの直径。
  double get _ringSize => _short ? 232 : 300;

  /// タイトルからリングまでの固定余白。計測中は機種名 1 行ぶん(35)を引く。
  double get _topGap => _short ? 56 : 165;

  // ---------- タイトル ----------
  Widget _appTitle() {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Center(
        child: Text('パチ回転計',
            style: AppTheme.sans(
                size: 15,
                weight: FontWeight.w700,
                color: AppColors.textStrong,
                letterSpacing: 0.2 * 15)),
      ),
    );
  }

  // ---------- 前回比ヒーロー + 機種選択カード + 主役の円形スタート ----------
  /// 開いた瞬間に計測へ入れることを最優先にした並び。
  /// リングの上端を計測中の表示と揃えるため、固定スペーサーで押し下げる。
  Widget _heroAndStart() {
    return Column(
      children: [
        SizedBox(height: _topGap),
        _ring(
          onTap: _startQuick,
          children: [
            Text('計測スタート',
                style: AppTheme.sans(
                    size: 34,
                    weight: FontWeight.w700,
                    letterSpacing: 0.06 * 34)),
            const SizedBox(height: 10),
            Text('START',
                style: AppTheme.mono(
                    size: 12,
                    color: AppColors.accent,
                    letterSpacing: 0.35 * 12)),
          ],
        ),
        SizedBox(height: _short ? 24 : 40),
        _machineSelectCard(),
        const Spacer(),
      ],
    );
  }
  // ---------- 復帰カード ----------
  /// 中断中のセッションを 1 タップで再開する。リングの上端は通常時と揃える
  /// (機種名の 1 行ぶんスペーサーを縮める)。
  /// 「機種を選んで計測 ›」。主役(リング)の下に置く従の導線。
  Widget _machineSelectCard() {
    return Center(
      child: GestureDetector(
        onTap: _startWithMachine,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('機種を選んで計測',
                  style: AppTheme.sans(size: 14, color: AppColors.textStrong)),
              const SizedBox(width: 8),
              Text('›', style: AppTheme.sans(size: 16, color: AppColors.faint)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _restoreCard(_ActiveSummary a) {
    final quick = a.machine == null;
    return Column(
      children: [
        SizedBox(height: quick ? _topGap : 14),
        if (!quick) ...[
          Text(a.machine!.name,
              textAlign: TextAlign.center,
              style: AppTheme.sans(size: 14, color: AppColors.textStrong),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          SizedBox(height: _topGap - 35),
        ],
        _ring(
          onTap: () => _openMeasurement(a.session, a.machine),
          children: [
            // 78px の「--.-」は点と罫が散らばって壊れて見えるので「--」に落とす。
            Text(a.rate == null ? '--' : a.rate!.toStringAsFixed(1),
                style: AppTheme.mono(
                    size: 78,
                    weight: FontWeight.w700,
                    height: 1,
                    letterSpacing: -0.02 * 78)),
            const SizedBox(height: 8),
            Text('回/k', style: AppTheme.mono(size: 14, color: AppColors.muted)),
            const SizedBox(height: 26),
            Text('タップで再開',
                style: AppTheme.sans(
                    size: 14,
                    weight: FontWeight.w700,
                    color: AppColors.accent,
                    letterSpacing: 0.2 * 14)),
          ],
        ),
        SizedBox(height: _short ? 24 : 40),
        _restoreMeta(a),
        const Spacer(),
      ],
    );
  }

  /// 「1,000円 · 25回転  最終 12:33」。
  Widget _restoreMeta(_ActiveSummary a) {
    return SizedBox(
      height: 44,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${a.consumedYen} · ${a.totalSpins}回転',
                  style: AppTheme.mono(size: 14, color: AppColors.muted)),
              const SizedBox(width: 8),
              Text('最終 ${a.lastLabel}',
                  style: AppTheme.mono(size: 14, color: AppColors.mutedDark)),
            ],
          ),
        ),
      ),
    );
  }

  /// 主役のリング 300×300。面は塗らず、ミント 2px の枠と外側の薄いハローだけ。
  Widget _ring({required VoidCallback onTap, required List<Widget> children}) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: _ringSize,
          height: _ringSize,
          decoration: const BoxDecoration(
            color: AppColors.bg,
            shape: BoxShape.circle,
            border: Border.fromBorderSide(
                BorderSide(color: AppColors.accent, width: 2)),
            boxShadow: [
              BoxShadow(color: AppColors.accentHalo, spreadRadius: 14),
            ],
          ),
          // 文字を大きくする設定でもリングの中で収める。
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
  /// 最下部の 2 リンク(履歴 | 設定)。控えめだが 44px 以上で確実に押せる。
  /// フッター。通常は 履歴 / 前回 / 設定、計測中は 破棄 / 終了して記録 / 設定。
  Widget _footer() {
    final a = _active;
    if (a == null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _roundButton('履歴', _openHistory),
          if (_latest != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: GestureDetector(
                onTap: _openHistory,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('前回 ',
                        style: AppTheme.sans(
                            size: 12, color: AppColors.mutedDark)),
                    Text('${fmtRate(_latest!.rotationRate)}回/k',
                        style:
                            AppTheme.mono(size: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            ),
          _roundButton('設定', _openSettings),
        ],
      );
    }
    return Row(
      children: [
        _roundButton('破棄', () => _tapDiscard(a.session),
            danger: _discardArmed),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => _openMeasurement(a.session, a.machine,
                intent: MeasureIntent.end),
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.borderStrong),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Text('終了して記録',
                  style:
                      AppTheme.sans(size: 15, color: AppColors.textStrong)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _roundButton('設定', _openSettings),
      ],
    );
  }

  /// フッターの丸ボタン 52×52。枠線だけで面は光らせない。
  Widget _roundButton(String label, VoidCallback onTap,
      {bool danger = false}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: danger ? AppColors.down : AppColors.border),
        ),
        child: Text(label,
            style: AppTheme.sans(
                size: 13,
                color: danger ? AppColors.down : AppColors.muted)),
      ),
    );
  }
}
