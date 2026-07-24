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
enum CommitFeedback { none, commit, rebase }

/// 計測画面の状態。DB(SessionService)を唯一の真実とし、[entries] はその
/// 読み出しキャッシュ。決定・大当り・戻すは即時に DB へ反映してから再読込する。
///
/// 現金/持ち玉の区別は持たない。決定は常に「1 単位(1000/500円分)消化」の申告。
class MeasurementController extends ChangeNotifier {
  final SessionService service;
  Session session;
  final Machine? machine; // null=クイック計測(機種を選ばず計測)

  List<Entry> _entries = const [];
  String _typed = '';
  int _unit; // 加算単位(円): 1000 / 500
  bool _hit = false; // 大当り復帰値の入力中
  bool _error = false; // 入力枠の赤シェイク
  ConfirmPrompt? _confirm;

  // ---- フィードバック用の一過性状態 ----
  int _feedbackTick = 0; // コミットのたびに増える(画面が変化を検知する)
  CommitFeedback _lastFeedback = CommitFeedback.none;

  MeasurementController({
    required this.service,
    required this.session,
    required this.machine,
  }) : _unit = session.addUnit;

  // ---- 公開状態 ----
  List<Entry> get entries => _entries;
  String get typed => _typed;
  int get unit => _unit;

  /// 単位チップの表示。「+1000」/「+500」。
  String get unitChipLabel => '+$_unit';

  /// 決定ボタンのサブ表示。「+1000円分」/「+500円分」。
  String get commitSubLabel => '+$_unit円分';

  bool get isHit => _hit;
  bool get isError => _error;
  ConfirmPrompt? get confirm => _confirm;

  /// ボーダーがあるか(クイック計測・未登録スロットは false)。
  bool get hasBorder => (machine?.borderFor(session.ballPrice) ?? 0) > 0;

  /// クイック計測(機種を選ばず計測)か。
  bool get isQuick => machine == null;

  /// コミットのたびに増えるシーケンス。画面はこの変化でハプティクス/演出を発火する。
  int get feedbackTick => _feedbackTick;
  CommitFeedback get lastFeedback => _lastFeedback;

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
        border: machine?.borderFor(session.ballPrice) ?? 0,
      );

  /// DB からイベントを読み込む。
  Future<void> load() async {
    _entries = await service.entriesOf(session.id!);
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

  // ---- 単位 ----
  void cycleUnit() {
    if (_hit) return;
    _unit = _unit == 1000 ? 500 : 1000;
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
      await load();
      return;
    }

    final prev = lastCounter;
    final delta = n - prev;
    final kind = detectAnomaly(
      diff: delta,
      addUnit: _unit,
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
    // 常に 1 単位(_unit 円分)消化として確定する。
    await service.recordCount(session, counter: n, yen: _unit);
    _typed = '';
    _confirm = null;
    _lastFeedback = CommitFeedback.commit;
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
