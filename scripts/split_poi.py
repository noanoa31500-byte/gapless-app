#!/usr/bin/env python3
# ============================================================
# split_poi.py
# GitHubにある _poi.gplb.gz を4カテゴリに仕分けして
# 別ファイルとして再アップロードする。
#
# 出力ファイル（例: miyagi_sendai の場合）:
#   miyagi_sendai_poi_hospital.gplb.gz   病院・診療所
#   miyagi_sendai_poi_shelter.gplb.gz    避難所（学校・公民館含む）
#   miyagi_sendai_poi_store.gplb.gz      コンビニ・スーパー
#   miyagi_sendai_poi_water.gplb.gz      給水所（水・自販機・燃料）
#
# 使い方:
#   python3 split_poi.py miyagi
#   python3 split_poi.py miyagi ibaraki
#   python3 split_poi.py --all
#   python3 split_poi.py miyagi --check-only
#   python3 split_poi.py miyagi --dry-run
# ============================================================

import argparse
import base64
import gzip
import http.client
import json
import os
import ssl
import struct
import sys
import urllib.parse
import urllib.request

SCRIPTS_DIR   = os.path.dirname(os.path.abspath(__file__))
GITHUB_OWNER  = "noanoa31500-byte"
GITHUB_REPO   = "maps"
GITHUB_BRANCH = "main"
GITHUB_API    = "https://api.github.com"

# POI タイプID → カテゴリ
CATEGORY_MAP = {
    20: "shelter",   # 避難所
    21: "shelter",   # 学校
    22: "shelter",   # 公民館・市役所
    30: "store",     # コンビニ
    31: "store",     # スーパー
    32: "water",     # 給水所
    33: "water",     # 水の自販機
    34: "water",     # ガソリンスタンド
    40: "hospital",  # 病院・診療所
}

CATEGORY_LABELS = {
    "hospital": "病院・診療所",
    "shelter":  "避難所",
    "store":    "コンビニ・スーパー",
    "water":    "給水所",
}

CATEGORY_SUFFIX = {
    "hospital": "poi_hospital",
    "shelter":  "poi_shelter",
    "store":    "poi_store",
    "water":    "poi_water",
}

PREFECTURES = {
    "hokkaido":"北海道","aomori":"青森県","iwate":"岩手県","miyagi":"宮城県",
    "akita":"秋田県","yamagata":"山形県","fukushima":"福島県","ibaraki":"茨城県",
    "tochigi":"栃木県","gunma":"群馬県","saitama":"埼玉県","chiba":"千葉県",
    "tokyo":"東京都","kanagawa":"神奈川県","niigata":"新潟県","toyama":"富山県",
    "ishikawa":"石川県","fukui":"福井県","yamanashi":"山梨県","nagano":"長野県",
    "shizuoka":"静岡県","aichi":"愛知県","mie":"三重県","shiga":"滋賀県",
    "kyoto":"京都府","osaka":"大阪府","hyogo":"兵庫県","nara":"奈良県",
    "wakayama":"和歌山県","tottori":"鳥取県","shimane":"島根県","okayama":"岡山県",
    "hiroshima":"広島県","yamaguchi":"山口県","tokushima":"徳島県","kagawa":"香川県",
    "ehime":"愛媛県","kochi":"高知県","fukuoka":"福岡県","saga":"佐賀県",
    "nagasaki":"長崎県","kumamoto":"熊本県","oita":"大分県","miyazaki":"宮崎県",
    "kagoshima":"鹿児島県","okinawa":"沖縄県",
}


REGIONS = {
    "hokkaido":"hokkaido",
    "aomori":"tohoku","iwate":"tohoku","miyagi":"tohoku",
    "akita":"tohoku","yamagata":"tohoku","fukushima":"tohoku",
    "ibaraki":"kanto","tochigi":"kanto","gunma":"kanto",
    "saitama":"kanto","chiba":"kanto","tokyo":"kanto","kanagawa":"kanto",
    "niigata":"chubu","toyama":"chubu","ishikawa":"chubu","fukui":"chubu",
    "yamanashi":"chubu","nagano":"chubu","shizuoka":"chubu","aichi":"chubu","mie":"chubu",
    "shiga":"kinki","kyoto":"kinki","osaka":"kinki","hyogo":"kinki","nara":"kinki","wakayama":"kinki",
    "tottori":"chugoku","shimane":"chugoku","okayama":"chugoku","hiroshima":"chugoku","yamaguchi":"chugoku",
    "tokushima":"shikoku","kagawa":"shikoku","ehime":"shikoku","kochi":"shikoku",
    "fukuoka":"kyushu","saga":"kyushu","nagasaki":"kyushu","kumamoto":"kyushu",
    "oita":"kyushu","miyazaki":"kyushu","kagoshima":"kyushu","okinawa":"kyushu",
}


def log(msg):
    print(f"[split_poi] {msg}", flush=True)


# ─────────────────────────────────────────────
# GitHub API
# ─────────────────────────────────────────────
def get_token():
    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        print("エラー: GITHUB_TOKEN が設定されていません")
        print("export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx")
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
        log(f"API失敗: {e}")
        return None
    finally:
        conn.close()


def get_all_poi_files(pref_key) -> list | None:
    """
    旧構造（pref_key/）と新構造（region/pref_key/muni/）の両方から
    _poi.gplb.gz ファイルの情報リストを返す。
    APIエラー（rate limit等）の場合は None を返す。
    各要素: {"name": str, "download_url": str, "repo_path": str}
    """
    poi_files = []
    api_error = False

    def collect_from_path(base_path, depth=0):
        nonlocal api_error
        result = github_request("GET",
            f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/{base_path}?ref={GITHUB_BRANCH}")
        if result is None:
            api_error = True
            return
        if isinstance(result, dict):
            if result.get("_not_found"):
                return  # 404は正常（フォルダなし）
            if result.get("_api_error"):
                api_error = True
                return
            return
        if not isinstance(result, list):
            return
        for item in result:
            if item["type"] == "file":
                name = item["name"]
                if name.endswith("_poi.gplb.gz") and "_poi_" not in name:
                    poi_files.append({
                        "name":         name,
                        "download_url": item["download_url"],
                        "repo_path":    f"{base_path}/{name}",
                    })
            elif item["type"] == "dir" and depth < 2:
                # 1段階のみ再帰（市区町村フォルダ）
                collect_from_path(f"{base_path}/{item['name']}", depth + 1)

    # 旧構造
    collect_from_path(pref_key)
    if api_error:
        return None
    # 新構造
    region = REGIONS.get(pref_key, "")
    if region:
        collect_from_path(f"{region}/{pref_key}")
    if api_error:
        return None

    return poi_files


def download_file(download_url) -> bytes | None:
    try:
        req = urllib.request.Request(
            download_url, headers={"User-Agent": "GapLess-pipeline"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.read()
    except Exception as e:
        log(f"ダウンロード失敗: {e}")
        return None


def upload_to_github(repo_path, content_bytes, commit_message) -> bool:
    content_b64 = base64.b64encode(content_bytes).decode("utf-8")
    existing = github_request("GET",
        f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/{repo_path}"
        f"?ref={GITHUB_BRANCH}")
    sha = existing.get("sha") if existing else None
    body = {
        "message": commit_message.encode("ascii", "ignore").decode("ascii"),
        "content": content_b64,
        "branch":  GITHUB_BRANCH,
    }
    if sha:
        body["sha"] = sha
    result = github_request("PUT",
        f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/{repo_path}", body)
    return result is not None and "content" in result


# ─────────────────────────────────────────────
# GPLB v2 パーサー
# ─────────────────────────────────────────────
def parse_gplb_poi(data: bytes) -> list:
    if len(data) < 9:
        return []
    magic   = data[:4]
    version = data[4]
    if magic != b'GPLB' or version != 2:
        log(f"  非対応フォーマット (magic={magic}, ver={version})")
        return []
    count  = struct.unpack_from('<I', data, 5)[0]
    pois   = []
    offset = 9
    for _ in range(count):
        if offset + 11 > len(data):
            break
        poi_type = data[offset];                                   offset += 1
        lat      = struct.unpack_from('<i', data, offset)[0]/1e6; offset += 4
        lng      = struct.unpack_from('<i', data, offset)[0]/1e6; offset += 4
        offset  += 3   # padding (uint16 + uint8)
        name_len = data[offset];                                   offset += 1
        name     = data[offset:offset+name_len].decode("utf-8", errors="replace")
        offset  += name_len
        pois.append({"poi_type": poi_type, "lat": lat, "lng": lng, "name": name})
    return pois


# ─────────────────────────────────────────────
# GPLB v2 ビルダー
# ─────────────────────────────────────────────
def build_gplb_poi(pois: list) -> bytes:
    buf  = bytearray()
    buf += b'GPLB'
    buf += struct.pack('B', 2)
    buf += struct.pack('<I', len(pois))
    for p in pois:
        name_bytes = p["name"][:20].encode("utf-8")[:40]
        buf += struct.pack('B',  p["poi_type"])
        buf += struct.pack('<i', int(p["lat"] * 1e6))
        buf += struct.pack('<i', int(p["lng"] * 1e6))
        buf += struct.pack('<H', 0)
        buf += struct.pack('B',  0)
        buf += struct.pack('B',  len(name_bytes))
        buf += name_bytes
    return bytes(buf)


# ─────────────────────────────────────────────
# 1ファイルの仕分け
# ─────────────────────────────────────────────
def split_one(pref_key, area_name, gz_bytes, check_only, dry_run, upload_prefix=None) -> bool:
    try:
        raw  = gzip.decompress(gz_bytes)
        pois = parse_gplb_poi(raw)
    except Exception as e:
        log(f"  解凍/パース失敗: {e}")
        return False

    if not pois:
        log(f"  POIなし: {area_name}")
        return True

    # カテゴリ別に仕分け
    buckets: dict[str, list] = {c: [] for c in CATEGORY_LABELS}
    unknown_types = set()
    for p in pois:
        cat = CATEGORY_MAP.get(p["poi_type"])
        if cat:
            buckets[cat].append(p)
        else:
            unknown_types.add(p["poi_type"])

    summary = ", ".join(
        f"{CATEGORY_LABELS[c]}:{len(v)}" for c, v in buckets.items() if v)
    log(f"  {area_name}: 計{len(pois)}件 → {summary}")
    if unknown_types:
        log(f"  未分類タイプ: {unknown_types}")

    if check_only:
        return True

    # カテゴリ別にアップロード
    for cat, items in buckets.items():
        if not items:
            continue
        raw_cat   = build_gplb_poi(items)
        gz_cat    = gzip.compress(raw_cat, compresslevel=9)
        filename  = f"{area_name}_{CATEGORY_SUFFIX[cat]}.gplb.gz"
        prefix    = upload_prefix if upload_prefix else pref_key
        repo_path = f"{prefix}/{filename}"

        if dry_run:
            log(f"  [dry-run] {repo_path} ({len(gz_cat)//1024} KB, {len(items)}件)")
            continue

        ok = upload_to_github(repo_path, gz_cat,
                              f"Split POI {cat}: {area_name}")
        log(f"  {repo_path} ({len(items)}件) → {'完了' if ok else '失敗'}")

    return True


# ─────────────────────────────────────────────
# 県単位処理
# ─────────────────────────────────────────────
def process_prefecture(pref_key, check_only, dry_run):
    log(f"\n{'='*50}\n{PREFECTURES[pref_key]} ({pref_key})\n{'='*50}")

    poi_files = get_all_poi_files(pref_key)
    if poi_files is None:
        log(f"  APIエラー（レート制限の可能性）。時間をおいて再実行してください。")
        return
    if not poi_files:
        log(f"  POIファイルが見つかりません（旧構造・新構造ともに）")
        return

    log(f"  対象ファイル: {len(poi_files)} 件")

    for file_info in poi_files:
        area_name = file_info["name"].replace("_poi.gplb.gz", "")
        log(f"処理: {area_name}")
        gz_bytes = download_file(file_info["download_url"])
        if gz_bytes is None:
            log(f"  スキップ")
            continue
        # アップロード先は元ファイルと同じフォルダ
        base_repo_path = file_info["repo_path"].replace(f"/{file_info['name']}", "")
        split_one(pref_key, area_name, gz_bytes, check_only, dry_run,
                  upload_prefix=base_repo_path)


# ─────────────────────────────────────────────
# メイン
# ─────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="POIファイルを病院・避難所・コンビニ・給水所に仕分けする",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog="""
使用例:
  python3 split_poi.py miyagi
  python3 split_poi.py miyagi ibaraki
  python3 split_poi.py --all
  python3 split_poi.py miyagi --check-only   # 件数確認のみ
  python3 split_poi.py miyagi --dry-run      # アップロードしない
""")
    parser.add_argument("prefs",        nargs="*")
    parser.add_argument("--all",        action="store_true", help="全県処理")
    parser.add_argument("--check-only", action="store_true", help="件数確認のみ")
    parser.add_argument("--dry-run",    action="store_true", help="アップロードしない")
    args = parser.parse_args()

    if args.all:
        targets = list(PREFECTURES.keys())
    elif args.prefs:
        targets = args.prefs
    else:
        parser.print_help(); sys.exit(1)

    unknown = [p for p in targets if p not in PREFECTURES]
    if unknown:
        print(f"不明な県名: {unknown}"); sys.exit(1)

    for pref_key in targets:
        process_prefecture(pref_key, args.check_only, args.dry_run)

    log("\n完了")


if __name__ == "__main__":
    main()
