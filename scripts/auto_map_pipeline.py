#!/usr/bin/env python3
"""
GapLess マップデータ自動パイプライン
Overpass API からデータ取得 → compress.py → update_index.py → git push
を全エリア分、ブラウザ操作なしで自動実行する。

使い方:
  # 特定エリアのみ
  python3 auto_map_pipeline.py miyagi_sendai hokkaido_sapporo

  # 全エリア（47都道府県 + 既存エリア）
  python3 auto_map_pipeline.py --all

  # ドライラン（git pushしない）
  python3 auto_map_pipeline.py --all --dry-run
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# ─────────────────────────────────────────────
# 設定
# ─────────────────────────────────────────────
SCRIPTS_DIR = os.path.expanduser("~/Desktop/GapLess/scripts")
DATA_DIR    = os.path.expanduser("~/Desktop/GapLess/data")
OUTPUT_DIR  = os.path.join(SCRIPTS_DIR, "output")   # compress.py の出力先
OVERPASS_URL = "https://overpass-api.de/api/interpreter"
OVERPASS_TIMEOUT = 180
REQUEST_INTERVAL = 5   # Overpass への連続リクエスト間隔（秒）

# ─────────────────────────────────────────────
# エリア定義（PDFの座標一覧）
# ─────────────────────────────────────────────
AREAS = {
    "hokkaido_sapporo":    (43.00, 141.25, 43.15, 141.45),
    "aomori_aomori":       (40.75, 140.65, 40.90, 140.80),
    "iwate_morioka":       (39.65, 141.10, 39.80, 141.25),
    "miyagi_sendai":       (38.20, 140.80, 38.35, 141.00),
    "akita_akita":         (39.68, 140.05, 39.78, 140.20),
    "yamagata_yamagata":   (38.22, 140.30, 38.32, 140.45),
    "fukushima_fukushima": (37.70, 140.40, 37.80, 140.55),
    "ibaraki_mito":        (36.33, 140.40, 36.43, 140.55),
    "tochigi_utsunomiya":  (36.52, 139.83, 36.62, 139.98),
    "gunma_maebashi":      (36.37, 139.00, 36.47, 139.15),
    "saitama_saitama":     (35.85, 139.60, 35.95, 139.75),
    "chiba_chiba":         (35.57, 140.05, 35.67, 140.20),
    "tokyo_center":        (35.60, 139.60, 35.75, 139.85),
    "kanagawa_yokohama":   (35.40, 139.60, 35.55, 139.75),
    "niigata_niigata":     (37.85, 138.95, 37.95, 139.10),
    "toyama_toyama":       (36.65, 137.15, 36.75, 137.30),
    "ishikawa_kanazawa":   (36.53, 136.60, 36.63, 136.75),
    "fukui_fukui":         (36.03, 136.17, 36.13, 136.32),
    "yamanashi_kofu":      (35.63, 138.53, 35.73, 138.68),
    "nagano_nagano":       (36.62, 138.13, 36.72, 138.28),
    "shizuoka_shizuoka":   (34.93, 138.35, 35.03, 138.50),
    "aichi_nagoya":        (35.10, 136.80, 35.25, 137.00),
    "mie_tsu":             (34.68, 136.48, 34.78, 136.63),
    "shiga_otsu":          (34.98, 135.83, 35.08, 135.98),
    "kyoto_kyoto":         (34.95, 135.68, 35.10, 135.83),
    "osaka_osaka":         (34.60, 135.40, 34.75, 135.60),
    "hyogo_kobe":          (34.65, 135.13, 34.75, 135.28),
    "nara_nara":           (34.65, 135.78, 34.75, 135.93),
    "wakayama_wakayama":   (34.20, 135.13, 34.30, 135.28),
    "tottori_tottori":     (35.48, 134.18, 35.58, 134.33),
    "shimane_matsue":      (35.45, 133.03, 35.55, 133.18),
    "okayama_okayama":     (34.63, 133.88, 34.73, 134.03),
    "hiroshima_hiroshima": (34.35, 132.40, 34.45, 132.55),
    "yamaguchi_yamaguchi": (34.15, 131.43, 34.25, 131.58),
    "tokushima_tokushima": (34.05, 134.50, 34.15, 134.65),
    "kagawa_takamatsu":    (34.30, 134.00, 34.40, 134.15),
    "ehime_matsuyama":     (33.80, 132.68, 33.90, 132.83),
    "kochi_kochi":         (33.53, 133.48, 33.63, 133.63),
    "fukuoka_fukuoka":     (33.50, 130.30, 33.70, 130.50),
    "saga_saga":           (33.23, 130.25, 33.33, 130.40),
    "nagasaki_nagasaki":   (32.70, 129.83, 32.80, 129.98),
    "kumamoto_kumamoto":   (32.73, 130.65, 32.83, 130.80),
    "oita_oita":           (33.20, 131.55, 33.30, 131.70),
    "miyazaki_miyazaki":   (31.88, 131.38, 31.98, 131.53),
    "kagoshima_kagoshima": (31.55, 130.50, 31.65, 130.65),
    "okinawa_naha":        (26.18, 127.63, 26.28, 127.78),
    "osaki":            (38.30, 140.60, 38.90, 141.20),
    "thailand":            ( 6.40,  99.50,  7.10, 100.40),
}

# ─────────────────────────────────────────────
# Overpass クエリテンプレート
# ─────────────────────────────────────────────
ROADS_QUERY = """\
[out:json][timeout:{timeout}];
(
  way["highway"]["highway"!~"footway|steps|path|cycleway|service|track|proposed|construction|motorway|motorway_link"]
  ({min_lat},{min_lng},{max_lat},{max_lng});
);
out body;
>;
out skel qt;
"""

POI_QUERY = """\
[out:json][timeout:{timeout}];
(
  node["amenity"="hospital"]({min_lat},{min_lng},{max_lat},{max_lng});
  way["amenity"="hospital"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["amenity"~"shelter|community_centre"]({min_lat},{min_lng},{max_lat},{max_lng});
  way["amenity"~"school|community_centre"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["shop"="convenience"]({min_lat},{min_lng},{max_lat},{max_lng});
  node["amenity"="drinking_water"]({min_lat},{min_lng},{max_lat},{max_lng});
);
out body;
>;
out skel qt;
"""

# ─────────────────────────────────────────────
# ユーティリティ
# ─────────────────────────────────────────────
def log(msg: str):
    print(f"[pipeline] {msg}", flush=True)


def run(cmd: list[str], cwd: str | None = None) -> bool:
    """コマンドを実行し、失敗なら False を返す。"""
    log(f"$ {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd)
    if result.returncode != 0:
        log(f"ERROR: コマンド失敗 (exit {result.returncode})")
        return False
    return True


def overpass_to_geojson(query: str, retries: int = 3) -> dict | None:
    """Overpass API を叩いて GeoJSON 形式に変換して返す。"""
    data = urllib.parse.urlencode({"data": query}).encode()
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(
                OVERPASS_URL,
                data=data,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
            with urllib.request.urlopen(req, timeout=OVERPASS_TIMEOUT + 30) as resp:
                raw = json.loads(resp.read().decode("utf-8"))
            return osm_to_geojson(raw)
        except urllib.error.HTTPError as e:
            log(f"HTTP {e.code} (試行 {attempt}/{retries})")
            if e.code == 429:
                time.sleep(60)  # Too Many Requests → 60秒待つ
        except Exception as e:
            log(f"リクエスト失敗: {e} (試行 {attempt}/{retries})")
        time.sleep(REQUEST_INTERVAL * attempt)
    return None


def osm_to_geojson(osm: dict) -> dict:
    """Overpass JSON → GeoJSON Feature Collection に変換する。"""
    nodes: dict[int, tuple[float, float]] = {}
    features = []

    for el in osm.get("elements", []):
        if el["type"] == "node":
            nodes[el["id"]] = (el["lon"], el["lat"])

    for el in osm.get("elements", []):
        props = el.get("tags", {})
        props["osm_id"] = el["id"]

        if el["type"] == "node":
            features.append({
                "type": "Feature",
                "properties": props,
                "geometry": {"type": "Point", "coordinates": [el["lon"], el["lat"]]},
            })
        elif el["type"] == "way":
            coords = [nodes[nid] for nid in el.get("nodes", []) if nid in nodes]
            if len(coords) >= 2:
                features.append({
                    "type": "Feature",
                    "properties": props,
                    "geometry": {"type": "LineString", "coordinates": coords},
                })

    return {"type": "FeatureCollection", "features": features}


# ─────────────────────────────────────────────
# メイン処理
# ─────────────────────────────────────────────
def process_area(area_name: str, coords: tuple, dry_run: bool) -> bool:
    min_lat, min_lng, max_lat, max_lng = coords
    log(f"=== {area_name} 開始 ({min_lat},{min_lng} → {max_lat},{max_lng}) ===")
    os.makedirs(DATA_DIR, exist_ok=True)

    # --- Step 1: 道路データ取得 ---
    roads_path = os.path.join(DATA_DIR, f"{area_name}_roads_raw.geojson")
    if os.path.exists(roads_path):
        log(f"道路データはキャッシュを使用: {roads_path}")
    else:
        log("Overpass API から道路データを取得中...")
        query = ROADS_QUERY.format(
            timeout=OVERPASS_TIMEOUT,
            min_lat=min_lat, min_lng=min_lng, max_lat=max_lat, max_lng=max_lng,
        )
        geojson = overpass_to_geojson(query)
        if geojson is None:
            log("道路データの取得に失敗。スキップします。")
            return False
        with open(roads_path, "w", encoding="utf-8") as f:
            json.dump(geojson, f)
        log(f"保存: {roads_path} ({len(geojson['features'])} features)")
        time.sleep(REQUEST_INTERVAL)

    # --- Step 2: POI データ取得 ---
    poi_path = os.path.join(DATA_DIR, f"{area_name}_poi_raw.geojson")
    if os.path.exists(poi_path):
        log(f"POIデータはキャッシュを使用: {poi_path}")
    else:
        log("Overpass API から POI データを取得中...")
        query = POI_QUERY.format(
            timeout=OVERPASS_TIMEOUT,
            min_lat=min_lat, min_lng=min_lng, max_lat=max_lat, max_lng=max_lng,
        )
        geojson = overpass_to_geojson(query)
        if geojson is None:
            log("POIデータの取得に失敗。スキップします。")
            return False
        with open(poi_path, "w", encoding="utf-8") as f:
            json.dump(geojson, f)
        log(f"保存: {poi_path} ({len(geojson['features'])} features)")
        time.sleep(REQUEST_INTERVAL)

    # --- Step 3: 圧縮スクリプト実行 ---
    ok = run(
        ["python3", "compress.py", f"../data/{area_name}_roads_raw.geojson", f"{area_name}_roads", "roads"],
        cwd=SCRIPTS_DIR,
    )
    if not ok:
        return False

    ok = run(
        ["python3", "compress.py", f"../data/{area_name}_poi_raw.geojson", f"{area_name}_poi", "poi"],
        cwd=SCRIPTS_DIR,
    )
    if not ok:
        return False

    ok = run(
        ["python3", "update_index.py", area_name,
         str(min_lat), str(min_lng), str(max_lat), str(max_lng)],
        cwd=SCRIPTS_DIR,
    )
    if not ok:
        return False

    log(f"{area_name} 圧縮完了")
    return True


def git_push(area_names: list[str], dry_run: bool):
    """生成した .gplb.gz と index.json を git push する。"""
    if dry_run:
        log("[dry-run] git push をスキップします")
        return

    # output/ フォルダのパスを確認
    if not os.path.isdir(OUTPUT_DIR):
        log(f"output ディレクトリが見つかりません: {OUTPUT_DIR}")
        return

    files_to_add = []
    for name in area_names:
        for suffix in ["_roads.gplb.gz", "_poi.gplb.gz"]:
            p = os.path.join(OUTPUT_DIR, name + suffix)
            if os.path.exists(p):
                files_to_add.append(p)

    index_path = os.path.join(OUTPUT_DIR, "index.json")
    if os.path.exists(index_path):
        files_to_add.append(index_path)

    if not files_to_add:
        log("push するファイルが見つかりません")
        return

    repo_dir = os.path.dirname(OUTPUT_DIR) if "output" in OUTPUT_DIR else OUTPUT_DIR

    run(["git", "add"] + files_to_add, cwd=repo_dir)
    commit_msg = f"Add map data: {', '.join(area_names)}"
    run(["git", "commit", "-m", commit_msg], cwd=repo_dir)
    run(["git", "push", "origin", "main"], cwd=repo_dir)
    log("git push 完了")


def main():
    parser = argparse.ArgumentParser(description="GapLess マップデータ自動パイプライン")
    parser.add_argument("areas", nargs="*", help="処理するエリア名（省略時は --all が必要）")
    parser.add_argument("--all", action="store_true", help="全エリアを処理する")
    parser.add_argument("--dry-run", action="store_true", help="git push をしない")
    parser.add_argument("--list", action="store_true", help="利用可能なエリア一覧を表示")
    args = parser.parse_args()

    if args.list:
        for name, coords in AREAS.items():
            print(f"  {name:30s} {coords}")
        return

    if args.all:
        targets = list(AREAS.keys())
    elif args.areas:
        unknown = [a for a in args.areas if a not in AREAS]
        if unknown:
            print(f"不明なエリア名: {unknown}")
            print("利用可能な名前を確認: python3 auto_map_pipeline.py --list")
            sys.exit(1)
        targets = args.areas
    else:
        parser.print_help()
        sys.exit(1)

    log(f"処理対象: {targets}")
    succeeded = []
    failed = []

    for area_name in targets:
        coords = AREAS[area_name]
        ok = process_area(area_name, coords, args.dry_run)
        if ok:
            succeeded.append(area_name)
        else:
            failed.append(area_name)

    if succeeded:
        git_push(succeeded, args.dry_run)

    log(f"完了: {len(succeeded)} 成功 / {len(failed)} 失敗")
    if failed:
        log(f"失敗したエリア: {failed}")


if __name__ == "__main__":
    main()
