#!/usr/bin/env python3
# ============================================================
# build_index.py
# GitHub上の全市区町村ファイルを読み取り、Overpassでbboxを取得して
# index.jsonを一括再構築してGitHubにアップロードする。
#
# 使い方:
#   python3 build_index.py              # 全県
#   python3 build_index.py miyagi       # 宮城だけ
#   python3 build_index.py --dry-run    # アップロードしない
#   python3 build_index.py --from miyagi  # 途中再開
# ============================================================

import argparse
import http.client
import json
import os
import re
import ssl
import sys
import time
import urllib.parse
import urllib.request
import base64

SCRIPTS_DIR   = os.path.dirname(os.path.abspath(__file__))
MAPS_DIR      = os.path.normpath(os.path.join(SCRIPTS_DIR, "..", "maps"))
INDEX_PATH    = os.path.join(MAPS_DIR, "index.json")
OVERPASS_URL  = "https://overpass-api.de/api/interpreter"
GITHUB_OWNER  = "noanoa31500-byte"
GITHUB_REPO   = "maps"
GITHUB_BRANCH = "main"
GITHUB_API    = "https://api.github.com"

PREFECTURES = {
    "hokkaido":"北海道","aomori":"青森県","iwate":"岩手県","miyagi":"宮城県",
    "akita":"秋田県","yamagata":"山形県","fukushima":"福島県","ibaraki":"茨城県",
    "tochigi":"栃木県","gunma":"群馬県","saitama":"埼玉県","chiba":"千葉県",
    "tokyo":"東京都","kanagawa":"神奈川県","niigata":"新潟県","toyama":"富山県",
    "ishikawa":"石川県","fukui":"福井県","yamanashi":"山梨県","nagano":"長野県",
    "gifu":"岐阜県","shizuoka":"静岡県","aichi":"愛知県","mie":"三重県",
    "shiga":"滋賀県","kyoto":"京都府","osaka":"大阪府","hyogo":"兵庫県",
    "nara":"奈良県","wakayama":"和歌山県","tottori":"鳥取県","shimane":"島根県",
    "okayama":"岡山県","hiroshima":"広島県","yamaguchi":"山口県","tokushima":"徳島県",
    "kagawa":"香川県","ehime":"愛媛県","kochi":"高知県","fukuoka":"福岡県",
    "saga":"佐賀県","nagasaki":"長崎県","kumamoto":"熊本県","oita":"大分県",
    "miyazaki":"宮崎県","kagoshima":"鹿児島県","okinawa":"沖縄県",
}

REGIONS = {
    "hokkaido":"hokkaido",
    "aomori":"tohoku","iwate":"tohoku","miyagi":"tohoku",
    "akita":"tohoku","yamagata":"tohoku","fukushima":"tohoku",
    "ibaraki":"kanto","tochigi":"kanto","gunma":"kanto",
    "saitama":"kanto","chiba":"kanto","tokyo":"kanto","kanagawa":"kanto",
    "niigata":"chubu","toyama":"chubu","ishikawa":"chubu","fukui":"chubu",
    "yamanashi":"chubu","nagano":"chubu","gifu":"chubu","shizuoka":"chubu",
    "aichi":"chubu","mie":"chubu",
    "shiga":"kinki","kyoto":"kinki","osaka":"kinki","hyogo":"kinki",
    "nara":"kinki","wakayama":"kinki",
    "tottori":"chugoku","shimane":"chugoku","okayama":"chugoku",
    "hiroshima":"chugoku","yamaguchi":"chugoku",
    "tokushima":"shikoku","kagawa":"shikoku","ehime":"shikoku","kochi":"shikoku",
    "fukuoka":"kyushu","saga":"kyushu","nagasaki":"kyushu","kumamoto":"kyushu",
    "oita":"kyushu","miyazaki":"kyushu","kagoshima":"kyushu","okinawa":"kyushu",
}

MUNICIPALITIES_QUERY = """\
[out:json][timeout:120];
area["admin_level"="4"]["name"="{pref_ja}"]->.pref;
(
  relation["admin_level"="7"]["boundary"="administrative"](area.pref);
  relation["admin_level"="8"]["boundary"="administrative"](area.pref);
);
out bb tags;
"""


def log(msg):
    print(f"[build_index] {msg}", flush=True)


# ─────────────────────────────────────────────
# GitHub API
# ─────────────────────────────────────────────
def get_token():
    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        print("エラー: GITHUB_TOKEN が設定されていません")
        sys.exit(1)
    return token


def github_request(method, path, body=None):
    token = get_token()
    data  = json.dumps(body, ensure_ascii=True).encode("utf-8") if body else None
    parsed   = urllib.parse.urlparse(f"{GITHUB_API}{path}")
    selector = parsed.path
    if parsed.query:
        selector += "?" + parsed.query

    def h(s): return s.encode("ascii", "ignore").decode("ascii")
    headers = {
        "Authorization": h(f"token {token}"),
        "Accept":        "application/vnd.github+json",
        "Content-Type":  "application/json; charset=utf-8",
        "User-Agent":    "GapLess-pipeline",
    }
    if data:
        headers["Content-Length"] = str(len(data))

    ctx  = ssl.create_default_context()
    conn = http.client.HTTPSConnection(parsed.netloc, context=ctx, timeout=30)
    try:
        conn.request(method, selector, body=data, headers=headers)
        resp      = conn.getresponse()
        resp_body = resp.read().decode("utf-8")
        if resp.status == 404:
            return {"_not_found": True}
        if resp.status >= 400:
            return {"_api_error": True, "_status": resp.status}
        return json.loads(resp_body)
    except Exception as e:
        log(f"GitHub API 失敗: {e}")
        return None
    finally:
        conn.close()


def list_github_dir(path, depth=0, max_depth=2) -> dict:
    """
    指定パス以下のファイルを再帰的に取得する。
    戻り値: {filename: download_url}
    """
    result = github_request("GET",
        f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/{path}?ref={GITHUB_BRANCH}")
    if not isinstance(result, list):
        return {}

    files = {}
    for item in result:
        if item["type"] == "file":
            files[item["name"]] = item.get("download_url", "")
        elif item["type"] == "dir" and depth < max_depth:
            sub = list_github_dir(f"{path}/{item['name']}", depth + 1, max_depth)
            files.update(sub)
    return files


def get_pref_files(pref_key) -> dict:
    """県フォルダ（旧構造・新構造両方）のファイル一覧を返す。"""
    files = {}
    # 旧構造
    files.update(list_github_dir(pref_key))
    # 新構造
    region = REGIONS.get(pref_key, "")
    if region:
        files.update(list_github_dir(f"{region}/{pref_key}"))
    return files


# ─────────────────────────────────────────────
# Overpass
# ─────────────────────────────────────────────
def overpass_request(query, retries=3):
    data = urllib.parse.urlencode({"data": query}).encode()
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(
                OVERPASS_URL, data=data,
                headers={"Content-Type": "application/x-www-form-urlencoded"})
            with urllib.request.urlopen(req, timeout=150) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as e:
            log(f"  Overpass エラー (試行 {attempt}/3): {e}")
            if attempt < retries:
                time.sleep(10)
    return None


def safe_slug(pref_key, tags):
    name_en = tags.get("name:en", "")
    if name_en:
        slug = re.sub(r"\s+", "_", name_en.lower())
        slug = re.sub(r"[^a-z0-9_]", "", slug)
        return f"{pref_key}_{slug}"
    name_ja = tags.get("name", "unknown")
    slug = re.sub(r"[市区町村郡]$", "", re.sub(r"[　\s]", "", name_ja))
    if not re.search(r"[^\x00-\x7F]", slug):
        return f"{pref_key}_{slug.lower()}"
    return f"{pref_key}_{abs(hash(name_ja)) % 100000:05d}"


def fetch_municipalities(pref_key) -> list:
    pref_ja = PREFECTURES[pref_key]
    raw = overpass_request(MUNICIPALITIES_QUERY.format(pref_ja=pref_ja))
    if raw is None:
        return []
    results = []
    seen = set()
    for el in raw.get("elements", []):
        if el.get("type") != "relation":
            continue
        tags   = el.get("tags", {})
        bounds = el.get("bounds")
        if not bounds:
            continue
        area_name = safe_slug(pref_key, tags)
        if area_name in seen:
            continue
        seen.add(area_name)
        results.append({
            "area_name": area_name,
            "name_ja":   tags.get("name", ""),
            "bbox": (bounds["minlat"], bounds["minlon"],
                     bounds["maxlat"], bounds["maxlon"]),
        })
    return results


# ─────────────────────────────────────────────
# index.json 構築
# ─────────────────────────────────────────────
def build_tile_entry(area_name, bbox, github_files) -> dict | None:
    """
    1市区町村のindex.jsonエントリを構築する。
    roads ファイルがなければ None を返す。
    """
    min_lat, min_lng, max_lat, max_lng = bbox

    roads_gz = f"{area_name}_roads.gplb.gz"
    if roads_gz not in github_files:
        return None

    files = {"roads": roads_gz}

    # POI（仕分け済み優先、なければ統合版）
    for cat in ["hospital", "shelter", "store", "water"]:
        fn = f"{area_name}_poi_{cat}.gplb.gz"
        if fn in github_files:
            files[f"poi_{cat}"] = fn
    if not any(k.startswith("poi_") for k in files):
        poi_gz = f"{area_name}_poi.gplb.gz"
        if poi_gz in github_files:
            files["poi"] = poi_gz

    # hazard
    hazard_gz = f"{area_name}_hazard.gplh.gz"
    if hazard_gz in github_files:
        files["hazard"] = hazard_gz

    today = time.strftime("%Y-%m-%d")
    return {
        "id":         area_name,
        "lat_min":    min_lat,
        "lat_max":    max_lat,
        "lng_min":    min_lng,
        "lng_max":    max_lng,
        "files":      files,
        "size_kb":    0,
        "updated_at": today,
    }


def upload_index(index: dict, dry_run: bool):
    """index.jsonをローカル保存してGitHubにアップロードする。"""
    os.makedirs(MAPS_DIR, exist_ok=True)
    with open(INDEX_PATH, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=2)
    log(f"index.json 保存: {INDEX_PATH} ({len(index['tiles'])} タイル)")

    if dry_run:
        log("[dry-run] アップロードをスキップ")
        return

    from github_upload import upload_files
    ok, ng = upload_files(
        [(INDEX_PATH, "index.json")],
        commit_prefix="Rebuild index.json"
    )
    log(f"index.json アップロード: {ok} 成功 / {ng} 失敗")


# ─────────────────────────────────────────────
# メイン
# ─────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="GitHub上のファイルからindex.jsonを一括再構築する")
    parser.add_argument("prefs", nargs="*", help="対象都道府県（省略時は全県）")
    parser.add_argument("--all",     action="store_true", help="全県処理")
    parser.add_argument("--dry-run", action="store_true", help="アップロードしない")
    parser.add_argument("--from", dest="from_pref", metavar="PREF",
                        help="指定した県から再開")
    args = parser.parse_args()

    all_keys = list(PREFECTURES.keys())

    if args.from_pref:
        if args.from_pref not in PREFECTURES:
            print(f"不明な県名: {args.from_pref}"); sys.exit(1)
        targets = all_keys[all_keys.index(args.from_pref):]
    elif args.all or not args.prefs:
        targets = all_keys
    else:
        targets = args.prefs
        for p in targets:
            if p not in PREFECTURES:
                print(f"不明な県名: {p}"); sys.exit(1)

    # 既存index.jsonを読み込む（あれば）
    if os.path.exists(INDEX_PATH):
        with open(INDEX_PATH, encoding="utf-8") as f:
            index = json.load(f)
        log(f"既存index.json読み込み: {len(index['tiles'])} タイル")
    else:
        index = {"version": 2, "updated_at": "", "tiles": []}

    existing_ids = {t["id"]: i for i, t in enumerate(index["tiles"])}
    today = time.strftime("%Y-%m-%d")

    for pref_key in targets:
        log(f"\n=== {PREFECTURES[pref_key]} ({pref_key}) ===")

        # GitHubのファイル一覧を取得
        log("  GitHub ファイル一覧を取得中...")
        github_files = get_pref_files(pref_key)
        log(f"  {len(github_files)} ファイル検出")

        if not github_files:
            log("  ファイルなし → スキップ")
            continue

        # Overpassから市区町村リストとbboxを取得
        log("  市区町村リストを取得中...")
        munis = fetch_municipalities(pref_key)
        log(f"  {len(munis)} 市区町村")
        time.sleep(3)

        added = updated = skipped = 0
        for muni in munis:
            area_name = muni["area_name"]
            entry = build_tile_entry(area_name, muni["bbox"], github_files)
            if entry is None:
                skipped += 1
                continue

            if area_name in existing_ids:
                index["tiles"][existing_ids[area_name]] = entry
                updated += 1
            else:
                index["tiles"].append(entry)
                existing_ids[area_name] = len(index["tiles"]) - 1
                added += 1

        log(f"  追加: {added} / 更新: {updated} / スキップ: {skipped}")

    index["updated_at"] = today
    upload_index(index, args.dry_run)
    log(f"\n完了: 合計 {len(index['tiles'])} タイル")


if __name__ == "__main__":
    main()
