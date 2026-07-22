import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logic/anomaly.dart';
import '../logic/rotation_calc.dart';
import '../logic/session_service.dart';
import '../models/entry.dart';
import '../models/machine.dart';
import '../models/session.dart';

/// 異常確認シートの内容。
class ConfirmPrompt {
  final int prev;
  final int next;
  final int delta;
  final AnomalyKind kind;
  const ConfirmPrompt(this.prev, this.next, this.delta, this.kind);
}

/// 直前のコミットで起きたこと(画面のフィードバック演出用)。
enum CommitFeedback { none, cashCommit, ballCommit, rebase }

/// 計測画面の状態。DB(SessionService)を唯一の真実とし、[entries] はその
/// 読み出しキャッシュ。決定・大当り・戻すは即時に DB へ反映してから再読込する。
class MeasurementController extends ChangeNotifier {
  final SessionService service;
  Session session;
  final Machine machine;

  List<Entry> _entries = const [];
  String _typed = '';
  EntryMode _mode = EntryMode.cash;
  int _cashUnit; // 現金の加算単位(円): 1000 / 500
  late int _ballUnit; // 持ち玉の消費単位(玉): base / 2×base(貸玉連動)
  bool _hit = false; // 大当り復帰値の入力中
  bool _error = false; // 入力枠の赤シェイク
  ConfirmPrompt? _confirm;

  // ---- フィードバック用の一過性状態 ----
  int _feedbackTick = 0; // コミットのたびに増える(画面が変化を検知する)
  CommitFeedback _lastFeedback = CommitFeedback.none;
  int? _rebaseAnnounce; // rebase 直後、数秒間バナーに出す「基準を{値}に更新」の値
  Timer? _announceTimer;

  MeasurementController({
    required this.service,
    required this.session,
    required this.machine,
  }) : _cashUnit = session.addUnit {
    _ballUnit = _ballUnitBase; // 貸玉連動の基準玉数(4円=250, 1円=1000)
  }

  /// 持ち玉単位の基準玉数(= 1000 円相当の玉数)。4円=250 / 1円=1000。
  int get _ballUnitBase => (1000 / session.ballPrice).round();

  // ---- 公開状態 ----
  List<Entry> get entries => _entries;
  String get typed => _typed;
  EntryMode get mode => _mode;
  int get cashUnit => _cashUnit;
  int get ballUnit => _ballUnit;

  /// 異常判定に使う「この決定の投資相当額(円)」。
  int get activeUnitYen =>
      isCash ? _cashUnit : (_ballUnit * session.ballPrice).round();

  /// 単位チップの表示。現金は「+1000」、持ち玉は「250玉」。
  String get unitChipLabel => isCash ? '+$_cashUnit' : '$_ballUnit玉';

  /// 決定ボタンのサブ表示。現金は「+1000円」、持ち玉は「250玉」。
  String get commitSubLabel => isCash ? '+$_cashUnit円' : '$_ballUnit玉';

  bool get isHit => _hit;
  bool get isError => _error;
  ConfirmPrompt? get confirm => _confirm;
  bool get isCash => _mode == EntryMode.cash;
  bool get isBall => _mode == EntryMode.ball;

  /// コミットのたびに増えるシーケンス。画面はこの変化でハプティクス/演出を発火する。
  int get feedbackTick => _feedbackTick;
  CommitFeedback get lastFeedback => _lastFeedback;

  /// rebase 直後の数秒間だけ非 null。バナーの強調表示に使う。
  int? get rebaseAnnounce => _rebaseAnnounce;

  @override
  void dispose() {
    _announceTimer?.cancel();
    super.dispose();
  }

  /// 直近イベントが count でない(start / rebase 直後)= 異常判定をスキップする境界。
  /// UI のゲートには使わない(計測画面は常に通常状態で開く)。
  bool get _firstAfterOrigin {
    final last = _lastEntry;
    return last == null || last.type != EntryType.count;
  }

  Entry? get _lastEntry => _entries.isEmpty ? null : _entries.last;

  /// 差分計算の起点カウンタ(最後のイベントの counter)。
  int get lastCounter => _lastEntry?.counter ?? 0;

  RotationStats get stats => computeStats(
        entries: _entries,
        catalogBorder: machine.borderForRate(session.exchangeRate),
        ballPrice: session.ballPrice,
      );

  /// DB からイベントを読み込み、現在モードを最終イベントから導出する。
  Future<void> load() async {
    _entries = await service.entriesOf(session.id!);
    final last = _lastEntry;
    if (last != null) {
      _mode = last.type == EntryType.rebase ? EntryMode.ball : last.mode;
    }
    notifyListeners();
  }

  // ---- テンキー ----
  void tapKey(String d) {
    if (d == '⌫') {
      if (_typed.isNotEmpty) _typed = _typed.substring(0, _typed.length - 1);
    } else {
      final next = (_typed + d);
      _typed = next.length > 6 ? next.substring(0, 6) : next;
    }
    notifyListeners();
  }

  void _flagError() {
    _error = true;
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 420), () {
      _error = false;
      notifyListeners();
    });
  }

  // ---- モード / 単位 ----
  void setMode(EntryMode m) {
    if (_hit) return;
    _mode = m;
    notifyListeners();
  }

  void cycleUnit() {
    if (_hit) return;
    if (isCash) {
      _cashUnit = _cashUnit == 1000 ? 500 : 1000;
    } else {
      // 持ち玉: 基準玉数 ↔ 2×基準玉数(4円=250/500, 1円=1000/2000)。
      _ballUnit = _ballUnit == _ballUnitBase ? _ballUnitBase * 2 : _ballUnitBase;
    }
    notifyListeners();
  }

  // ---- 大当り ----
  void startHit() {
    if (_hit) return;
    _hit = true;
    _typed = '';
    notifyListeners();
  }

  void cancelHit() {
    _hit = false;
    _typed = '';
    notifyListeners();
  }

  // ---- 決定 ----
  Future<void> commit() async {
    if (_typed.isEmpty) {
      _flagError();
      return;
    }
    final n = int.tryParse(_typed);
    if (n == null) {
      _flagError();
      return;
    }

    if (_hit) {
      if (n <= 0) {
        _flagError();
        return;
      }
      await service.recordRebase(session, counter: n);
      _hit = false;
      _typed = '';
      _lastFeedback = CommitFeedback.rebase;
      _feedbackTick++;
      _rebaseAnnounce = n; // 数秒間バナーに「基準を{n}に更新」を出す
      _announceTimer?.cancel();
      _announceTimer = Timer(const Duration(seconds: 3), () {
        _rebaseAnnounce = null;
        notifyListeners();
      });
      await load(); // mode は rebase により ball になる
      return;
    }

    final prev = lastCounter;
    final delta = n - prev;
    final kind = detectAnomaly(
      diff: delta,
      addUnit: activeUnitYen, // 持ち玉も円換算した投資相当でしきい値を出す
      isFirstAfterOrigin: _firstAfterOrigin,
    );
    if (kind != AnomalyKind.none) {
      _confirm = ConfirmPrompt(prev, n, delta, kind);
      _flagError();
      return;
    }
    await _doCommit(n);
  }

  Future<void> _doCommit(int n) async {
    final committedMode = _mode;
    // cash は現金投資(円)、ball は持ち玉消費(玉)を確定する。
    await service.recordCount(
      session,
      counter: n,
      mode: committedMode,
      investAdded: committedMode == EntryMode.cash ? _cashUnit : null,
      ballsAdded: committedMode == EntryMode.ball ? _ballUnit : 0,
    );
    _typed = '';
    _confirm = null;
    _lastFeedback = committedMode == EntryMode.ball
        ? CommitFeedback.ballCommit
        : CommitFeedback.cashCommit;
    _feedbackTick++;
    await load();
  }

  /// 異常確認シート: 入力し直す。
  void confirmRetry() {
    _confirm = null;
    _typed = '';
    notifyListeners();
  }

  /// 異常確認シート: このまま確定する(入力値をそのまま追記)。
  Future<void> confirmForce() async {
    final c = _confirm;
    if (c == null) return;
    await _doCommit(c.next);
  }

  // ---- 1つ戻す ----
  Future<void> undo() async {
    if (_hit) return; // count が無ければ undoLastCount は no-op
    final removed = await service.undoLastCount(session.id!);
    if (removed) {
      _typed = '';
      await load();
    }
  }
}
