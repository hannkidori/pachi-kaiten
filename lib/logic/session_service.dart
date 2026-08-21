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
  /// [machine] が null ならクイック計測(機種を選ばず計測)。
  /// [ballPrice] は開始時点のグローバル貸玉設定をコピーして固定する。
  Future<Session> start({
    required Machine? machine,
    required double ballPrice,
    required int startCounter,
    int addUnit = 1000,
  }) async {
    final now = clock();
    final session = await sessions.insert(Session(
      date: _date(now),
      machineId: machine?.id,
      ballPrice: ballPrice,
      addUnit: addUnit,
      state: SessionState.active,
      startedAt: _iso(now),
    ));
    await entries.insert(Entry(
      sessionId: session.id!,
      type: EntryType.start,
      counter: startCounter,
      createdAt: _iso(now),
    ));
    return session;
  }

  /// 決定タップ。追記後の Entry を返す(即時書き込み)。
  ///
  /// [yen] はこの決定で消化した金額(円 = 加算単位)。未指定なら [Session.addUnit]。
  Future<Entry> recordCount(
    Session session, {
    required int counter,
    int? yen,
  }) async {
    final now = clock();
    final entry = Entry(
      sessionId: session.id!,
      type: EntryType.count,
      counter: counter,
      yen: yen ?? session.addUnit,
      createdAt: _iso(now),
    );
    final id = await entries.insert(entry);
    return Entry(
      id: id,
      sessionId: entry.sessionId,
      type: entry.type,
      counter: entry.counter,
      yen: entry.yen,
      createdAt: entry.createdAt,
    );
  }

  /// 大当り復帰。差分計算の起点を付け替える(通常状態へ戻る)。
  Future<Entry> recordRebase(Session session, {required int counter}) async {
    final now = clock();
    final entry = Entry(
      sessionId: session.id!,
      type: EntryType.rebase,
      counter: counter,
      createdAt: _iso(now),
    );
    final id = await entries.insert(entry);
    return Entry(
      id: id,
      sessionId: entry.sessionId,
      type: entry.type,
      counter: entry.counter,
      yen: entry.yen,
      createdAt: entry.createdAt,
    );
  }

  /// 1 つ戻す。直前の count 1 件のみ削除(start / rebase は戻せない)。
  Future<bool> undoLastCount(int sessionId) {
    return entries.deleteLastIfCount(sessionId);
  }

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
  /// ボーダーは機種の該当スロット。未入力/クイック計測は 0(判定・EV は出ない)。
  Future<RotationStats> stats(Session session, Machine? machine) async {
    final list = await entries.bySession(session.id!);
    return computeStats(
      entries: list,
      border: machine?.borderFor(session.ballPrice) ?? 0,
    );
  }

  /// 終了の集約点。終了 / リセット / 復帰カード終了の 3 経路すべてがここを通る。
  ///
  /// - **総回転が 0 以下**(= 決定なし、または打ち始め値と同値で決定しただけ等の
  ///   空セッション)は足跡を残さず破棄する。最初の決定は異常値判定をスキップする
  ///   ため delta 0 の count が作られ得るので、count 件数でなく総回転で判定する。
  /// - それ以外は close して計測データから足跡を 1 行自動保存する。
  ///   回収額 [recovery] を渡せば P/L(回収 − 消化額)も記録、null ならスキップ扱い。
  ///
  /// 保存した [Trace] を返す(破棄した場合は null)。
  Future<Trace?> endAndLog(
    Session session,
    Machine? machine, {
    int? recovery,
  }) async {
    final list = await entries.bySession(session.id!);
    final stats = computeStats(
      entries: list,
      border: machine?.borderFor(session.ballPrice) ?? 0,
    );
    // 空セッション(総回転 0 以下)は足跡を残さず破棄する。
    if (stats.totalRotations <= 0) {
      await discard(session.id!);
      return null;
    }

    await close(session, recovery: recovery);

    final now = clock();
    final trace = Trace(
      date: session.date,
      machineName: machine?.name, // null=クイック計測
      rotationRate: stats.rotationRate,
      borderDiff: stats.borderDiff,
      totalRotations: stats.totalRotations,
      evYen: stats.expectedValue?.round(),
      consumedYen: stats.consumedYen,
      bonusCount: stats.bonusCount,
      plYen: recovery == null ? null : recovery - stats.consumedYen,
      createdAt: _iso(now),
    );
    final id = await traces.insert(trace);
    return Trace(
      id: id,
      date: trace.date,
      machineName: trace.machineName,
      rotationRate: trace.rotationRate,
      borderDiff: trace.borderDiff,
      totalRotations: trace.totalRotations,
      evYen: trace.evYen,
      consumedYen: trace.consumedYen,
      bonusCount: trace.bonusCount,
      plYen: trace.plYen,
      createdAt: trace.createdAt,
    );
  }
}
