import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_service.dart';

/// ファイル名に使える安全なタイムスタンプ。
String _stamp(DateTime t) =>
    '${t.year}${_pad(t.month)}${_pad(t.day)}_${_pad(t.hour)}${_pad(t.minute)}${_pad(t.second)}';
String _pad(int v) => v.toString().padLeft(2, '0');

/// 登録機種 + 足跡ログを JSON にして共有シートで書き出す(唯一残す補助機能)。
Future<void> exportAndShare(BackupService backup) async {
  final now = DateTime.now();
  final data = await backup.exportData(exportedAt: now.toIso8601String());
  final dir = await getTemporaryDirectory();
  final file =
      File(p.join(dir.path, 'pachi_kaiten_export_${_stamp(now)}.json'));
  await file.writeAsString(jsonEncode(data));
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], subject: 'パチ回転計 エクスポート'),
  );
}
