import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/machine.dart';
import '../repositories/machine_repository.dart';
import '../repositories/settings_repository.dart';

/// リモート取得の結果(UI には出さず、ログ/デバッグ用)。
enum SyncOutcome {
  applied, // 新しい版を UPSERT した
  upToDate, // 同じか古い版だったので何もしない
  failed, // 取得/パース失敗(既存マスタは無傷)
}

class SyncResult {
  final SyncOutcome outcome;
  final String? version;
  final int count;
  final Object? error;
  const SyncResult(this.outcome, {this.version, this.count = 0, this.error});
}

/// テキスト取得関数(テストで差し替え可能)。
typedef Fetcher = Future<String> Function(String url);

/// 機種マスタの取り込み。
///
/// 設計方針(最重要): 配信側のミスでアプリ側のマスタが壊れないこと。
/// - リモート JSON は **完全にパース・検証してから** DB に触れる(全件バリデーション
///   に成功した場合のみ UPSERT)。途中で失敗したら DB は一切変更しない。
/// - version がローカルと同じか古ければ UPSERT しない。
/// - あらゆる例外は握り潰し、[SyncOutcome.failed] を返す(UI には見せない)。
class MachineSync {
  final MachineRepository repo;
  final SettingsRepository? settings;
  MachineSync(this.repo, {this.settings});

  static const _assetPath = 'assets/machines.json';

  /// machines.json 文字列を厳格にパースして [Machine] のリストと version を返す。
  /// 必須フィールド(id/name/probability/borders."4.0")が欠けていれば例外。
  static ({String version, List<Machine> machines}) parse(String jsonStr) {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map) {
      throw const FormatException('ルートがオブジェクトではありません');
    }
    final version = decoded['version'];
    if (version is! String || version.isEmpty) {
      throw const FormatException('version がありません');
    }
    final rawList = decoded['machines'];
    if (rawList is! List) {
      throw const FormatException('machines が配列ではありません');
    }
    final machines = <Machine>[];
    for (final item in rawList) {
      if (item is! Map) {
        throw const FormatException('machines の要素がオブジェクトではありません');
      }
      // Machine.fromJson は必須欠落で例外を投げる(id/name/probability/4.0)。
      machines.add(Machine.fromJson(item.cast<String, Object?>(),
          version: version));
    }
    if (machines.isEmpty) {
      throw const FormatException('machines が空です');
    }
    return (version: version, machines: machines);
  }

  /// マスタが空なら(初回起動)アセットからシードし、version を記録する。
  Future<void> seedIfEmpty() async {
    if (await repo.count() > 0) return;
    final jsonStr = await rootBundle.loadString(_assetPath);
    final parsed = parse(jsonStr);
    await repo.upsertAll(parsed.machines);
    await settings?.setMachinesVersion(parsed.version);
  }

  /// リモート(GitHub raw など)から取得して差分適用する。
  /// 失敗は握り潰し、既存マスタは無傷のまま [SyncOutcome.failed] を返す。
  Future<SyncResult> syncFromRemote(String url, {required Fetcher fetch}) async {
    try {
      final body = await fetch(url);

      // 1) 先に完全パース・検証(ここで失敗しても DB は無傷)。
      final parsed = parse(body);

      // 2) version 比較。同じ/古ければ何もしない。
      final local = await settings?.machinesVersion();
      if (local != null && parsed.version.compareTo(local) <= 0) {
        return SyncResult(SyncOutcome.upToDate, version: parsed.version);
      }

      // 3) 検証済みのリストだけを UPSERT。
      await repo.upsertAll(parsed.machines);
      await settings?.setMachinesVersion(parsed.version);
      return SyncResult(SyncOutcome.applied,
          version: parsed.version, count: parsed.machines.length);
    } catch (e) {
      // 取得失敗・パース失敗・DB例外いずれもユーザーには見せない。
      return SyncResult(SyncOutcome.failed, error: e);
    }
  }
}
