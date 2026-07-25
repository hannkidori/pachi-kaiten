import 'package:flutter/material.dart';

import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../widgets/counter_field.dart';
import '../widgets/glow_background.dart';
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
      body: GlowBackground.start(
        child: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _topBar(),
                  // 本文エリア中央にモードカード。
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 26),
                      child: Center(child: _modeCard()),
                    ),
                  ),
                  _counterSection(),
                  _startButton(),
                ],
              ),
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

  /// モードカード(クイック計測の説明)。制限を「警告」でなく事実の並記で見せる。
  Widget _modeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x4756D9F0)), // rgba(86,217,240,0.28)
        gradient: const RadialGradient(
          center: Alignment(0, -1), // 50% 0%
          radius: 1.3, // 130%
          colors: [Color(0x1756D9F0), Color(0x0056D9F0)], // 0.09 → 0
          stops: [0, 0.72],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 見出し行(ドット + クイック計測)。
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xE656D9F0), // 0.9
                        blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Text('クイック計測',
                  style: AppTheme.sans(
                      size: 15,
                      weight: FontWeight.w700,
                      color: const Color(0xFFF1ECE3))),
            ],
          ),
          const SizedBox(height: 12),
          Text('機種を選ばずに、回転率だけを計測します。',
              style: AppTheme.sans(
                  size: 12, height: 1.6, color: const Color(0xFF96A1AB))),
          const SizedBox(height: 12),
          Container(height: 1, color: const Color(0x14FFFFFF)),
          const SizedBox(height: 12),
          // できること / できないこと(✓ のみアクセント、— はニュートラル)。
          _cardBullet('✓', AppColors.accent, '回転率・総回転・グラフ'),
          const SizedBox(height: 6),
          _cardBullet('—', AppColors.mutedDark, 'ボーダー比較・期待値は出ません'),
        ],
      ),
    );
  }

  Widget _cardBullet(String mark, Color markColor, String label) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(mark,
            style: AppTheme.mono(
                size: 12, weight: FontWeight.w600, color: markColor)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: AppTheme.sans(size: 11.5, color: AppColors.mutedDark)),
        ),
      ],
    );
  }

  Widget _counterSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 入力説明行(i 円アイコン + 説明)。
          Row(
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x7356D9F0)), // 0.45
                ),
                child: Text('i',
                    style: AppTheme.sans(
                        size: 11,
                        weight: FontWeight.w700,
                        color: AppColors.accent)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('台のデータ表示機の回転数をそのまま入力',
                    style: AppTheme.sans(
                        size: 12,
                        weight: FontWeight.w500,
                        color: AppColors.textDim)),
              ),
            ],
          ),
          const SizedBox(height: 9),
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
