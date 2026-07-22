import '../models/entry.dart';
import '../models/machine.dart';
import '../models/session.dart';
import '../models/trace.dart';
import '../repositories/entry_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/trace_repository.dart';
import 'rotation_calc.dart';

/// 計測フローのオーケストレーション。
///
/// 最重要ポリシー: 決定タップの瞬間に同期的に DB へ書き込む。呼び出し側の
/// メモリ状態は DB の読み出しキャッシュにすぎず、いつアプリが殺されても
/// 確定済みイベントは失われない。
///
/// [clock] を差し替えることでテスト時に時刻を固定できる。
class SessionService {
  final SessionRepository sessions;
  final EntryRepository entries;
  final TraceRepository traces;
  final DateTime Function() clock;

  SessionService({
    required this.sessions,
    required this.entries,
    required this.traces,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  String _iso(DateTime t) => t.toIso8601String();
  String _date(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  /// 新しいセッションを開始し、start イベントを追記する。
  ///
  /// [ballPrice] は開始時点のグローバル貸玉設定をコピーして固定する。
  Future<Session> start({
    required Machine machine,
    required double ballPrice,
    required int startCounter,
    int addUnit = 1000,
  }) async {
    final now = clock();
    final session = await sessions.insert(Session(
      date: _date(now),
      machineId: machine.id!,
      ballPrice: ballPrice,
      addUnit: addUnit,
      state: SessionState.active,
      startedAt: _iso(now),
    ));
    await entries.insert(Entry(
      sessionId: session.id!,
      type: EntryType.start,
      counter: startCounter,
      mode: EntryMode.cash,
      createdAt: _iso(now),
    ));
    return session;
  }

  /// 決定タップ。追記後の Entry を返す(即時書き込み)。
  ///
  /// - cash: [investAdded](円)を渡す。未指定なら [Session.addUnit]。
  /// - ball: [ballsAdded](玉)を渡す。持ち玉消費として計測に算入される。
  Future<Entry> recordCount(
    Session session, {
    required int counter,
    required EntryMode mode,
    int? investAdded,
    int ballsAdded = 0,
  }) async {
    final now = clock();
    final entry = Entry(
      sessionId: session.id!,
      type: EntryType.count,
      counter: counter,
      mode: mode,
      investAdded:
          mode == EntryMode.cash ? (investAdded ?? session.addUnit) : 0,
      ballsAdded: mode == EntryMode.ball ? ballsAdded : 0,
      createdAt: _iso(now),
    );
    final id = await entries.insert(entry);
    return Entry(
      id: id,
      sessionId: entry.sessionId,
      type: entry.type,
      counter: entry.counter,
      mode: entry.mode,
      investAdded: entry.investAdded,
      ballsAdded: entry.ballsAdded,
      createdAt: entry.createdAt,
    );
  }

  /// 大当り復帰。差分計算の起点を付け替える。以降のモードは持ち玉になる。
  Future<Entry> recordRebase(Session session, {required int counter}) async {
    final now = clock();
    final entry = Entry(
      sessionId: session.id!,
      type: EntryType.rebase,
      counter: counter,
      mode: EntryMode.ball,
      createdAt: _iso(now),
    );
    final id = await entries.insert(entry);
    return Entry(
      id: id,
      sessionId: entry.sessionId,
      type: entry.type,
      counter: entry.counter,
      mode: entry.mode,
      investAdded: entry.investAdded,
      createdAt: entry.createdAt,
    );
  }

  /// 1 つ戻す。直前の count 1 件のみ削除(start / rebase は戻せない)。
  Future<bool> undoLastCount(int sessionId) {
    return entries.deleteLastIfCount(sessionId);
  }

  /// 現在のモード。rebase 以降は ball、それ以外は最後の count のモード。
  /// イベントが無ければ cash。
  Future<EntryMode> currentMode(int sessionId) async {
    final last = await entries.last(sessionId);
    if (last == null) return EntryMode.cash;
    if (last.type == EntryType.rebase) return EntryMode.ball;
    return last.mode;
  }

  /// 差分計算の起点となる直近カウンタ(次の入力補助・初回判定に使う)。
  Future<Entry?> lastEntry(int sessionId) => entries.last(sessionId);

  /// セッションの全イベント(追記順)。画面のキャッシュ再読込に使う。
  Future<List<Entry>> entriesOf(int sessionId) => entries.bySession(sessionId);

  /// 破棄。セッションと計測イベントを物理削除する(復帰カードの「破棄」)。
  Future<void> discard(int sessionId) async {
    await entries.deleteBySession(sessionId);
    await sessions.delete(sessionId);
  }

  /// 終了。回収額(任意)を確定し closed にする。
  Future<Session> close(Session session, {int? recovery}) async {
    final now = clock();
    final closed = session.copyWith(
      state: SessionState.closed,
      recovery: recovery,
      closedAt: _iso(now),
    );
    await sessions.update(closed);
    return closed;
  }

  /// セッションの現在統計を計算する。
  ///
  /// ボーダーは機種の該当スロット。未入力の場合は 0(判定・EV は出ない)。
  Future<RotationStats> stats(Session session, Machine machine) async {
    final list = await entries.bySession(session.id!);
    return computeStats(
      entries: list,
      border: machine.borderFor(session.ballPrice) ?? 0,
      ballPrice: session.ballPrice,
    );
  }

  /// 終了の集約点。終了 / 台移動 / 復帰カード終了の 3 経路すべてがここを通る。
  ///
  /// - count イベントが 1 件も無い(極端に短い)セッションは足跡を残さず破棄する。
  /// - それ以外は close して計測データから足跡を 1 行自動保存する。
  ///   回収額 [recovery] を渡せば P/L(回収 − 現金投資)も記録、null ならスキップ扱い。
  ///
  /// 保存した [Trace] を返す(破棄した場合は null)。
  Future<Trace?> endAndLog(
    Session session,
    Machine machine, {
    int? recovery,
  }) async {
    final list = await entries.bySession(session.id!);
    final hasCount = list.any((e) => e.type == EntryType.count);
    if (!hasCount) {
      await discard(session.id!);
      return null;
    }

    await close(session, recovery: recovery);
    final stats = computeStats(
      entries: list,
      border: machine.borderFor(session.ballPrice) ?? 0,
      ballPrice: session.ballPrice,
    );

    final now = clock();
    final trace = Trace(
      date: session.date,
      machineName: machine.name,
      rotationRate: stats.rotationRate,
      totalRotations: stats.totalRotations,
      evYen: stats.expectedValue?.round(),
      investYen: stats.cashInvest,
      bonusCount: stats.bonusCount,
      plYen: recovery == null ? null : recovery - stats.cashInvest,
      createdAt: _iso(now),
    );
    final id = await traces.insert(trace);
    return Trace(
      id: id,
      date: trace.date,
      machineName: trace.machineName,
      rotationRate: trace.rotationRate,
      totalRotations: trace.totalRotations,
      evYen: trace.evYen,
      investYen: trace.investYen,
      bonusCount: trace.bonusCount,
      plYen: trace.plYen,
      createdAt: trace.createdAt,
    );
  }
}
