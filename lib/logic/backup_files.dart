import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_service.dart';

/// 機種マスタ同期用の HTTP 取得(MachineSync.syncFromRemote に渡す Fetcher)。
Future<String> httpFetch(String url) async {
  final res = await http
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 8));
  if (res.statusCode != 200) {
    throw HttpException('HTTP ${res.statusCode}');
  }
  return res.body;
}

enum ImportResult { success, cancelled }

/// ファイル名に使える安全なタイムスタンプ。
String _stamp(DateTime t) =>
    '${t.year}${_pad(t.month)}${_pad(t.day)}_${_pad(t.hour)}${_pad(t.minute)}${_pad(t.second)}';
String _pad(int v) => v.toString().padLeft(2, '0');

/// 全データを JSON にして共有シートで書き出す。
Future<void> exportAndShare(BackupService backup) async {
  final now = DateTime.now();
  final data = await backup.exportData(exportedAt: now.toIso8601String());
  final dir = await getTemporaryDirectory();
  final file =
      File(p.join(dir.path, 'pachi_kaiten_backup_${_stamp(now)}.json'));
  await file.writeAsString(jsonEncode(data));
  // share_plus 13: 静的 Share は廃止。SharePlus.instance.share(ShareParams)。
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], subject: 'パチ回転計 バックアップ'),
  );
}

/// JSON ファイルを選んでインポートする。上書き前に現 DB を
/// アプリ内 backups/ に自動バックアップしてから取り込む。
Future<ImportResult> pickAndImport(BackupService backup) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  final path = picked?.files.singleOrNull?.path;
  if (path == null) return ImportResult.cancelled;

  final text = await File(path).readAsString();
  final incoming = (jsonDecode(text) as Map).cast<String, Object?>();

  final now = DateTime.now();
  await backup.importWithBackup(
    incoming,
    backupStamp: now.toIso8601String(),
    writeBackup: (snapshot) async {
      final docs = await getApplicationDocumentsDirectory();
      final backupsDir = Directory(p.join(docs.path, 'backups'));
      await backupsDir.create(recursive: true);
      final f = File(p.join(
          backupsDir.path, 'auto_before_import_${_stamp(now)}.json'));
      await f.writeAsString(jsonEncode(snapshot));
    },
  );
  return ImportResult.success;
}
