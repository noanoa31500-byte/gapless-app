#!/usr/bin/env python3
"""
auto_map_pipeline_v3.py
v2 からの変更点:
  - POI クエリにスーパー・避難所を追加
  - hazard モード（洪水リスク）の収集に対応（--hazard フラグ）
  - ただし hazard は fetch_hazard_tokyo.py で別途処理する方が安定するため
    このスクリプトでは OSM の簡易ハザードタグのみ収集する

使い方（v2 と同じ）:
  python3 auto_map_pipeline_v3.py miyagi
  python3 auto_map_pipeline_v3.py --all
  python3 auto_map_pipeline_v3.py --municipalities miyagi
"""

import argparse, json, os, re, subprocess, sys, time
import urllib.error, urllib.parse, urllib.request

SCRIPTS_DIR  = os.path.expanduser("~/Desktop/GapLess/scripts")
DATA_DIR     = os.path.expanduser("~/Desktop/GapLess/data")
OUTPUT_DIR   = os.path.expanduser("~/Desktop/GapLess/output")
OVERPASS_URL = "https://overpass-api.de/api/interpreter"
OVERPASS_TIMEOUT   = 180
REQUEST_INTERVAL   = 6
MUNICIPALITY_PAUSE = 2

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

# ────────────────────────────────────────────────────────
# POI クエリ（v3 で拡充）
# compress.py の POI_TYPE_MAP に対応するタグをすべて収集する
#
#  20: shelter（避難所）
#  21: school（学校 → 避難所として機能することが多い）
#  22: community_centre / townhall
#  30: convenience（コンビニ）
#  31: supermarket（スーパー）
#  32: drinking_water（給水所）
#  33: vending_machine
#  34: fuel（ガソリンスタンド → 緊急時の給電・補給）
#  40: hospital / clinic（病院）
# ────────────────────────────────────────────────────────
POI_QUERY = """\
[out:json][timeout:{timeout}];
(
  // ── 病院・診療所 ──
  node["amenity"="hospital"]({min_lat},{min_lng},{max_lat},{max_lng});
  way["amenity"="hospital"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["amenity"="clinic"]({min_lat},{min_lng},{max_lat},{max_lng});
  way["amenity"="clinic"]({min_lat},{min_lng},{max_lat},{max_lng});

  // ── 避難所・公共施設 ──
  node["amenity"="shelter"]({min_lat},{min_lng},{max_lat},{max_lng});
  way["amenity"="shelter"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["amenity"="community_centre"]({min_lat},{min_lng},{max_lat},{max_lng});
  way["amenity"="community_centre"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["amenity"="townhall"]({min_lat},{min_lng},{max_lat},{max_lng});
  way["amenity"="townhall"]({min_lat},{min_lng},{max_lat},{max_lng});

  // ── 学校（避難所指定が多い）──
  way["amenity"="school"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["amenity"="school"]({min_lat},{min_lng},{max_lat},{max_lng});

  // ── 日本固有の避難所タグ ──
  node["emergency"="assembly_point"]({min_lat},{min_lng},{max_lat},{max_lng});
  way["emergency"="assembly_point"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["disaster"="evacuation_site"]({min_lat},{min_lng},{max_lat},{max_lng});

  // ── コンビニ・スーパー（給水・補給拠点）──
  node["shop"="convenience"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["shop"="supermarket"]({min_lat},{min_lng},{max_lat},{max_lng});
  way["shop"="supermarket"]({min_lat},{min_lng},{max_lat},{max_lng});

  // ── 給水・補給 ──
  node["amenity"="drinking_water"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["amenity"="vending_machine"]["vending"="water"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["amenity"="fuel"]({min_lat},{min_lng},{max_lat},{max_lng});
);
out body;>;
out skel qt;
"""


def log(msg):
    print(f"[pipeline] {msg}", flush=True)

def run(cmd, cwd=None):
    log(f"$ {' '.join(cmd)}")
    r = subprocess.run(cmd, cwd=cwd)
    if r.returncode != 0:
        log(f"ERROR: exit {r.returncode}")
        return False
    return True

def overpass_request(query, retries=3):
    data = urllib.parse.urlencode({"data": query}).encode()
    for attempt in range(1, retries+1):
        try:
            req = urllib.request.Request(
                OVERPASS_URL, data=data,
                headers={"Content-Type": "application/x-www-form-urlencoded"})
            with urllib.request.urlopen(req, timeout=OVERPASS_TIMEOUT+30) as resp:
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
            features.append({"type":"Feature","properties":props,
                "geometry":{"type":"Point","coordinates":[el["lon"],el["lat"]]}})
        elif el["type"] == "way":
            coords = [nodes[n] for n in el.get("nodes",[]) if n in nodes]
            if len(coords) >= 2:
                features.append({"type":"Feature","properties":props,
                    "geometry":{"type":"LineString","coordinates":coords}})
    return {"type":"FeatureCollection","features":features}

def safe_area_name(pref_key, tags):
    name_en = tags.get("name:en","")
    if name_en:
        slug = re.sub(r'\s+','_',name_en.lower())
        slug = re.sub(r'[^a-z0-9_]','',slug)
        return f"{pref_key}_{slug}"
    name_ja = tags.get("name","unknown")
    slug = re.sub(r'[市区町村郡]$','',re.sub(r'[　\s]','',name_ja))
    if not re.search(r'[^\x00-\x7F]',slug):
        return f"{pref_key}_{slug.lower()}"
    return f"{pref_key}_{abs(hash(name_ja))%100000:05d}"

def fetch_municipalities(pref_key):
    pref_ja = PREFECTURES[pref_key]
    log(f"{pref_ja} の市区町村リスト取得中...")
    raw = overpass_request(MUNICIPALITIES_QUERY.format(pref_ja=pref_ja))
    if raw is None:
        return []
    results = []
    seen = set()
    for el in raw.get("elements",[]):
        if el.get("type") != "relation":
            continue
        tags = el.get("tags",{})
        bounds = el.get("bounds")
        if not bounds:
            continue
        area_name = safe_area_name(pref_key, tags)
        if area_name in seen:
            continue
        seen.add(area_name)
        results.append({
            "area_name": area_name,
            "name_ja":   tags.get("name",""),
            "bbox":      (bounds["minlat"],bounds["minlon"],bounds["maxlat"],bounds["maxlon"]),
        })
    log(f"{pref_ja}: {len(results)} 市区町村")
    return results

def process_municipality(pref_key, muni, dry_run):
    area_name = muni["area_name"]
    name_ja   = muni["name_ja"]
    min_lat, min_lng, max_lat, max_lng = muni["bbox"]
    log(f"  [{name_ja}] ({area_name})")

    pref_data_dir   = os.path.join(DATA_DIR,   pref_key)
    pref_output_dir = os.path.join(OUTPUT_DIR, pref_key)
    os.makedirs(pref_data_dir,   exist_ok=True)
    os.makedirs(pref_output_dir, exist_ok=True)

    # 道路
    roads_raw = os.path.join(pref_data_dir, f"{area_name}_roads_raw.geojson")
    if not os.path.exists(roads_raw):
        q = ROADS_QUERY.format(timeout=OVERPASS_TIMEOUT,
            min_lat=min_lat,min_lng=min_lng,max_lat=max_lat,max_lng=max_lng)
        raw = overpass_request(q)
        if raw is None: return False
        with open(roads_raw,"w") as f: json.dump(osm_to_geojson(raw),f)
        time.sleep(REQUEST_INTERVAL)

    # POI（v3: 拡充クエリ）
    poi_raw = os.path.join(pref_data_dir, f"{area_name}_poi_raw.geojson")
    if not os.path.exists(poi_raw):
        q = POI_QUERY.format(timeout=OVERPASS_TIMEOUT,
            min_lat=min_lat,min_lng=min_lng,max_lat=max_lat,max_lng=max_lng)
        raw = overpass_request(q)
        if raw is None: return False
        with open(poi_raw,"w") as f: json.dump(osm_to_geojson(raw),f)
        time.sleep(REQUEST_INTERVAL)

    # compress.py
    # compress.py は ../output/ に出力する（SCRIPTS_DIR 基準）
    # 県フォルダ分けは git push 前に手動 or 別途整理
    for suffix, kind in [("roads","roads"),("poi","poi")]:
        ok = run(["python3","compress.py",
            os.path.join(pref_data_dir, f"{area_name}_{suffix}_raw.geojson"),
            f"{area_name}_{suffix}",
            kind], cwd=SCRIPTS_DIR)
        if not ok: return False

    ok = run(["python3","update_index.py",
        area_name,
        str(min_lat),str(min_lng),str(max_lat),str(max_lng)], cwd=SCRIPTS_DIR)
    return ok

def update_master_index(processed_prefs):
    master = {}
    for pref_key in processed_prefs:
        idx_path = os.path.join(OUTPUT_DIR, pref_key, "index.json")
        if os.path.exists(idx_path):
            with open(idx_path) as f:
                master[pref_key] = json.load(f)
    master_path = os.path.join(OUTPUT_DIR, "index.json")
    with open(master_path,"w") as f:
        json.dump(master, f, ensure_ascii=False, indent=2)
    log(f"マスター index.json 更新")

def upload_pref(pref_key, dry_run):
    from github_upload import upload_files
    actual_output = os.path.normpath(os.path.join(SCRIPTS_DIR, "..", "maps"))
    if not os.path.isdir(actual_output):
        log(f"output ディレクトリが見つかりません: {actual_output}")
        return
    local_files = [os.path.join(actual_output, f) for f in os.listdir(actual_output)
                   if f.startswith(pref_key) and (f.endswith(".gplb.gz") or f.endswith(".gplh.gz"))]
    index_path = os.path.join(actual_output, "index.json")
    if os.path.exists(index_path):
        local_files.append(index_path)
    # index.json だけルート直下、他は県フォルダ
    pairs = [(p, f"{pref_key}/{os.path.basename(p)}" if p != index_path else "index.json") for p in local_files]
    if not local_files:
        log(f"{pref_key}: アップロードするファイルなし")
        return
    if dry_run:
        log(f"[dry-run] {len(local_files)} ファイル ({pref_key})")
        return
    ok, ng = upload_files(pairs, commit_prefix=f"Add map data: {pref_key}")
    log(f"アップロード完了: {ok} 成功 / {ng} 失敗")


def main():
    parser = argparse.ArgumentParser(
        description="GapLess マップデータ 都道府県×市区町村 パイプライン",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog="""
使用例:
  # 県単位
  python3 auto_map_pipeline_v3.py tokyo
  python3 auto_map_pipeline_v3.py --all
  python3 auto_map_pipeline_v3.py --from iwate        # 岩手から全県再開

  # 市区町村単位
  python3 auto_map_pipeline_v3.py --muni miyagi 仙台市  # 仙台市だけ取得
  python3 auto_map_pipeline_v3.py --from-muni miyagi 仙台市  # 宮城県内を仙台市から再開
  python3 auto_map_pipeline_v3.py --municipalities miyagi  # 市区町村一覧を表示
"""
    )
    parser.add_argument("prefs", nargs="*")
    parser.add_argument("--all",       action="store_true", help="47都道府県すべて処理")
    parser.add_argument("--dry-run",   action="store_true", help="git push をしない")
    parser.add_argument("--list",      action="store_true", help="都道府県一覧を表示")
    parser.add_argument("--municipalities", metavar="PREF", help="指定県の市区町村一覧を表示")
    parser.add_argument("--from",      dest="from_pref",  metavar="PREF",  help="指定した県から残りを実行（県途中再開）")
    parser.add_argument("--muni",      dest="muni",       nargs=2, metavar=("PREF", "NAME"), help="指定した市区町村だけ取得")
    parser.add_argument("--from-muni", dest="from_muni",  nargs=2, metavar=("PREF", "NAME"), help="指定した市区町村から県内を再開")
    args = parser.parse_args()

    # 都道府県一覧
    if args.list:
        for k,v in PREFECTURES.items():
            print(f"  {k:15s} {v}")
        return

    # 市区町村一覧表示
    if args.municipalities:
        pref_key = args.municipalities
        if pref_key not in PREFECTURES:
            print(f"不明: {pref_key}"); sys.exit(1)
        munis = fetch_municipalities(pref_key)
        for i, m in enumerate(munis, 1):
            print(f"  {i:3d}. {m['area_name']:40s} {m['name_ja']}")
        return

    # 市区町村単体取得
    if args.muni:
        pref_key, muni_name = args.muni
        if pref_key not in PREFECTURES:
            print(f"不明な県名: {pref_key}"); sys.exit(1)
        munis = fetch_municipalities(pref_key)
        matches = [m for m in munis if m["name_ja"] == muni_name or m["area_name"] == muni_name]
        if not matches:
            print(f"市区町村が見つかりません: {muni_name}")
            print(f"python3 auto_map_pipeline_v3.py --municipalities {pref_key} で一覧確認")
            sys.exit(1)
        for muni in matches:
            log(f"単体取得: {muni['name_ja']} ({muni['area_name']})")
            process_municipality(pref_key, muni, args.dry_run)
            upload_pref(pref_key, args.dry_run)
        return

    # 市区町村から県内を再開
    if args.from_muni:
        pref_key, muni_name = args.from_muni
        if pref_key not in PREFECTURES:
            print(f"不明な県名: {pref_key}"); sys.exit(1)
        munis = fetch_municipalities(pref_key)
        # 日本語名 or area_name どちらでも検索
        start_idx = None
        for i, m in enumerate(munis):
            if m["name_ja"] == muni_name or m["area_name"] == muni_name:
                start_idx = i
                break
        if start_idx is None:
            print(f"市区町村が見つかりません: {muni_name}")
            print(f"python3 auto_map_pipeline_v3.py --municipalities {pref_key} で一覧確認")
            sys.exit(1)
        remaining = munis[start_idx:]
        log(f"{PREFECTURES[pref_key]} を {muni_name} から再開（残り {len(remaining)}/{len(munis)} 市区町村）")
        ok_count, failed = 0, []
        for i, muni in enumerate(remaining, 1):
            log(f"[{i}/{len(remaining)}]")
            if process_municipality(pref_key, muni, args.dry_run):
                ok_count += 1
            else:
                failed.append(muni["name_ja"])
            time.sleep(MUNICIPALITY_PAUSE)
        log(f"{pref_key}: {ok_count}/{len(remaining)} 完了")
        if failed: log(f"失敗: {failed}")
        if ok_count > 0:
            upload_pref(pref_key, args.dry_run)
        return

    # 通常の県単位処理
    if args.from_pref:
        # --from 単体で使える（--all 不要）
        if args.from_pref not in PREFECTURES:
            print(f"不明な県名: {args.from_pref}"); sys.exit(1)
        all_keys = list(PREFECTURES.keys())
        start_idx = all_keys.index(args.from_pref)
        targets = all_keys[start_idx:]
        log(f"{args.from_pref} から再開します（残り {len(targets)} 県）")
    elif args.all:
        targets = list(PREFECTURES.keys())
    elif args.prefs:
        targets = args.prefs
    else:
        parser.print_help(); sys.exit(1)

    unknown = [p for p in targets if p not in PREFECTURES]
    if unknown:
        print(f"不明な県名: {unknown}"); sys.exit(1)

    log(f"対象: {targets}")
    processed = []

    for pref_key in targets:
        log(f"\n{'='*50}\n{PREFECTURES[pref_key]} ({pref_key})\n{'='*50}")
        munis = fetch_municipalities(pref_key)
        if not munis:
            log(f"{pref_key}: スキップ"); continue

        ok_count, failed = 0, []
        for i, muni in enumerate(munis, 1):
            log(f"[{i}/{len(munis)}]")
            if process_municipality(pref_key, muni, args.dry_run):
                ok_count += 1
            else:
                failed.append(muni["name_ja"])
            time.sleep(MUNICIPALITY_PAUSE)

        log(f"{pref_key}: {ok_count}/{len(munis)} 完了")
        if failed: log(f"失敗: {failed}")
        if ok_count > 0:
            processed.append(pref_key)
            update_master_index(processed)
            upload_pref(pref_key, args.dry_run)

    log("完了")

if __name__ == "__main__":
    main()
