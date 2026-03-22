#!/usr/bin/env python3
# ============================================================
# check_and_fill.py
# GitHubにある市区町村データと、Overpassから取得できる
# 全市区町村リストを比較し、不足分だけ取得・アップロードする。
#
# 使い方:
#   python3 check_and_fill.py              # 全県をチェックして不足分を取得
#   python3 check_and_fill.py miyagi       # 宮城県だけチェック
#   python3 check_and_fill.py --check-only # 不足リストを表示するだけ（取得しない）
#   python3 check_and_fill.py --dry-run    # 取得するがアップロードしない
# ============================================================

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import http.client
import ssl
import subprocess

SCRIPTS_DIR  = os.path.dirname(os.path.abspath(__file__))
DATA_DIR     = os.path.expanduser("~/Desktop/GapLess/data")
MAPS_DIR     = os.path.normpath(os.path.join(SCRIPTS_DIR, "..", "maps"))
OVERPASS_URL = "https://overpass-api.de/api/interpreter"
OVERPASS_TIMEOUT   = 180
REQUEST_INTERVAL   = 6
MUNICIPALITY_PAUSE = 2

# GitHub設定
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
    "shizuoka":"静岡県","aichi":"愛知県","mie":"三重県","shiga":"滋賀県",
    "kyoto":"京都府","osaka":"大阪府","hyogo":"兵庫県","nara":"奈良県",
    "wakayama":"和歌山県","tottori":"鳥取県","shimane":"島根県","okayama":"岡山県",
    "hiroshima":"広島県","yamaguchi":"山口県","tokushima":"徳島県","kagawa":"香川県",
    "ehime":"愛媛県","kochi":"高知県","fukuoka":"福岡県","saga":"佐賀県",
    "nagasaki":"長崎県","kumamoto":"熊本県","oita":"大分県","miyazaki":"宮崎県",
    "kagoshima":"鹿児島県","okinawa":"沖縄県",
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

ROADS_QUERY = """\
[out:json][timeout:{timeout}];
(
  way["highway"]["highway"!~"footway|steps|path|cycleway|service|track|proposed|construction|motorway|motorway_link"]
  ({min_lat},{min_lng},{max_lat},{max_lng});
);
out body;>;
out skel qt;
"""

POI_QUERY = """\
[out:json][timeout:{timeout}];
(
  node["amenity"="hospital"]({min_lat},{min_lng},{max_lat},{max_lng});
  way["amenity"="hospital"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["amenity"="clinic"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["amenity"="shelter"]({min_lat},{min_lng},{max_lat},{max_lng});
  way["amenity"="shelter"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["amenity"="community_centre"]({min_lat},{min_lng},{max_lat},{max_lng});
  way["amenity"="community_centre"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["amenity"="townhall"]({min_lat},{min_lng},{max_lat},{max_lng});
  way["amenity"="school"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["emergency"="assembly_point"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["shop"="convenience"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["shop"="supermarket"]({min_lat},{min_lng},{max_lat},{max_lng});
  way["shop"="supermarket"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["amenity"="drinking_water"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["amenity"="fuel"]({min_lat},{min_lng},{max_lat},{max_lng});
);
out body;>;
out skel qt;
"""


# ─────────────────────────────────────────────
# ログ
# ─────────────────────────────────────────────
def log(msg):
    print(f"[check_and_fill] {msg}", flush=True)


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
        log(f"GitHub API 失敗: {e}")
        return None
    finally:
        conn.close()


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


def get_github_files_from_path(path, depth=0, max_depth=3) -> set:
    """
    指定パス以下のファイル名を再帰的に取得する。
    404は「フォルダなし」として空setを返す。
    APIエラー（rate limit等）は None を返す。
    """
    result = github_request("GET",
        f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/{path}?ref={GITHUB_BRANCH}")
    if isinstance(result, dict):
        if result.get("_not_found"):
            return set()   # フォルダが存在しないだけ
        if result.get("_api_error"):
            return None    # レート制限等の本当のエラー
        return set()
    if not isinstance(result, list):
        return set()

    files = set()
    for item in result:
        if item["type"] == "file":
            files.add(item["name"])
        elif item["type"] == "dir" and depth < max_depth:
            sub = get_github_files_from_path(
                f"{path}/{item['name']}", depth + 1, max_depth)
            if sub is None:
                return None  # エラーを上位に伝播
            files |= sub
    return files


def get_github_files(pref_key) -> set:
    """
    旧構造（pref_key/）と新構造（region/pref_key/muni/）の両方からファイル名を取得する。
    APIエラー時は空setを返してログに出す。
    """
    files = set()

    # 旧構造
    result = get_github_files_from_path(pref_key)
    if result is None:
        log("  GitHub APIエラー（レート制限の可能性）。時間をおいて再実行してください。")
        return set()
    files |= result

    # 新構造
    region = REGIONS.get(pref_key, "")
    if region:
        result = get_github_files_from_path(f"{region}/{pref_key}")
        if result is None:
            log("  GitHub APIエラー（レート制限の可能性）。時間をおいて再実行してください。")
            return set()
        files |= result

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
            with urllib.request.urlopen(req, timeout=OVERPASS_TIMEOUT + 30) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            log(f"HTTP {e.code} (試行 {attempt}/{retries})")
            if e.code == 429:
                time.sleep(60)
        except Exception as e:
            log(f"失敗: {e} (試行 {attempt}/{retries})")
        time.sleep(REQUEST_INTERVAL * attempt)
    return None


def osm_to_geojson(osm):
    nodes = {}
    features = []
    for el in osm.get("elements", []):
        if el["type"] == "node":
            nodes[el["id"]] = (el["lon"], el["lat"])
    for el in osm.get("elements", []):
        props = {**el.get("tags", {}), "osm_id": el["id"]}
        if el["type"] == "node":
            features.append({"type": "Feature", "properties": props,
                "geometry": {"type": "Point", "coordinates": [el["lon"], el["lat"]]}})
        elif el["type"] == "way":
            coords = [nodes[n] for n in el.get("nodes", []) if n in nodes]
            if len(coords) >= 2:
                features.append({"type": "Feature", "properties": props,
                    "geometry": {"type": "LineString", "coordinates": coords}})
    return {"type": "FeatureCollection", "features": features}


def safe_area_name(pref_key, tags):
    name_en = tags.get("name:en", "")
    if name_en:
        slug = re.sub(r'\s+', '_', name_en.lower())
        slug = re.sub(r'[^a-z0-9_]', '', slug)
        return f"{pref_key}_{slug}"
    name_ja = tags.get("name", "unknown")
    slug = re.sub(r'[市区町村郡]$', '', re.sub(r'[　\s]', '', name_ja))
    if not re.search(r'[^\x00-\x7F]', slug):
        return f"{pref_key}_{slug.lower()}"
    return f"{pref_key}_{abs(hash(name_ja)) % 100000:05d}"


def fetch_municipalities(pref_key):
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
        area_name = safe_area_name(pref_key, tags)
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
# 不足チェック
# ─────────────────────────────────────────────
def find_missing(pref_key, check_hazard=False) -> list[dict]:
    """
    Overpass から全市区町村リストを取得し、
    GitHub にない市区町村を返す。

    check_hazard=False: roads / poi の不足を検査
    check_hazard=True:  hazard (.gplh.gz) の不足を検査
    """
    mode = "hazard" if check_hazard else "roads/poi"
    log(f"{PREFECTURES[pref_key]} の不足チェック中... ({mode})")

    munis = fetch_municipalities(pref_key)
    if not munis:
        log(f"  市区町村リスト取得失敗")
        return []

    github_files = get_github_files(pref_key)
    log(f"  GitHub に {len(github_files)} ファイル / Overpass に {len(munis)} 市区町村")

    missing = []
    for muni in munis:
        if check_hazard:
            hazard_gz = f"{muni['area_name']}_hazard.gplh.gz"
            if hazard_gz not in github_files:
                missing.append(muni)
        else:
            an = muni['area_name']
            roads_gz = f"{an}_roads.gplb.gz"
            # split_poi.py 実行後は _poi.gplb.gz が仕分け済みファイルに置き換わる
            # どちらかが存在すれば「完了」とみなす
            poi_gz        = f"{an}_poi.gplb.gz"
            poi_hospital  = f"{an}_poi_hospital.gplb.gz"
            poi_ok = poi_gz in github_files or poi_hospital in github_files
            if roads_gz not in github_files or not poi_ok:
                missing.append(muni)

    log(f"  不足: {len(missing)} 市区町村")
    return missing


# ─────────────────────────────────────────────
# 取得・変換・アップロード
# ─────────────────────────────────────────────
def run(cmd, cwd=None):
    result = subprocess.run(cmd, cwd=cwd)
    return result.returncode == 0


def process_muni(pref_key, muni, dry_run) -> bool:
    area_name = muni["area_name"]
    min_lat, min_lng, max_lat, max_lng = muni["bbox"]

    pref_data_dir = os.path.join(DATA_DIR, pref_key)
    os.makedirs(pref_data_dir, exist_ok=True)
    os.makedirs(MAPS_DIR, exist_ok=True)

    # 道路
    roads_raw = os.path.join(pref_data_dir, f"{area_name}_roads_raw.geojson")
    if not os.path.exists(roads_raw):
        q   = ROADS_QUERY.format(timeout=OVERPASS_TIMEOUT,
                min_lat=min_lat, min_lng=min_lng,
                max_lat=max_lat, max_lng=max_lng)
        raw = overpass_request(q)
        if raw is None:
            return False
        with open(roads_raw, "w") as f:
            json.dump(osm_to_geojson(raw), f)
        time.sleep(REQUEST_INTERVAL)

    # POI
    poi_raw = os.path.join(pref_data_dir, f"{area_name}_poi_raw.geojson")
    if not os.path.exists(poi_raw):
        q   = POI_QUERY.format(timeout=OVERPASS_TIMEOUT,
                min_lat=min_lat, min_lng=min_lng,
                max_lat=max_lat, max_lng=max_lng)
        raw = overpass_request(q)
        if raw is None:
            return False
        with open(poi_raw, "w") as f:
            json.dump(osm_to_geojson(raw), f)
        time.sleep(REQUEST_INTERVAL)

    # compress.py
    compress = os.path.join(SCRIPTS_DIR, "compress.py")
    for suffix, kind in [("roads", "roads"), ("poi", "poi")]:
        ok = run(["python3", compress,
                  os.path.join(pref_data_dir, f"{area_name}_{suffix}_raw.geojson"),
                  area_name + f"_{suffix}",
                  kind], cwd=SCRIPTS_DIR)
        if not ok:
            return False

    # update_index.py
    update = os.path.join(SCRIPTS_DIR, "update_index.py")
    run(["python3", update, area_name,
         str(min_lat), str(min_lng), str(max_lat), str(max_lng)],
        cwd=SCRIPTS_DIR)

    # アップロード
    if not dry_run:
        from github_upload import upload_files
        region = REGIONS.get(pref_key, pref_key)
        local_files = []
        for suffix in ["roads", "poi"]:
            gz = os.path.join(MAPS_DIR, f"{area_name}_{suffix}.gplb.gz")
            if os.path.exists(gz):
                # 新構造: region/pref_key/area_name/filename
                repo_path = f"{region}/{pref_key}/{area_name}/{os.path.basename(gz)}"
                local_files.append((gz, repo_path))
        index_path = os.path.join(MAPS_DIR, "index.json")
        if os.path.exists(index_path):
            local_files.append((index_path, "index.json"))
        if local_files:
            ok, ng = upload_files(local_files, commit_prefix=f"Fill missing: {area_name}")
            log(f"  アップロード: {ok} 成功 / {ng} 失敗")
            # アップロード成功分のみ削除
            if ok:
                for gz_path, _ in local_files:
                    if os.path.exists(gz_path) and gz_path != index_path:
                        os.remove(gz_path)

    return True


# ─────────────────────────────────────────────
# hazard 不足補完
# ─────────────────────────────────────────────
def process_missing_hazard(pref_key, missing_munis, dry_run) -> int:
    """
    不足している市区町村のhazardデータだけを補完してアップロードする。
    県全体のGeoJSONキャッシュが存在すれば再利用する。
    戻り値: 成功した市区町村数
    """
    import json as _json
    import gzip as _gzip

    pref_geojson = os.path.join(DATA_DIR, f"{pref_key}_hazard_raw.geojson")

    # 県全体GeoJSONがなければfetch_hazard.pyを実行
    if not os.path.exists(pref_geojson):
        log(f"  {PREFECTURES[pref_key]}: 県全体GeoJSONがありません。fetch_hazard.py を実行します...")
        fetch_script = os.path.join(SCRIPTS_DIR, "fetch_hazard.py")
        ok = subprocess.run(
            ["python3", fetch_script, pref_key, "--geojson-only"],
            cwd=SCRIPTS_DIR
        ).returncode == 0
        if not ok or not os.path.exists(pref_geojson):
            log(f"  GeoJSON取得失敗")
            return 0

    # 県全体GeoJSONを読み込む
    log(f"  GeoJSONを読み込み中: {pref_geojson}")
    try:
        with open(pref_geojson, encoding="utf-8") as f:
            pref_data = _json.load(f)
    except Exception as e:
        log(f"  GeoJSON読み込み失敗: {e}")
        return 0

    all_features = pref_data.get("features", [])
    log(f"  全フィーチャー数: {len(all_features)}")

    compress_script = os.path.join(SCRIPTS_DIR, "compress.py")
    region = REGIONS.get(pref_key, pref_key)
    success = 0

    for i, muni in enumerate(missing_munis, 1):
        area_name = muni["area_name"]
        bbox      = muni["bbox"]
        log(f"  [{i}/{len(missing_munis)}] {muni['name_ja']} ({area_name}) 補完中...")

        # bboxでフィーチャーを切り出し
        min_lat, min_lng, max_lat, max_lng = bbox
        clipped = []
        for feat in all_features:
            geom   = feat.get("geometry", {})
            coords = geom.get("coordinates", [[]])[0]
            if not coords:
                continue
            try:
                pts = [pt for pt in coords if isinstance(pt, (list, tuple)) and len(pt) >= 2]
                if not pts:
                    continue
                lats = [float(p[1]) for p in pts]
                lngs = [float(p[0]) for p in pts]
                clat = sum(lats) / len(lats)
                clng = sum(lngs) / len(lngs)
                if min_lat <= clat <= max_lat and min_lng <= clng <= max_lng:
                    clipped.append(feat)
            except:
                continue

        if not clipped:
            log(f"    フィーチャーなし → スキップ")
            continue

        # 一時GeoJSONに保存
        muni_geojson = os.path.join(DATA_DIR, f"{area_name}_hazard_raw.geojson")
        with open(muni_geojson, "w", encoding="utf-8") as f:
            _json.dump({"type": "FeatureCollection", "features": clipped}, f, ensure_ascii=False)

        # GPLH変換
        ok = run(["python3", compress_script,
                  muni_geojson, f"{area_name}_hazard", "hazard"],
                 cwd=SCRIPTS_DIR)
        if not ok:
            log(f"    compress.py 失敗")
            if os.path.exists(muni_geojson):
                os.remove(muni_geojson)
            continue

        gplh_gz = os.path.join(MAPS_DIR, f"{area_name}_hazard.gplh.gz")
        if not os.path.exists(gplh_gz):
            log(f"    gplh.gz が生成されませんでした")
            if os.path.exists(muni_geojson):
                os.remove(muni_geojson)
            continue

        # アップロード
        uploaded = False
        if not dry_run:
            from github_upload import upload_files
            repo_path = f"{region}/{pref_key}/{area_name}/{os.path.basename(gplh_gz)}"
            ok2, ng = upload_files(
                [(gplh_gz, repo_path)],
                commit_prefix=f"Fill hazard: {area_name}"
            )
            log(f"    アップロード: {ok2} 成功 / {ng} 失敗")
            if ok2:
                success += 1
                uploaded = True
        else:
            log(f"    [dry-run] {gplh_gz} → {region}/{pref_key}/{area_name}/")
            success += 1
            uploaded = True

        # 一時GeoJSONは常に削除
        if os.path.exists(muni_geojson):
            os.remove(muni_geojson)
        # gplh.gz はアップロード成功時のみ削除
        if uploaded and os.path.exists(gplh_gz):
            os.remove(gplh_gz)

    return success


# ─────────────────────────────────────────────
# メイン
# ─────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="不足している市区町村データを検出して補完する")
    parser.add_argument("prefs", nargs="*",
                        help="対象の都道府県（省略時は全県）")
    parser.add_argument("--check-only", action="store_true",
                        help="不足リストを表示するだけ（取得しない）")
    parser.add_argument("--dry-run",    action="store_true",
                        help="取得・変換するがアップロードしない")
    parser.add_argument("--hazard",     action="store_true",
                        help="hazardデータの不足チェック・補完（fetch_hazard.pyを呼び出す）")
    args = parser.parse_args()

    targets = args.prefs if args.prefs else list(PREFECTURES.keys())
    unknown = [p for p in targets if p not in PREFECTURES]
    if unknown:
        print(f"不明な県名: {unknown}"); sys.exit(1)

    total_missing  = 0
    total_filled   = 0
    total_failed   = 0

    for pref_key in targets:
        missing = find_missing(pref_key, check_hazard=args.hazard)
        total_missing += len(missing)

        if not missing:
            log(f"{PREFECTURES[pref_key]}: 不足なし")
            continue

        log(f"{PREFECTURES[pref_key]}: {len(missing)} 件不足")
        for m in missing:
            log(f"  - {m['name_ja']} ({m['area_name']})")

        if args.check_only:
            continue

        if args.hazard:
            # hazard不足 → 不足市区町村だけを補完してアップロード
            ok = process_missing_hazard(pref_key, missing, args.dry_run)
            total_filled += ok
            total_failed += len(missing) - ok
        else:
            # roads/poi不足 → 市区町村単位で取得
            for i, muni in enumerate(missing, 1):
                log(f"[{i}/{len(missing)}] {muni['name_ja']} 取得中...")
                ok = process_muni(pref_key, muni, args.dry_run)
                if ok:
                    total_filled += 1
                    log(f"  完了: {muni['name_ja']}")
                else:
                    total_failed += 1
                    log(f"  失敗: {muni['name_ja']}")
                time.sleep(MUNICIPALITY_PAUSE)

    log(f"\n{'='*50}")
    log(f"不足合計: {total_missing} 市区町村")
    if not args.check_only:
        log(f"補完成功: {total_filled} / 失敗: {total_failed}")


if __name__ == "__main__":
    main()