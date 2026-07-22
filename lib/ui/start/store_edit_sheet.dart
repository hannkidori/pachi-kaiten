import 'package:flutter/material.dart';

import '../../models/store.dart';
import '../../repositories/store_repository.dart';
import '../../theme/app_theme.dart';

/// 店舗の追加 / 編集シート。保存すると採番/更新済みの [Store] を返す。
/// 削除した場合は [StoreEditResult.deleted] を返す。
Future<StoreEditResult?> showStoreEditSheet(
  BuildContext context, {
  required StoreRepository repo,
  Store? initial,
}) {
  return showModalBottomSheet<StoreEditResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StoreEditSheet(repo: repo, initial: initial),
  );
}

class StoreEditResult {
  final Store? store; // 保存された店舗(削除時 null)
  final bool deleted;
  const StoreEditResult.saved(this.store) : deleted = false;
  const StoreEditResult.removed()
      : store = null,
        deleted = true;
}

const _rateOptions = <(double, String)>[
  (4.0, '等価'),
  (3.57, '3.57'),
  (3.3, '3.3'),
  (3.03, '3.03'),
];
const _ballOptions = <(double, String)>[
  (4.0, '4円'),
  (1.0, '1円'),
];

class _StoreEditSheet extends StatefulWidget {
  final StoreRepository repo;
  final Store? initial;
  const _StoreEditSheet({required this.repo, this.initial});

  @override
  State<_StoreEditSheet> createState() => _StoreEditSheetState();
}

class _StoreEditSheetState extends State<_StoreEditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late double _rate = widget.initial?.exchangeRate ?? 3.57;
  late double _ball = widget.initial?.ballPrice ?? 4.0;
  bool _saving = false;

  bool get _isEdit => widget.initial?.id != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    final base = (widget.initial ?? const Store(name: '', exchangeRate: 3.57))
        .copyWith(name: name, exchangeRate: _rate, ballPrice: _ball);
    final Store saved;
    if (_isEdit) {
      await widget.repo.update(base);
      saved = base;
    } else {
      saved = await widget.repo.insert(base);
    }
    if (mounted) Navigator.of(context).pop(StoreEditResult.saved(saved));
  }

  Future<void> _delete() async {
    if (widget.initial?.id == null) return;
    await widget.repo.delete(widget.initial!.id!);
    if (mounted) Navigator.of(context).pop(const StoreEditResult.removed());
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_isEdit ? '店舗を編集' : '店舗を追加',
                    style:
                        AppTheme.sans(size: 14, weight: FontWeight.w700)),
                const Spacer(),
                if (_isEdit)
                  GestureDetector(
                    onTap: _delete,
                    child: Text('削除',
                        style:
                            AppTheme.sans(size: 12, color: AppColors.down)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              style: AppTheme.sans(size: 15),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                hintText: '店舗名',
                hintStyle: AppTheme.sans(size: 15, color: AppColors.mutedDark),
                filled: true,
                fillColor: AppColors.surfaceAlt,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0x596BCBDD)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('換金率',
                style: AppTheme.sans(size: 11, color: AppColors.muted)),
            const SizedBox(height: 8),
            _choiceRow(
              _rateOptions,
              _rate,
              (v) => setState(() => _rate = v),
            ),
            const SizedBox(height: 16),
            Text('貸玉',
                style: AppTheme.sans(size: 11, color: AppColors.muted)),
            const SizedBox(height: 8),
            _choiceRow(
              _ballOptions,
              _ball,
              (v) => setState(() => _ball = v),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _save,
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentDeep,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text('保存',
                    style: AppTheme.sans(
                        size: 16,
                        weight: FontWeight.w700,
                        color: AppColors.accentInk)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceRow(
    List<(double, String)> options,
    double selected,
    ValueChanged<double> onPick,
  ) {
    return Wrap(
      spacing: 8,
      children: [
        for (final (value, label) in options)
          GestureDetector(
            onTap: () => onPick(value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: value == selected
                    ? const Color(0x296BCBDD)
                    : AppColors.surfaceAlt,
                border: Border.all(
                    color: value == selected
                        ? const Color(0x666BCBDD)
                        : AppColors.border),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(label,
                  style: AppTheme.mono(
                      size: 13,
                      weight: FontWeight.w600,
                      color: value == selected
                          ? AppColors.accentSoft
                          : AppColors.textStrong)),
            ),
          ),
      ],
    );
  }
}
