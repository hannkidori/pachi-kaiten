#!/usr/bin/env python3
"""machines.json ビルダー(開発者ローカル専用・アプリには含めない)。

パチンコ機種の「機種名 / 大当り確率 / 各換金率ボーダー」を収集し、
アプリ同梱の assets/machines.json を生成する。実行は開発者ローカルで
月1回程度を想定。

設計方針:
  1. 相手サーバーへの配慮 — リクエスト間に必ず sleep(既定2.5秒、最低2.0秒)、
     User-Agent を正直に名乗る、並列リクエスト禁止(完全に直列)。
  2. 取得と変換の分離 — `fetch` で生HTMLを tool/cache/ に保存し、`parse` は
     キャッシュのみから machines.json を生成する。パーサ調整のたびに再取得しない。
  3. 出力前検証 — machine_sync.dart と同じ必須フィールド基準で検証し、1件でも
     欠落があれば出力せずエラー終了(配信前にローカルで弾く)。
  4. diff 確認 — 既存 machines.json との差分(追加/変更/削除)を表示し、
     書き込み前に確認を取る。意図しない大量削除を防ぐ。

使い方:
  python build_scraper.py fetch          # sources.txt の URL を直列取得しキャッシュ
  python build_scraper.py parse          # キャッシュ → machines.json(検証+diff+確認)
  python build_scraper.py parse --yes    # 確認をスキップ(CI 等)
  python build_scraper.py diff           # 生成せず差分だけ表示

依存: requests, beautifulsoup4  (pip install -r tool/requirements.txt)
"""
from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import re
import sys
import time
from pathlib import Path
from typing import Any

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:  # parse だけなら requests は不要にしたいが、明示エラーにする
    requests = None  # type: ignore
    BeautifulSoup = None  # type: ignore

# ---------------------------------------------------------------------------
# 設定
# ---------------------------------------------------------------------------
TOOL_DIR = Path(__file__).resolve().parent
CACHE_DIR = TOOL_DIR / "cache"
SOURCES_FILE = TOOL_DIR / "sources.txt"
OUTPUT_FILE = TOOL_DIR.parent / "assets" / "machines.json"

# 正直な User-Agent。CONTACT は自分の連絡先に置き換える。
CONTACT = "your-email@example.com"  # ← 連絡先を入れる
USER_AGENT = f"pachi-kaiten-scraper/1.0 (personal machine-data collector; +{CONTACT})"

# リクエスト間の待機。相手サーバーへの配慮として最低 2.0 秒を強制する。
REQUEST_DELAY_SEC = 2.5
_MIN_DELAY_SEC = 2.0

# 換金率キー(machines.json / machine_sync.dart と一致させる)。
RATE_KEYS = ["4.0", "3.57", "3.3", "3.03"]

# 大量削除の警告閾値(既存に対する削除割合)。
MASS_DELETE_RATIO = 0.30


# ---------------------------------------------------------------------------
# fetch 段階(唯一ネットワークに触れる。直列 + sleep + 正直な UA)
# ---------------------------------------------------------------------------
def _slug(url: str) -> str:
    h = hashlib.sha1(url.encode("utf-8")).hexdigest()[:10]
    tail = re.sub(r"[^a-zA-Z0-9]+", "-", url.split("//", 1)[-1])[:60].strip("-")
    return f"{tail}-{h}.html"


def read_sources() -> list[str]:
    if not SOURCES_FILE.exists():
        sys.exit(
            f"[fetch] {SOURCES_FILE} がありません。取得したい一覧/機種ページの URL を\n"
            "1 行に 1 つ書いてください(# 始まりはコメント)。"
        )
    urls = []
    for line in SOURCES_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            urls.append(line)
    return urls


def cmd_fetch(_args: argparse.Namespace) -> None:
    if requests is None:
        sys.exit("requests が必要です: pip install -r tool/requirements.txt")
    urls = read_sources()
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})
    delay = max(REQUEST_DELAY_SEC, _MIN_DELAY_SEC)

    print(f"[fetch] {len(urls)} ページを直列取得(間隔 {delay}s, UA={USER_AGENT})")
    for i, url in enumerate(urls, 1):
        dest = CACHE_DIR / _slug(url)
        print(f"  ({i}/{len(urls)}) {url}")
        try:
            resp = session.get(url, timeout=20)
            resp.raise_for_status()
            dest.write_text(resp.text, encoding="utf-8")
            print(f"      -> {dest.name} ({len(resp.text)} bytes)")
        except Exception as e:  # 1 ページ失敗しても全体は続行
            print(f"      !! 取得失敗: {e}")
        # 並列にせず、必ず待つ(最後の 1 件の後は待たない)。
        if i < len(urls):
            time.sleep(delay)
    print("[fetch] 完了。次に `parse` を実行してください。")


# ---------------------------------------------------------------------------
# parse 段階(キャッシュのみ。ネットワークに触れない)
# ---------------------------------------------------------------------------
def _num(text: str | None) -> float | None:
    """'1/319.6' や '319.6回' などから数値を取り出す。"""
    if text is None:
        return None
    m = re.search(r"(\d+(?:\.\d+)?)", text.replace(",", ""))
    return float(m.group(1)) if m else None


def parse_page(html: str) -> list[dict[str, Any]]:
    """1 ページ分の HTML から機種 dict のリストを抽出する。

    ==== サイト構造依存(サイト変更時はここだけ直す)====
    実際の配信元(パチセブン等)の DOM 構造に合わせてセレクタを調整する。
    下記はテンプレート。data-* 属性を持つ想定のダミー実装なので、対象サイトの
    実際のマークアップに合わせて書き換えること。
    """
    if BeautifulSoup is None:
        sys.exit("beautifulsoup4 が必要です: pip install -r tool/requirements.txt")
    soup = BeautifulSoup(html, "html.parser")
    machines: list[dict[str, Any]] = []

    # --- 調整ポイント(例) ---
    # 各機種カードが <div class="machine" data-id="umi5sp"> ... の想定。
    for card in soup.select(".machine"):
        mid = card.get("data-id") or card.get("id")
        name = _text(card.select_one(".machine-name"))
        prob = _num(_text(card.select_one(".machine-prob")))
        mtype = _text(card.select_one(".machine-type"))

        borders: dict[str, float] = {}
        for key in RATE_KEYS:
            # 例: <span class="border" data-rate="4.0">16.5</span>
            el = card.select_one(f'.border[data-rate="{key}"]')
            val = _num(_text(el))
            if val is not None:
                borders[key] = val

        machines.append(
            {
                "id": mid,
                "name": name,
                "probability": prob,
                "borders": borders,
                "type": mtype,
            }
        )
    return machines


def _text(el: Any) -> str | None:
    if el is None:
        return None
    t = el.get_text(strip=True)
    return t or None


def parse_all_cache() -> list[dict[str, Any]]:
    if not CACHE_DIR.exists():
        sys.exit(f"[parse] キャッシュがありません({CACHE_DIR})。先に `fetch` を実行。")
    files = sorted(CACHE_DIR.glob("*.html"))
    if not files:
        sys.exit(f"[parse] {CACHE_DIR} に *.html がありません。先に `fetch` を実行。")

    by_id: dict[str, dict[str, Any]] = {}
    for f in files:
        html = f.read_text(encoding="utf-8")
        for m in parse_page(html):
            mid = m.get("id")
            if mid:
                by_id[mid] = m  # 後勝ちでマージ(重複ページ対策)
    return normalize(list(by_id.values()))


def normalize(machines: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """型を整え、id 順に安定ソートする。"""
    out = []
    for m in machines:
        borders = {
            k: float(v)
            for k, v in (m.get("borders") or {}).items()
            if isinstance(v, (int, float))
        }
        out.append(
            {
                "id": (m.get("id") or "").strip(),
                "name": (m.get("name") or "").strip(),
                "probability": m.get("probability"),
                "borders": borders,
                "type": (m.get("type") or None),
            }
        )
    out.sort(key=lambda x: x["id"])
    return out


# ---------------------------------------------------------------------------
# 検証(machine_sync.dart と同じ必須基準)
# ---------------------------------------------------------------------------
def validate(machines: list[dict[str, Any]]) -> list[str]:
    """必須フィールド欠落を洗い出す。返り値が空でなければ出力してはいけない。

    machine_sync.dart の parse と同じ基準:
      id(非空文字列) / name(非空文字列) / probability(数値) / borders["4.0"](数値)
    """
    errors: list[str] = []
    if not machines:
        errors.append("機種が 0 件です")
    seen: set[str] = set()
    for i, m in enumerate(machines):
        label = m.get("id") or m.get("name") or f"#{i}"
        mid = m.get("id")
        if not isinstance(mid, str) or not mid:
            errors.append(f"[{label}] id が空")
        elif mid in seen:
            errors.append(f"[{label}] id が重複")
        else:
            seen.add(mid)
        if not isinstance(m.get("name"), str) or not m.get("name"):
            errors.append(f"[{label}] name が空")
        if not isinstance(m.get("probability"), (int, float)):
            errors.append(f"[{label}] probability が数値でない")
        b40 = (m.get("borders") or {}).get("4.0")
        if not isinstance(b40, (int, float)):
            errors.append(f'[{label}] borders["4.0"](等価ボーダー)が無い')
    return errors


# ---------------------------------------------------------------------------
# diff(既存 machines.json との差分)
# ---------------------------------------------------------------------------
def load_existing() -> dict[str, dict[str, Any]]:
    if not OUTPUT_FILE.exists():
        return {}
    data = json.loads(OUTPUT_FILE.read_text(encoding="utf-8"))
    return {m["id"]: m for m in data.get("machines", []) if m.get("id")}


def _machine_changed(a: dict[str, Any], b: dict[str, Any]) -> bool:
    keys = ("name", "probability", "type", "borders")
    return any(a.get(k) != b.get(k) for k in keys)


def compute_diff(
    old: dict[str, dict[str, Any]], new: list[dict[str, Any]]
) -> tuple[list[str], list[str], list[str]]:
    new_by_id = {m["id"]: m for m in new}
    added = [new_by_id[i]["name"] for i in new_by_id if i not in old]
    deleted = [old[i].get("name", i) for i in old if i not in new_by_id]
    changed = [
        new_by_id[i]["name"]
        for i in new_by_id
        if i in old and _machine_changed(old[i], new_by_id[i])
    ]
    return sorted(added), sorted(changed), sorted(deleted)


def print_diff(old: dict, new: list) -> tuple[list[str], list[str], list[str]]:
    added, changed, deleted = compute_diff(old, new)
    print(f"[diff] 既存 {len(old)} 件 → 生成 {len(new)} 件")
    print(f"  追加 {len(added)} / 変更 {len(changed)} / 削除 {len(deleted)}")
    for name in added:
        print(f"  + {name}")
    for name in changed:
        print(f"  ~ {name}")
    for name in deleted:
        print(f"  - {name}")
    return added, changed, deleted


# ---------------------------------------------------------------------------
# 書き込み
# ---------------------------------------------------------------------------
def build_document(machines: list[dict[str, Any]]) -> dict[str, Any]:
    version = _dt.date.today().isoformat()
    return {"version": version, "machines": machines}


def write_output(doc: dict[str, Any]) -> None:
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(
        json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"[write] {OUTPUT_FILE} を更新(version={doc['version']}, "
          f"{len(doc['machines'])} 件)")


def cmd_parse(args: argparse.Namespace) -> None:
    machines = parse_all_cache()

    # 出力前検証(1 件でも欠落があれば出力しない)。
    errors = validate(machines)
    if errors:
        print("[検証NG] 必須フィールド欠落のため出力しません:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        sys.exit(1)
    print(f"[検証OK] {len(machines)} 件すべて必須フィールドを満たしています。")

    # diff 表示。
    old = load_existing()
    added, changed, deleted = print_diff(old, machines)

    # 大量削除の警告。
    if old and len(deleted) >= max(1, int(len(old) * MASS_DELETE_RATIO)):
        print(
            f"[警告] 削除が {len(deleted)} 件(既存の "
            f"{len(deleted) / len(old) * 100:.0f}%)。取得漏れの可能性があります。"
        )

    if args.diff_only:
        return

    # 書き込み確認。
    if not args.yes:
        ans = input("この内容で machines.json を書き込みますか? [y/N] ").strip().lower()
        if ans not in ("y", "yes"):
            print("[中止] 書き込みませんでした。")
            return

    write_output(build_document(machines))


def cmd_diff(args: argparse.Namespace) -> None:
    args.diff_only = True
    args.yes = False
    cmd_parse(args)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main() -> None:
    parser = argparse.ArgumentParser(description="machines.json ビルダー(開発者用)")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("fetch", help="sources.txt の URL を直列取得しキャッシュ")

    p_parse = sub.add_parser("parse", help="キャッシュ → machines.json")
    p_parse.add_argument("--yes", action="store_true", help="書き込み確認をスキップ")
    p_parse.add_argument("--diff-only", action="store_true", help="生成せず差分のみ")

    sub.add_parser("diff", help="生成せず既存との差分のみ表示")

    args = parser.parse_args()
    if args.cmd == "fetch":
        cmd_fetch(args)
    elif args.cmd == "parse":
        cmd_parse(args)
    elif args.cmd == "diff":
        cmd_diff(args)


if __name__ == "__main__":
    main()
