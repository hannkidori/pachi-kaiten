# パチ回転計

パチンコの回転率をホールで打ちながら計測し、そのまま収支記録に落とし込む Flutter アプリ
(Android / iOS)。完全無料・広告なし・オフライン完結。機種マスタ内蔵(機種選択でボーダー
自動セット)と、回転率 → 収支の一気通貫が特長。ダークテーマのみ、数字は等幅。

## 主な機能

- **計測**: カスタムテンキーで決定タップごとにカウンタを記録。差分から回転率を算出。
  現金・持ち玉の両区間を計測に算入(250玉=1000円 / 1円貸しは 1000玉=1000円)。
- **実質ボーダー自動計算**: 機種マスタ + 店舗の換金率・貸玉から実質ボーダー B を提示。
  ボーダー比(上=緑/下=赤)と期待値をリアルタイム表示。
- **大当り復帰・台移動・終了サマリー**: 大当りで基準を付け替え、台移動は回収額→機種選択→
  新セッションへ途切れなく接続。終了で回収額を入れて収支サマリー。
- **履歴・収支**: 月別 → 日別グルーピング、機種別集計(回収率主指標)、勝率(±0円除外)。
- **バックアップ**: JSON でエクスポート/インポート(インポート前に自動バックアップ)。
- **機種マスタ同期**: 起動時に GitHub から `data/machines.json` を取得し、新しければ更新。
  取得・パース失敗時は既存マスタを保護(配信ミスでアプリ側が壊れない設計)。

## 構成

- `lib/logic/` — 純粋な計算ロジック(回転率・期待値・rebase・持ち玉換算・異常値判定)。
  `flutter test` でユニットテスト済み。
- `lib/models/` `lib/db/` `lib/repositories/` — sqflite の永続化層。
- `lib/state/` `lib/ui/` — 計測画面・スタート・履歴・設定などの UI。
- `assets/machines.json` — 同梱の初期シード。`data/machines.json` — 配信元(GitHub raw)。
- `tool/build_scraper.py` — 機種マスタ生成の開発者用ツール(アプリには含めない)。

## 開発

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## 機種マスタ配信

アプリは起動時に以下を取得して版が新しければ取り込む:

```
https://raw.githubusercontent.com/hannkidori/pachi-kaiten/main/data/machines.json
```

更新は開発者ローカルで `tool/build_scraper.py`(取得と変換を分離、出力前検証、差分確認つき)
を実行して `data/machines.json` を生成し、コミットする。詳細は `tool/README.md`。
