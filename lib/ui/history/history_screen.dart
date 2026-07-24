import 'package:flutter/material.dart';

import '../../models/trace.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';

/// 足跡。セッション終了時に自動保存された 1 行レコードの時系列リスト(新しい順)。
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('この足跡を削除しますか?',
            style: AppTheme.sans(size: 15, weight: FontWeight.w700)),
        content: Text('${fmtShortDate(t.date)} ${t.machineName} の記録を削除します。',
            style: AppTheme.sans(size: 13, color: AppColors.textStrong)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('やめる',
                style: AppTheme.sans(size: 13, color: AppColors.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('削除する',
                style: AppTheme.sans(size: 13, color: AppColors.down)),
          ),
        ],
      ),
    );
    if (ok == true && t.id != null) {
      await s.traces.delete(t.id!);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _topBar(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _traces.isEmpty
                      ? _empty()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          itemCount: _traces.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _traceRow(_traces[i]),
                        ),
            ),
          ],
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
          Text('足跡', style: AppTheme.sans(size: 17, weight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Text('まだ足跡はありません',
          style: AppTheme.sans(size: 13, color: AppColors.mutedDark)),
    );
  }

  Widget _traceRow(Trace t) {
    // 例: 7/22 ハネデリ 18.3回/k・412回転・EV+2,840 ・+3,500円
    final evColor = (t.evYen ?? 0) >= 0 ? AppColors.up : AppColors.down;
    return GestureDetector(
      onTap: () => _delete(t),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 42,
              child: Text(fmtShortDate(t.date),
                  style: AppTheme.mono(size: 13, color: AppColors.textDim)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.machineName ?? '計測のみ',
                      style: AppTheme.sans(
                          size: 13,
                          weight: FontWeight.w500,
                          color: t.machineName == null
                              ? AppColors.muted
                              : AppColors.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: '${fmtRate(t.rotationRate)}回/k',
                          style: AppTheme.mono(
                              size: 12, color: AppColors.textStrong)),
                      TextSpan(
                          text: '・${t.totalRotations}回転',
                          style:
                              AppTheme.mono(size: 12, color: AppColors.muted)),
                      // クイック計測(機種なし)の足跡は EV を表示しない。
                      if (t.machineName != null)
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
                              color: t.plYen! >= 0
                                  ? AppColors.up
                                  : AppColors.down),
                        ),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
