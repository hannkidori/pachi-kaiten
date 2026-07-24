import 'package:flutter/material.dart';

import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../widgets/counter_field.dart';
import '../widgets/numpad.dart';
import 'machine_sheets.dart';
import 'start_screen.dart';

/// クイック計測の打ち始め入力。機種選択を経由せず、打ち始めカウンタだけ入れて
/// 即開始する(machine_id = null)。ホームの主役「計測スタート」から遷移する。
class QuickStartScreen extends StatefulWidget {
  final AppServices services;
  const QuickStartScreen({super.key, required this.services});

  @override
  State<QuickStartScreen> createState() => _QuickStartScreenState();
}

class _QuickStartScreenState extends State<QuickStartScreen> {
  AppServices get s => widget.services;

  String _counter = '';
  int _addUnit = 1000;
  double _ballPrice = 4.0;
  bool _loading = true;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final addUnit = await s.settings.addUnitDefault();
    final ballPrice = await s.settings.ballPrice();
    if (!mounted) return;
    setState(() {
      _addUnit = addUnit;
      _ballPrice = ballPrice;
      _loading = false;
    });
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    final counter = int.tryParse(_counter) ?? 0;
    final session = await s.sessionService.start(
      machine: null, // クイック計測
      ballPrice: _ballPrice,
      startCounter: counter,
      addUnit: _addUnit,
    );
    if (!mounted) return;
    Navigator.of(context).pop(StartResult(session, null));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _topBar(),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('機種を選ばず計測します',
                            style: AppTheme.sans(
                                size: 12, color: AppColors.muted)),
                        const SizedBox(height: 4),
                        Text('ボーダー比較・期待値は出ません',
                            style: AppTheme.sans(
                                size: 10.5, color: AppColors.mutedDark)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  _counterSection(),
                  _startButton(),
                ],
              ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: AppColors.textDim),
          ),
          Text('計測を始める',
              style: AppTheme.sans(size: 16, weight: FontWeight.w700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(ballLabel(_ballPrice),
                style: AppTheme.mono(size: 11, color: AppColors.textDim)),
          ),
        ],
      ),
    );
  }

  Widget _counterSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('台のデータ表示機の回転数をそのまま入力',
              style: AppTheme.sans(size: 9.5, color: AppColors.muted)),
          const SizedBox(height: 6),
          CounterField(
            typed: _counter,
            prevCounter: null, // 打ち始め=前回「—」
            placeholder: '打ち始めの数字',
          ),
          const SizedBox(height: 8),
          Numpad(
            keyHeight: 44,
            onKey: (k) => setState(() => _counter = applyKey(_counter, k)),
          ),
        ],
      ),
    );
  }

  Widget _startButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Opacity(
        opacity: _starting ? 0.5 : 1,
        child: GestureDetector(
          onTap: _starting ? null : _start,
          child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('計測スタート',
                style: AppTheme.sans(
                    size: 16,
                    weight: FontWeight.w700,
                    color: AppColors.accentInk)),
          ),
        ),
      ),
    );
  }
}
