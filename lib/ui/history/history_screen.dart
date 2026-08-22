import 'package:flutter/material.dart';

import '../../models/trace.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../widgets/glow_background.dart';

/// 履歴。セッション終了時に自動保存された 1 行レコードの時系列リスト(新しい順)。
/// 集計・グラフ・フィルタ・編集は一切なし。行タップで削除のみ。
class HistoryScreen extends StatefulWidget {
  final AppServices services;
  const HistoryScreen({super.key, required this.services});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  AppServices get s => widget.services;
  List<Trace> _traces = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final traces = await s.traces.allDesc();
    if (!mounted) return;
    setState(() {
      _traces = traces;
      _loading = false;
    });
  }

  Future<void> _delete(Trace t) async {
    final ok = await _showDeleteSheet(t);
    if (ok == true && t.id != null) {
      await s.traces.delete(t.id!);
      await _load();
    }
  }

  /// 削除確認シート(編集・詳細・共有なし。削除確認のみ)。
  Future<bool?> _showDeleteSheet(Trace t) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xC2060810),
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('この履歴を削除しますか',
                style: AppTheme.sans(size: 14, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('削除した履歴は元に戻せません',
                style: AppTheme.sans(size: 12, color: AppColors.muted)),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () => Navigator.pop(context, true),
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x1FF06A5D),
                  border: Border.all(color: const Color(0x59F06A5D)),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text('削除する',
                    style: AppTheme.sans(
                        size: 15, weight: FontWeight.w700, color: AppColors.down)),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.pop(context, false),
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x2EFFFFFF)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('キャンセル',
                    style: AppTheme.sans(size: 13.5, color: AppColors.textStrong)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: GlowBackground.list(
        child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _topBar(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _traces.isEmpty
                      ? _empty()
                      : _list(),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: AppColors.textDim),
          ),
          Text('履歴', style: AppTheme.sans(size: 16, weight: FontWeight.w700)),
          const Spacer(),
          if (_traces.isNotEmpty)
            Text('${_traces.length}件',
                style: AppTheme.mono(size: 11, color: AppColors.faint)),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text('計測を終えると、ここに履歴が残ります',
            textAlign: TextAlign.center,
            style: AppTheme.sans(size: 13, color: AppColors.mutedDark)),
      ),
    );
  }

  /// 月ラベルを挟みつつ履歴行を並べる。
  Widget _list() {
    final items = <Widget>[];
    String? lastMonth;
    for (final t in _traces) {
      final month = t.date.length >= 7 ? t.date.substring(0, 7) : t.date;
      if (month != lastMonth) {
        lastMonth = month;
        items.add(_monthLabel(month));
      }
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _traceRow(t),
      ));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: items,
    );
  }

  /// 月ラベル `2026.07`。
  Widget _monthLabel(String yyyyMm) {
    final label = yyyyMm.length >= 7
        ? '${yyyyMm.substring(0, 4)}.${yyyyMm.substring(5, 7)}'
        : yyyyMm;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Text(label,
          style: AppTheme.mono(
              size: 10, color: AppColors.mutedDark, letterSpacing: 0.2 * 10)),
    );
  }

  Widget _traceRow(Trace t) {
    final isQuick = t.machineName == null;
    // EV 不明(ボーダー未登録)は緑=プラスに見えないよう中立色にする。
    final evColor = t.evYen == null
        ? AppColors.muted
        : (t.evYen! >= 0 ? AppColors.up : AppColors.down);
    return GestureDetector(
      onTap: () => _delete(t),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1 段目: 日付 + 機種名。
            Row(
              children: [
                Text(fmtShortDate(t.date),
                    style: AppTheme.mono(size: 13, color: AppColors.muted)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(t.machineName ?? '計測',
                      style: AppTheme.sans(
                          size: 13,
                          weight: FontWeight.w500,
                          color: isQuick ? AppColors.muted : AppColors.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 5),
            // 2 段目: 回転率(主役)・回転・EV・P/L。
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '${fmtRate(t.rotationRate)}回/k',
                    style: AppTheme.mono(
                        size: 14, weight: FontWeight.w600, color: AppColors.text)),
                TextSpan(
                    text: '・${t.totalRotations}回転',
                    style: AppTheme.mono(size: 12, color: AppColors.muted)),
                // クイック計測(機種なし)の履歴は EV を表示しない。
                if (!isQuick)
                  TextSpan(
                      text:
                          '・EV${t.evYen == null ? '--' : fmtSignedNum(t.evYen!)}',
                      style: AppTheme.mono(size: 12, color: evColor)),
                if (t.plYen != null)
                  TextSpan(
                    text: '・${fmtSignedNum(t.plYen!)}円',
                    style: AppTheme.mono(
                        size: 12,
                        weight: FontWeight.w600,
                        color: t.plYen! >= 0 ? AppColors.up : AppColors.down),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
