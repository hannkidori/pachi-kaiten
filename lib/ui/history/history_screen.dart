import 'package:flutter/material.dart';

import '../../logic/history_aggregation.dart';
import '../../logic/history_service.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';

/// 履歴・収支(確定デザイン準拠)。月チップ → 月収支サマリー →
/// 日別グルーピング(展開でセッション一覧)。
class HistoryScreen extends StatefulWidget {
  final AppServices services;
  const HistoryScreen({super.key, required this.services});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  HistoryService get h => widget.services.history;

  List<String> _months = [];
  String? _month;
  MonthData? _data;
  final Set<String> _open = {};
  bool _loading = true;
  bool _byMachine = false; // 日別 / 機種別 の切替

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final months = await h.months();
    setState(() {
      _months = months;
      _month = months.isNotEmpty ? months.first : null;
    });
    if (_month != null) {
      await _loadMonth(_month!);
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMonth(String month) async {
    setState(() {
      _loading = true;
      _month = month;
      _open.clear();
    });
    final data = await h.load(month);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerAndChips(),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_month == null)
              Expanded(child: _empty())
            else ...[
              _viewToggle(),
              Expanded(child: _byMachine ? _machineList() : _dayList()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Text('まだ記録がありません',
            style: AppTheme.sans(size: 13, color: AppColors.muted)),
      );

  Widget _headerAndChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: AppColors.textDim),
              ),
              Text('履歴・収支',
                  style: AppTheme.sans(size: 16, weight: FontWeight.w700)),
            ],
          ),
          if (_months.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _months.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => _monthChip(_months[i]),
                ),
              ),
            ),
          if (_data != null && _month != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 12),
              child: _monthSummary(),
            ),
        ],
      ),
    );
  }

  Widget _monthChip(String month) {
    final selected = month == _month;
    return GestureDetector(
      onTap: () => _loadMonth(month),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.chipActive : Colors.transparent,
          border: Border.all(
              color: selected ? const Color(0x1FFFFFFF) : AppColors.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(fmtMonthChip(month),
            style: AppTheme.mono(
                size: 12,
                weight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.text : AppColors.mutedDark)),
      ),
    );
  }

  Widget _monthSummary() {
    final aggs = _data!.aggregates;
    final invest = aggs.fold(0, (a, s) => a + s.invest);
    final recovery = aggs.fold(0, (a, s) => a + s.recovery);
    final ev = aggs.fold(0.0, (a, s) => a + s.expectedValue);
    final bal = recovery - invest;

    // 勝率(±0円の日を除外)。
    final days = groupByDay(aggs);
    final decided = days.where((d) => d.dayProfit != 0).toList();
    final wins = decided.where((d) => d.dayProfit > 0).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.hair),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(fmtMonthTitle(_month!),
                  style: AppTheme.sans(
                      size: 10,
                      color: AppColors.muted,
                      letterSpacing: 0.1 * 10)),
              const SizedBox(width: 10),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(fmtYenSigned(bal),
                      style: AppTheme.mono(
                          size: 24,
                          weight: FontWeight.w600,
                          color: bal >= 0 ? AppColors.up : AppColors.down)),
                ),
              ),
              const SizedBox(width: 10),
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: '期待値合計 ',
                    style: AppTheme.sans(size: 10, color: AppColors.muted)),
                TextSpan(
                    text: fmtYenSigned(ev),
                    style:
                        AppTheme.mono(size: 10, color: AppColors.textStrong)),
              ])),
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: '勝率 ',
                style: AppTheme.sans(size: 10, color: AppColors.muted)),
            TextSpan(
                text: decided.isEmpty
                    ? '—'
                    : '${(wins / decided.length * 100).round()}% '
                        '($wins/${decided.length}日)',
                style: AppTheme.mono(size: 10, color: AppColors.textStrong)),
          ])),
        ],
      ),
    );
  }

  // ---------- 日別 / 機種別 トグル ----------
  Widget _viewToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            _toggleSeg('日別', !_byMachine, () {
              if (_byMachine) setState(() => _byMachine = false);
            }),
            _toggleSeg('機種別', _byMachine, () {
              if (!_byMachine) setState(() => _byMachine = true);
            }),
          ],
        ),
      ),
    );
  }

  Widget _toggleSeg(String label, bool on, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: on ? null : onTap,
        child: Container(
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.chipActive : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
              style: AppTheme.sans(
                  size: 12.5,
                  weight: on ? FontWeight.w600 : FontWeight.w400,
                  color: on ? AppColors.text : AppColors.mutedDark)),
        ),
      ),
    );
  }

  // ---------- 機種別リスト(投資額の降順、回収率主指標) ----------
  Widget _machineList() {
    final machines = groupByMachine(_data!.aggregates);
    if (machines.isEmpty) return _empty();
    final names = _data!.machineNames;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: machines.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _machineCard(machines[i], names),
    );
  }

  Widget _machineCard(MachineSummary m, Map<String, String> names) {
    final rate = m.recoveryRate; // 回収率(%)、投資0なら null
    final rateColor =
        (rate ?? 0) >= 100 ? AppColors.up : AppColors.down;
    final profit = m.profit;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(names[m.machineId] ?? m.machineId,
                    style: AppTheme.sans(size: 13, weight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 10),
              Text(fmtYenSigned(profit),
                  style: AppTheme.mono(
                      size: 16,
                      weight: FontWeight.w600,
                      color: profit >= 0 ? AppColors.up : AppColors.down)),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              _kv('台数', '${m.sessionCount}'),
              const SizedBox(width: 14),
              _kv('投資', fmtK(m.totalInvest)),
              const SizedBox(width: 14),
              _kv('回収率', rate == null ? '—' : '${rate.round()}%',
                  color: rateColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayList() {
    final days = groupByDay(_data!.aggregates);
    if (days.isEmpty) return _empty();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: days.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _dayCard(days[i]),
    );
  }

  Widget _dayCard(DaySummary d) {
    final open = _open.contains(d.date);
    final bal = d.dayProfit;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(11),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() {
              if (open) {
                _open.remove(d.date);
              } else {
                _open.add(d.date);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(fmtDayLabel(d.date),
                          style:
                              AppTheme.sans(size: 13, weight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Text('${d.sessionCount}台',
                          style:
                              AppTheme.sans(size: 10.5, color: AppColors.muted)),
                      const Spacer(),
                      Text(fmtYenSigned(bal),
                          style: AppTheme.mono(
                              size: 18,
                              weight: FontWeight.w600,
                              color: bal >= 0 ? AppColors.up : AppColors.down)),
                      const SizedBox(width: 6),
                      Text(open ? '▴' : '▾',
                          style:
                              AppTheme.sans(size: 11, color: AppColors.mutedDark)),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      _kv('投資', fmtK(d.totalInvest)),
                      const SizedBox(width: 14),
                      _kv('回収', fmtK(d.totalRecovery)),
                      const SizedBox(width: 14),
                      _kv('期待値', fmtYenSigned(d.evSum),
                          color: d.evSum >= 0 ? AppColors.up : AppColors.down),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (open) _sessionList(d),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, {Color color = AppColors.textStrong}) {
    return Text.rich(TextSpan(children: [
      TextSpan(
          text: '$label ',
          style: AppTheme.mono(size: 11, color: AppColors.muted)),
      TextSpan(text: value, style: AppTheme.mono(size: 11, color: color)),
    ]));
  }

  Widget _sessionList(DaySummary d) {
    final names = _data!.machineNames;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x12FFFFFF))),
      ),
      child: Column(
        children: [
          for (final a in d.sessions)
            Container(
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: Color(0x0DFFFFFF))),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(names[a.session.machineId] ?? a.session.machineId,
                            style: AppTheme.sans(size: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          '${fmtRate(a.stats.rotationRate)}回/k ・ '
                          '投資${fmtK(a.invest)} ・ 回収${fmtK(a.recovery)}',
                          style:
                              AppTheme.mono(size: 10.5, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(fmtYenSigned(a.profit),
                      style: AppTheme.mono(
                          size: 14,
                          weight: FontWeight.w600,
                          color: a.profit >= 0 ? AppColors.up : AppColors.down)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
