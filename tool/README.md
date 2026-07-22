# build_scraper.py — machines.json ビルダー(開発者用)

パチンコ機種の「機種名 / 大当り確率 / 各換金率ボーダー」を収集して、アプリ同梱の
`assets/machines.json` を生成する開発者ローカル専用ツール。**アプリには含めない。**
実行頻度は月1回程度を想定。

取得元は **パチセブン**(pachiseven.jp)。`sources.txt` にはパチンコ機種一覧
(新台情報・ページング)の URL を記載し、fetch がそこから個別機種ページ
(`/machines/{id}`)を辿って取得する。ボーダーは各機種ページの
「4円交換/3.57円交換/3.3円交換/3.0円交換」列(遊技時間別の先頭=4h 行)から取る。

## セットアップ

```
pip install -r tool/requirements.txt
```

User-Agent に正直な連絡先を載せるため、環境変数 `SCRAPER_CONTACT` にメールを設定する
(リポジトリにメールをコミットしないよう、既定はプレースホルダ)。

```
export SCRAPER_CONTACT="you@example.com"   # PowerShell: $env:SCRAPER_CONTACT="..."
```

## 使い方

取得(fetch)と変換(parse)を分けている。パーサ調整のたびに再取得しない。

```
# 1. 一覧ページ(ページング)から個別機種を直列取得しキャッシュ
#    (リクエスト間 2.5s・正直な UA・既取得はスキップ)
python tool/build_scraper.py fetch            # 全件
python tool/build_scraper.py fetch --limit 8  # 動作確認用に機種数を制限

# 2. キャッシュ → machines.json(検証 → 差分 → 確認)。
#    未リリース(ボーダー未掲載)や特殊確率(一種二種混合等)は自動除外。
#    出力は data/machines.json と assets/machines.json の両方(同一内容)。
python tool/build_scraper.py parse

python tool/build_scraper.py diff        # 差分だけ(生成しない)
python tool/build_scraper.py parse --yes # 確認プロンプトをスキップ
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

`build_scraper.py` の `parse_page()` 内(`==== サイト構造依存 ====` マーカー)を
パチセブンの実際のマークアップに合わせて調整する(機種名=og:title、確率=スペック表
「大当り確率」セル、ボーダー=「4円交換…」列)。他は触らない。調整後は
`python tool/build_scraper.py parse` を再実行するだけ(再取得不要)。

## 注意

- パチセブンの利用規約はコンテンツの無断複製・再配布を制限している。取得データを
  公開リポジトリで再配布する場合はこの点を各自で判断すること。
- `version` は生成日(date.today())。同日に内容を変えても version は同じになるため、
  既存インストールへリモート同期で反映させたい場合は日をまたぐか version を手動で上げる。
