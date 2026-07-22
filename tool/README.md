# build_scraper.py — machines.json ビルダー(開発者用)

パチンコ機種の「機種名 / 大当り確率 / 各換金率ボーダー」を収集して、アプリ同梱の
`assets/machines.json` を生成する開発者ローカル専用ツール。**アプリには含めない。**
実行頻度は月1回程度を想定。

## セットアップ

```
pip install -r tool/requirements.txt
```

`build_scraper.py` の `CONTACT` を自分の連絡先(メール等)に書き換える。
User-Agent に載せて相手サーバーに正直に名乗るため。

## 使い方

取得(fetch)と変換(parse)を分けている。パーサ調整のたびに再取得しない。

```
# 1. 取得元 URL を tool/sources.txt に記載(1 行 1 URL)
# 2. 生HTMLをキャッシュに保存(直列・リクエスト間 2.5s・正直な UA)
python tool/build_scraper.py fetch

# 3. キャッシュから machines.json を生成(検証 → 差分表示 → 確認)
python tool/build_scraper.py parse

# 差分だけ確認(生成しない)
python tool/build_scraper.py diff

# 確認プロンプトをスキップ
python tool/build_scraper.py parse --yes
```

## 安全策

- **相手サーバーへの配慮**: リクエストは完全に直列(並列禁止)、間隔は最低 2.0 秒を
  強制、User-Agent に用途と連絡先を明記。
- **取得と変換の分離**: `fetch` が唯一ネットワークに触れる段階。`parse` は
  `tool/cache/` の生HTMLだけを読む。サイト構造変更への追従はパーサ修正 → `parse`
  再実行のみで、再取得は不要。
- **出力前検証**: `machine_sync.dart` と同じ必須基準(id / name / probability /
  borders["4.0"])で全件チェック。1 件でも欠落があれば **出力せずエラー終了**。
  配信側でミスる前にローカルで弾く。
- **差分確認**: 既存 `machines.json` との追加/変更/削除を表示してから書き込み確認。
  削除が既存の 30% 以上なら警告(取得漏れによる意図しない大量削除を防ぐ)。

## サイト構造変更時

`build_scraper.py` の `parse_page()` 内(`==== サイト構造依存 ====` マーカー)の
CSS セレクタだけを対象サイトの実際のマークアップに合わせて調整する。他は触らない。
調整後は `python tool/build_scraper.py parse` を再実行するだけ(再取得不要)。
