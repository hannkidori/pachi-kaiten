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
import os
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
# 配信元(data/)を主とし、バンドル版(assets/)へも同じ内容を書き出す。
OUTPUT_FILE = TOOL_DIR.parent / "data" / "machines.json"
ASSET_FILE = TOOL_DIR.parent / "assets" / "machines.json"

# 正直な User-Agent。連絡先は環境変数 SCRAPER_CONTACT で渡す(リポジトリに
# メールアドレスをコミットしないため、既定はプレースホルダ)。
CONTACT = os.environ.get("SCRAPER_CONTACT", "your-email@example.com")
USER_AGENT = f"pachi-kaiten-scraper/1.0 (personal machine-data collector; +{CONTACT})"

# 取得元(パチセブン)。個別機種は /machines/{数値ID}。
BASE = "https://pachiseven.jp"
DETAIL_RE = re.compile(r"/machines/(\d+)")

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


def cmd_fetch(args: argparse.Namespace) -> None:
    if requests is None:
        sys.exit("requests が必要です: pip install -r tool/requirements.txt")
    list_urls = read_sources()
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})
    delay = max(REQUEST_DELAY_SEC, _MIN_DELAY_SEC)

    def get(url: str):
        resp = session.get(url, timeout=25)
        resp.raise_for_status()
        return resp.text

    # 1) 一覧ページから個別機種 ID を収集(直列 + sleep)。
    print(f"[fetch] 一覧 {len(list_urls)} ページから機種IDを収集"
          f"(間隔 {delay}s, UA={USER_AGENT})")
    ids: list[str] = []
    for i, url in enumerate(list_urls, 1):
        print(f"  list ({i}/{len(list_urls)}) {url}")
        try:
            html = get(url)
            found = DETAIL_RE.findall(html)
            for mid in found:
                if mid not in ids:
                    ids.append(mid)
            print(f"      -> {len(set(found))} 機種リンク(累計 {len(ids)})")
        except Exception as e:
            print(f"      !! 取得失敗: {e}")
        if i < len(list_urls):
            time.sleep(delay)

    if args.limit:
        ids = ids[: args.limit]
    print(f"[fetch] 個別機種 {len(ids)} ページを取得(既取得はスキップ)")

    # 2) 各個別ページを取得(machine_{id}.html)。
    to_fetch = [m for m in ids if not (CACHE_DIR / f"machine_{m}.html").exists()]
    print(f"       新規取得 {len(to_fetch)} / スキップ {len(ids) - len(to_fetch)}")
    for j, mid in enumerate(to_fetch, 1):
        url = f"{BASE}/machines/{mid}"
        dest = CACHE_DIR / f"machine_{mid}.html"
        print(f"  ({j}/{len(to_fetch)}) {url}")
        try:
            html = get(url)
            dest.write_text(html, encoding="utf-8")
            print(f"      -> {dest.name} ({len(html)} bytes)")
        except Exception as e:  # 1 ページ失敗しても全体は続行
            print(f"      !! 取得失敗: {e}")
        if j < len(to_fetch):
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


def parse_page(html: str, machine_id: str | None = None) -> list[dict[str, Any]]:
    """パチセブンの個別機種ページ(/machines/{id})1 件から機種 dict を抽出する。

    ==== サイト構造依存(サイト変更時はここだけ直す)====
    - 機種名: <meta property="og:title"> から接尾辞(パチンコ/ボーダー/スペック等)以降を除去。
    - 大当り確率: 「大当り確率」ラベルを含む行の "約1/319.7" から数値。
    - 換金率別ボーダー: ヘッダに「4円交換 / 3.57円交換 / 3.3円交換 / 3.0円交換」を持つ表
      (遊技時間別)の先頭データ行(4h 相当)の値。
    - type: 大当り確率から簡易分類(甘 <100 / ライト <180 / ミドル 以上)。
    """
    if BeautifulSoup is None:
        sys.exit("beautifulsoup4 が必要です: pip install -r tool/requirements.txt")
    soup = BeautifulSoup(html, "html.parser")

    # 機種名
    og = soup.find("meta", property="og:title")
    title = og.get("content", "") if og else ""
    name = re.split(
        r"\s+(パチンコ|パチスロ|スロット|ボーダー|新台|スペック|信頼度|甘デジ)",
        title,
    )[0].strip()

    # 大当り確率(構造差に強い多段フォールバック)
    prob: float | None = None
    prob_re = re.compile(r"1\s*/\s*(\d{2,4}(?:\.\d)?)")
    # (1) スペック表: 「大当り確率」ラベルセル → 隣のセルの 1/xxx
    for cell in soup.find_all(["td", "th"]):
        if cell.get_text(strip=True) in ("大当り確率", "大当たり確率"):
            sib = cell.find_next_sibling(["td", "th"])
            m = prob_re.search(sib.get_text(" ", strip=True)) if sib else None
            if m:
                prob = float(m.group(1))
                break
    # (2) 「通常時 1/xxx」(多モード機の基準確率)
    if prob is None:
        m = re.search(r"通常時\s*" + prob_re.pattern, soup.get_text())
        if m:
            prob = float(m.group(1))
    # (3) 「大当り確率」を含む行(tr)全体から
    if prob is None:
        for el in soup.find_all(string=re.compile(r"大当[りた]*り?確率")):
            tr = el.find_parent("tr")
            if tr:
                m = prob_re.search(tr.get_text(" ", strip=True))
                if m:
                    prob = float(m.group(1))
                    break

    # 換金率別ボーダー
    borders: dict[str, float] = {}
    for t in soup.find_all("table"):
        head = t.find("tr")
        if not head:
            continue
        htxt = head.get_text()
        if "交換" not in htxt or "4円" not in htxt:
            continue
        cols = [c.get_text(" ", strip=True) for c in head.find_all(["th", "td"])]
        idx: dict[str, int] = {}
        for i, c in enumerate(cols):
            if re.search(r"4円", c):
                idx["4.0"] = i
            elif "3.57" in c:
                idx["3.57"] = i
            elif "3.3" in c or "3.30" in c:
                idx["3.3"] = i
            elif "3.0" in c or "3.03" in c:
                idx["3.03"] = i
        if not idx:
            continue
        for tr in t.find_all("tr")[1:]:
            cells = [c.get_text(" ", strip=True) for c in tr.find_all(["th", "td"])]
            if cells and re.match(r"\d+h", cells[0]):
                for k, i in idx.items():
                    if i < len(cells):
                        m = re.search(r"([12]\d\.\d)", cells[i])
                        if m:
                            borders[k] = float(m.group(1))
                break
        if borders:
            break

    mtype: str | None = None
    if prob is not None:
        mtype = "甘" if prob < 100 else ("ライト" if prob < 180 else "ミドル")

    return [
        {
            "id": machine_id,
            "name": name or None,
            "probability": prob,
            "borders": borders,
            "type": mtype,
        }
    ]


def parse_all_cache() -> list[dict[str, Any]]:
    if not CACHE_DIR.exists():
        sys.exit(f"[parse] キャッシュがありません({CACHE_DIR})。先に `fetch` を実行。")
    files = sorted(CACHE_DIR.glob("machine_*.html"))
    if not files:
        sys.exit(f"[parse] {CACHE_DIR} に machine_*.html がありません。先に `fetch` を実行。")

    by_id: dict[str, dict[str, Any]] = {}
    for f in files:
        mid = f.stem.replace("machine_", "")  # パチセブンの数値ID
        html = f.read_text(encoding="utf-8")
        for m in parse_page(html, machine_id=mid):
            if m.get("id"):
                by_id[m["id"]] = m
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
    # 生成日時(秒精度)。同日に作り直しても version が必ず新しくなるので、
    # アプリ側の同梱アセット同期(version 比較)が確実に発火する。
    version = _dt.datetime.now().isoformat(timespec="seconds")
    return {"version": version, "machines": machines}


def write_output(doc: dict[str, Any]) -> None:
    payload = json.dumps(doc, ensure_ascii=False, indent=2) + "\n"
    for path in (OUTPUT_FILE, ASSET_FILE):  # data/ と assets/ を同期
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(payload, encoding="utf-8")
        print(f"[write] {path} を更新(version={doc['version']}, "
              f"{len(doc['machines'])} 件)")


def _has_border(m: dict[str, Any]) -> bool:
    return isinstance((m.get("borders") or {}).get("4.0"), (int, float))


def _is_complete(m: dict[str, Any]) -> bool:
    return (
        bool(m.get("name"))
        and isinstance(m.get("probability"), (int, float))
        and _has_border(m)
    )


def cmd_parse(args: argparse.Namespace) -> None:
    parsed = parse_all_cache()

    # 不完全な機種は「エラー」ではなく除外する(パース失敗との区別: 全滅なら
    # この後の 0 件検証で気づける)。理由を分類してログする。
    machines = [m for m in parsed if _is_complete(m)]
    no_border = [m for m in parsed if not _has_border(m)]
    no_prob = [m for m in parsed
               if _has_border(m) and not isinstance(m.get("probability"), (int, float))]
    if no_border:
        print(f"[skip] ボーダー未掲載(未リリース等)を {len(no_border)} 件除外")
    if no_prob:
        names = [m.get("name") or m.get("id") for m in no_prob]
        print(f"[skip] 確率取得不可(特殊確率/一種二種混合など)を {len(no_prob)} 件除外: "
              f"{names[:6]}{' …' if len(names) > 6 else ''}")

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

    p_fetch = sub.add_parser(
        "fetch", help="一覧(sources.txt)→個別機種ページを直列取得しキャッシュ")
    p_fetch.add_argument("--limit", type=int, default=0,
                         help="取得する機種数の上限(0=無制限)")

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
