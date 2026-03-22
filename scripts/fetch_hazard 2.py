#!/usr/bin/env python3
# ============================================================
# fetch_hazard.py
# 国土数値情報（国土交通省）から各都道府県の洪水浸水想定区域データを取得し、
# GeoJSON に変換してから compress.py（hazard モード）に渡す。
#
# 使い方:
#   python3 fetch_hazard.py tokyo
#   python3 fetch_hazard.py miyagi hokkaido
#   python3 fetch_hazard.py --all
#   python3 fetch_hazard.py --list
#   python3 fetch_hazard.py tokyo --dry-run
# ============================================================

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
import urllib.error
import urllib.parse
import zipfile
import xml.etree.ElementTree as ET

# ─────────────────────────────────────────────
# 設定
# ─────────────────────────────────────────────
SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR    = os.path.expanduser("~/Desktop/GapLess/data")
OUTPUT_DIR  = os.path.normpath(os.path.join(SCRIPTS_DIR, "..", "maps"))
CACHE_DIR   = os.path.join(DATA_DIR, "hazard_cache")

OVERPASS_TIMEOUT = 180
OVERPASS_URL = "https://overpass-api.de/api/interpreter"

MUNICIPALITIES_QUERY = """\
[out:json][timeout:120];
area["admin_level"="4"]["name"="{pref_ja}"]->.pref;
(
  relation["admin_level"="7"]["boundary"="administrative"](area.pref);
  relation["admin_level"="8"]["boundary"="administrative"](area.pref);
);
out bb tags;
"""

# ─────────────────────────────────────────────
# 都道府県定義
# code: 国土数値情報の都道府県コード（2桁ゼロ埋め）
# ─────────────────────────────────────────────
PREFECTURES = {
    "hokkaido":  {"code": "01", "ja": "北海道"},
    "aomori":    {"code": "02", "ja": "青森県"},
    "iwate":     {"code": "03", "ja": "岩手県"},
    "miyagi":    {"code": "04", "ja": "宮城県"},
    "akita":     {"code": "05", "ja": "秋田県"},
    "yamagata":  {"code": "06", "ja": "山形県"},
    "fukushima": {"code": "07", "ja": "福島県"},
    "ibaraki":   {"code": "08", "ja": "茨城県"},
    "tochigi":   {"code": "09", "ja": "栃木県"},
    "gunma":     {"code": "10", "ja": "群馬県"},
    "saitama":   {"code": "11", "ja": "埼玉県"},
    "chiba":     {"code": "12", "ja": "千葉県"},
    "tokyo":     {"code": "13", "ja": "東京都"},
    "kanagawa":  {"code": "14", "ja": "神奈川県"},
    "niigata":   {"code": "15", "ja": "新潟県"},
    "toyama":    {"code": "16", "ja": "富山県"},
    "ishikawa":  {"code": "17", "ja": "石川県"},
    "fukui":     {"code": "18", "ja": "福井県"},
    "yamanashi": {"code": "19", "ja": "山梨県"},
    "nagano":    {"code": "20", "ja": "長野県"},
    "shizuoka":  {"code": "22", "ja": "静岡県"},
    "aichi":     {"code": "23", "ja": "愛知県"},
    "mie":       {"code": "24", "ja": "三重県"},
    "shiga":     {"code": "25", "ja": "滋賀県"},
    "kyoto":     {"code": "26", "ja": "京都府"},
    "osaka":     {"code": "27", "ja": "大阪府"},
    "hyogo":     {"code": "28", "ja": "兵庫県"},
    "nara":      {"code": "29", "ja": "奈良県"},
    "wakayama":  {"code": "30", "ja": "和歌山県"},
    "tottori":   {"code": "31", "ja": "鳥取県"},
    "shimane":   {"code": "32", "ja": "島根県"},
    "okayama":   {"code": "33", "ja": "岡山県"},
    "hiroshima": {"code": "34", "ja": "広島県"},
    "yamaguchi": {"code": "35", "ja": "山口県"},
    "tokushima": {"code": "36", "ja": "徳島県"},
    "kagawa":    {"code": "37", "ja": "香川県"},
    "ehime":     {"code": "38", "ja": "愛媛県"},
    "kochi":     {"code": "39", "ja": "高知県"},
    "fukuoka":   {"code": "40", "ja": "福岡県"},
    "saga":      {"code": "41", "ja": "佐賀県"},
    "nagasaki":  {"code": "42", "ja": "長崎県"},
    "kumamoto":  {"code": "43", "ja": "熊本県"},
    "oita":      {"code": "44", "ja": "大分県"},
    "miyazaki":  {"code": "45", "ja": "宮崎県"},
    "kagoshima": {"code": "46", "ja": "鹿児島県"},
    "okinawa":   {"code": "47", "ja": "沖縄県"},
}

# 浸水深ランク → risk_level
# A31 v3.0版: waterDepth の値は数値コード or 文字列
DEPTH_TO_RISK = {
    "1": "low", "2": "low",
    "3": "medium", "4": "medium",
    "5": "high", "6": "high", "7": "high",
}

# waterDepth の文字列値マッピング（v3版）
WATER_DEPTH_STR = {
    "0.5m未満":   "low",
    "0.5m～1m":   "low",
    "1m～2m":     "medium",
    "2m～3m":     "medium",
    "3m～5m":     "high",
    "5m以上":     "high",
    "5m～10m":    "high",
    "10m以上":    "high",
}


# ─────────────────────────────────────────────
# ユーティリティ
# ─────────────────────────────────────────────
def log(msg: str):
    print(f"[hazard] {msg}", flush=True)


def run(cmd: list, cwd: str = None) -> bool:
    log(f"$ {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd)
    if result.returncode != 0:
        log(f"ERROR: exit {result.returncode}")
        return False
    return True


# ─────────────────────────────────────────────
# ダウンロード
# ─────────────────────────────────────────────
def find_download_url(pref_code: str) -> str | None:
    """
    国土数値情報 A31（洪水浸水想定区域）の ZIP URL を返す。
    URLパターンを順番に試して存在するものを返す。
    """
    # 試すURLパターン（新しい版から順に）
    candidates = [
        # 第4.0版パターン（2022年度）
        f"https://nlftp.mlit.go.jp/ksj/gml/data/A31/A31-22/A31-22_{pref_code}_GML.zip",
        f"https://nlftp.mlit.go.jp/ksj/gml/data/A31/A31-21/A31-21_{pref_code}_GML.zip",
        # 第3.0版パターン（2021年度）
        f"https://nlftp.mlit.go.jp/ksj/gml/data/A31/A31-20/A31-20_{pref_code}_GML.zip",
        # 第2.2版パターン（2020年度）
        f"https://nlftp.mlit.go.jp/ksj/gml/data/A31/A31-19/A31-19_{pref_code}_GML.zip",
        # 第1.1版パターン（2012年度）
        f"https://nlftp.mlit.go.jp/ksj/gml/data/A31/A31-12/A31-12_{pref_code}_GML.zip",
    ]

    for url in candidates:
        log(f"URL確認中: {url}")
        try:
            req = urllib.request.Request(
                url, method="HEAD", headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                if resp.status == 200:
                    log(f"検出URL: {url}")
                    return url
        except urllib.error.HTTPError as e:
            if e.code == 404:
                continue
            log(f"HTTPエラー {e.code}: {url}")
        except Exception as e:
            log(f"確認失敗: {e}")

    return None


def download_zip(url: str, dest_path: str) -> bool:
    log(f"ダウンロード中: {url}")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=180) as resp:
            total = int(resp.headers.get("Content-Length", 0))
            data = bytearray()
            while True:
                chunk = resp.read(65536)
                if not chunk:
                    break
                data.extend(chunk)
                if total:
                    print(f"  {len(data)/1024/1024:.1f}/{total/1024/1024:.1f} MB", end="\r")
        print()
        with open(dest_path, "wb") as f:
            f.write(data)
        log(f"保存: {dest_path} ({os.path.getsize(dest_path)/1024/1024:.1f} MB)")
        return True
    except Exception as e:
        log(f"ダウンロード失敗: {e}")
        return False


# ─────────────────────────────────────────────
# GML → GeoJSON 変換
# ─────────────────────────────────────────────
def parse_pos_list(text: str) -> list:
    """gml:posList (lat lon ...) → [[lng,lat], ...] に変換する。"""
    vals = list(map(float, text.strip().split()))
    coords = []
    for i in range(0, len(vals) - 1, 2):
        lat, lng = vals[i], vals[i+1]
        coords.append([lng, lat])
    return coords


def get_risk_from_depth(depth_text: str) -> str:
    """浸水深テキストから risk_level を返す。"""
    if not depth_text:
        return "medium"
    risk = DEPTH_TO_RISK.get(depth_text.strip())
    if risk:
        return risk
    try:
        v = float(depth_text.replace("m","").split("～")[0].split("未満")[0].strip())
        if v >= 3.0: return "high"
        if v >= 1.0: return "medium"
        return "low"
    except:
        return "medium"


def gml_to_geojson(gml_path: str) -> dict:
    log(f"  GML解析: {os.path.basename(gml_path)}")
    try:
        tree = ET.parse(gml_path)
        root = tree.getroot()
    except Exception as e:
        log(f"  GML解析スキップ: {os.path.basename(gml_path)} ({e})")
        return {"type": "FeatureCollection", "features": []}

    GML   = "http://schemas.opengis.net/gml/3.2.1"
    KSJ   = "http://nlftp.mlit.go.jp/ksj/schemas/ksj-app"
    XLINK = "http://www.w3.org/1999/xlink"

    # gml:id → Surface要素 のマップ
    surface_map: dict = {}
    for el in root.iter(f"{{{GML}}}Surface"):
        gid = el.attrib.get(f"{{{GML}}}id", "")
        if gid:
            surface_map[gid] = el

    # gml:id → Curve要素 のマップ
    curve_map: dict = {}
    for el in root.iter(f"{{{GML}}}Curve"):
        gid = el.attrib.get(f"{{{GML}}}id", "")
        if gid:
            curve_map[gid] = el

    def resolve_curve(el) -> "ET.Element | None":
        """
        curveMember の直接の子、または xlink:href 参照を解決して Curve を返す。
        OrientableCurve → baseCurve[xlink:href] → Curve も対応。
        """
        # 直接 xlink:href を持つ場合（A31-10型）
        href = el.attrib.get(f"{{{XLINK}}}href", "")
        if href.startswith("#"):
            return curve_map.get(href[1:])

        # 子要素に OrientableCurve がある場合（A31-20型）
        for child in el:
            local = child.tag.split("}")[-1] if "}" in child.tag else child.tag
            if local == "OrientableCurve":
                base = child.find(f"{{{GML}}}baseCurve")
                if base is not None:
                    href2 = base.attrib.get(f"{{{XLINK}}}href", "")
                    if href2.startswith("#"):
                        return curve_map.get(href2[1:])
            elif local == "Curve":
                return child

        return None

    def get_ring_coords(ring_elem) -> list | None:
        """Ring → curveMember → Curve → posList の順で座標を取得する。"""
        all_coords = []
        for cm in ring_elem.findall(f"{{{GML}}}curveMember"):
            curve = resolve_curve(cm)
            if curve is None:
                continue
            pos_el = curve.find(f".//{{{GML}}}posList")
            if pos_el is not None and pos_el.text:
                all_coords.extend(parse_pos_list(pos_el.text))
        return all_coords if len(all_coords) >= 3 else None

    def get_polygon_from_surface(surf_elem) -> list | None:
        """
        Surface → patches → PolygonPatch から外周・内周リングを取得する。
        戻り値: GeoJSON Polygon の coordinates 形式 [[外周], [内周1], ...]
        """
        rings = []
        for patch in surf_elem.iter(f"{{{GML}}}PolygonPatch"):
            # 外周
            ext = patch.find(f"{{{GML}}}exterior")
            if ext is not None:
                ring_el = ext.find(f"{{{GML}}}Ring")
                if ring_el is not None:
                    coords = get_ring_coords(ring_el)
                    if coords:
                        if coords[0] != coords[-1]:
                            coords.append(coords[0])
                        rings.append(coords)

            # 内周（穴）
            for interior in patch.findall(f"{{{GML}}}interior"):
                ring_el = interior.find(f"{{{GML}}}Ring")
                if ring_el is not None:
                    coords = get_ring_coords(ring_el)
                    if coords:
                        if coords[0] != coords[-1]:
                            coords.append(coords[0])
                        rings.append(coords)

        return rings if rings else None

    # 浸水深要素名候補
    depth_tag_locals = {
        "waterDepth", "A31_001", "depthRank",
        "floodDepthRank", "inundationDepth",
    }

    # 区域要素名候補
    area_tag_locals = {
        "PlanScale",      # A31-10（計画規模）
        "MaximumScale",   # A31-20（想定最大規模）
        "InundationTime", # A31-30（浸水継続時間）
        "A31", "FloodingArea", "floodingArea", "InundationArea",
    }

    features = []

    for member in root.iter():
        local = member.tag.split("}")[-1] if "}" in member.tag else member.tag
        if local not in area_tag_locals:
            continue

        # 浸水深を取得
        depth_text = None
        for child in member.iter():
            child_local = child.tag.split("}")[-1] if "}" in child.tag else child.tag
            if child_local in depth_tag_locals and child.text:
                depth_text = child.text.strip()
                break

        risk_level = get_risk_from_depth(depth_text)

        # bounds の xlink:href から Surface を取得
        surf_elem = None
        for child in member:
            child_local = child.tag.split("}")[-1] if "}" in child.tag else child.tag
            if child_local == "bounds":
                href = child.attrib.get(f"{{{XLINK}}}href", "")
                if href.startswith("#"):
                    surf_elem = surface_map.get(href[1:])
                break

        if surf_elem is None:
            continue

        rings = get_polygon_from_surface(surf_elem)
        if not rings:
            continue

        features.append({
            "type": "Feature",
            "properties": {
                "risk_level": risk_level,
                "depth_rank": depth_text or "unknown",
            },
            "geometry": {
                "type": "Polygon",
                "coordinates": rings,
            },
        })

    log(f"  フィーチャー数: {len(features)}")
    return {"type": "FeatureCollection", "features": features}


def process_zip(zip_path: str, extract_dir: str, output_geojson: str) -> bool:
    os.makedirs(extract_dir, exist_ok=True)
    log(f"ZIP展開中: {zip_path}")
    with zipfile.ZipFile(zip_path, "r") as zf:
        gml_files = [n for n in zf.namelist()
                     if (n.endswith(".xml") or n.endswith(".gml"))
                     and not os.path.basename(n).startswith("KS-META")]
        log(f"GMLファイル数: {len(gml_files)}")
        zf.extractall(extract_dir)

    all_features = []
    for gml_name in gml_files:
        gml_path = os.path.join(extract_dir, gml_name)
        if os.path.exists(gml_path):
            result = gml_to_geojson(gml_path)
            all_features.extend(result.get("features", []))

    log(f"合計フィーチャー数: {len(all_features)}")
    if not all_features:
        return False

    geojson = {"type": "FeatureCollection", "features": all_features}
    with open(output_geojson, "w", encoding="utf-8") as f:
        json.dump(geojson, f, ensure_ascii=False)
    log(f"GeoJSON保存: {output_geojson} ({os.path.getsize(output_geojson)/1024/1024:.1f} MB)")
    return True


# ─────────────────────────────────────────────
# 市区町村bboxで切り出し
# ─────────────────────────────────────────────
def fetch_municipalities(pref_key: str) -> list:
    """Overpassから市区町村のbboxリストを取得する。"""
    import re as _re
    pref_ja = PREFECTURES[pref_key]["ja"]
    query = MUNICIPALITIES_QUERY.format(pref_ja=pref_ja)
    data = urllib.parse.urlencode({"data": query}).encode()
    try:
        req = urllib.request.Request(
            OVERPASS_URL, data=data,
            headers={"Content-Type": "application/x-www-form-urlencoded"})
        with urllib.request.urlopen(req, timeout=150) as resp:
            raw = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        log(f"市区町村取得失敗: {e}")
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
        name_en = tags.get("name:en", "")
        name_ja = tags.get("name", "unknown")
        if name_en:
            slug = _re.sub(r"[^a-z0-9_]", "", _re.sub(r"\s+", "_", name_en.lower()))
        else:
            slug = _re.sub(r"[市区町村郡]$", "", _re.sub(r"[　\s]", "", name_ja))
            if _re.search(r"[^-]", slug):
                slug = f"{abs(hash(name_ja)) % 100000:05d}"
        area_name = f"{pref_key}_{slug}"
        if area_name in seen:
            continue
        seen.add(area_name)
        results.append({
            "area_name": area_name,
            "name_ja":   name_ja,
            "bbox": (bounds["minlat"], bounds["minlon"],
                     bounds["maxlat"], bounds["maxlon"]),
        })
    log(f"  市区町村数: {len(results)}")
    return results


def clip_features_to_bbox(features: list, bbox: tuple) -> list:
    """フィーチャーをbboxでクリップする（ポリゴンの重心がbbox内のものを返す）。"""
    min_lat, min_lng, max_lat, max_lng = bbox
    result = []
    for feat in features:
        geom = feat.get("geometry", {})
        coords = geom.get("coordinates", [[]])[0]
        if not coords:
            continue
        # 重心がbbox内かチェック
        lats = [c[1] for c in coords]
        lngs = [c[0] for c in coords]
        clat = sum(lats) / len(lats)
        clng = sum(lngs) / len(lngs)
        if min_lat <= clat <= max_lat and min_lng <= clng <= max_lng:
            result.append(feat)
    return result


# ─────────────────────────────────────────────
# 1県の処理
# ─────────────────────────────────────────────
def process_prefecture(pref_key: str, dry_run: bool) -> bool:
    pref      = PREFECTURES[pref_key]
    pref_code = pref["code"]
    pref_ja   = pref["ja"]

    log(f"=== {pref_ja} ({pref_key}) ===")

    os.makedirs(DATA_DIR,   exist_ok=True)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(CACHE_DIR,  exist_ok=True)

    zip_path     = os.path.join(CACHE_DIR, f"A31_{pref_code}.zip")
    extract_dir  = os.path.join(CACHE_DIR, f"extracted_{pref_code}")
    pref_geojson = os.path.join(DATA_DIR,  f"{pref_key}_hazard_raw.geojson")

    # ダウンロード
    if dry_run:
        if not os.path.exists(zip_path):
            log(f"[dry-run] キャッシュなし: {zip_path}")
            return False
        log(f"[dry-run] キャッシュ使用: {zip_path}")
    else:
        if os.path.exists(zip_path):
            log(f"キャッシュ使用: {zip_path}")
        else:
            url = find_download_url(pref_code)
            if url is None:
                log(f"{pref_ja}: URLが見つかりませんでした。")
                log(f"  保存先: {zip_path}")
                log(f"  参照:   https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-A31.html")
                return False
            ok = download_zip(url, zip_path)
            if not ok:
                return False

    # 県全体のGeoJSON変換
    if os.path.exists(pref_geojson):
        log(f"GeoJSONキャッシュ使用: {pref_geojson}")
        with open(pref_geojson, encoding="utf-8") as f:
            pref_data = json.load(f)
    else:
        ok = process_zip(zip_path, extract_dir, pref_geojson)
        if not ok:
            log(f"{pref_ja}: GeoJSON変換失敗")
            return False
        with open(pref_geojson, encoding="utf-8") as f:
            pref_data = json.load(f)

    all_features = pref_data.get("features", [])
    log(f"  全フィーチャー数: {len(all_features)}")

    # 市区町村リストを取得してbboxで切り出し
    log("  市区町村リストをOverpassから取得中...")
    munis = fetch_municipalities(pref_key)

    compress_script = os.path.join(SCRIPTS_DIR, "compress.py")
    produced_files = []

    for muni in munis:
        area_name = muni["area_name"]
        bbox      = muni["bbox"]

        # bboxでフィーチャーを切り出し
        clipped = clip_features_to_bbox(all_features, bbox)
        if not clipped:
            continue

        # 市区町村単位のGeoJSONを保存
        muni_geojson = os.path.join(DATA_DIR, f"{area_name}_hazard_raw.geojson")
        with open(muni_geojson, "w", encoding="utf-8") as f:
            json.dump({"type": "FeatureCollection", "features": clipped},
                      f, ensure_ascii=False)

        log(f"  {area_name}: {len(clipped)}件")

        # GPLH変換
        ok = run(["python3", compress_script,
                  muni_geojson, f"{area_name}_hazard", "hazard"],
                 cwd=SCRIPTS_DIR)
        if not ok:
            log(f"  {area_name}: compress.py 失敗")
            continue

        gplh_gz = os.path.join(OUTPUT_DIR, f"{area_name}_hazard.gplh.gz")
        if os.path.exists(gplh_gz):
            produced_files.append({
                "area_name": area_name,
                "gplh_gz":   gplh_gz,
                "pref_key":  pref_key,
            })

        # 一時GeoJSONを削除
        if os.path.exists(muni_geojson):
            os.remove(muni_geojson)

    log(f"  生成ファイル数: {len(produced_files)}")
    return produced_files if produced_files else False


# ─────────────────────────────────────────────
# git push
# ─────────────────────────────────────────────
# 地方区分（アップロードパス解決用）
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


def upload_hazard(produced_files: list, pref_key: str, dry_run: bool):
    """
    produced_files: process_prefecture の戻り値
    各要素: {"area_name", "gplh_gz", "geojson_gz", "pref_key"}
    アップロード先:
      pref_key/{area_name}_hazard.gplh.gz
      pref_key/{area_name}_hazard_raw.geojson.gz
    """
    from github_upload import upload_files
    pairs = []
    for item in produced_files:
        pk = item["pref_key"]
        if os.path.exists(item["gplh_gz"]):
            pairs.append((item["gplh_gz"], f"{pk}/{os.path.basename(item['gplh_gz'])}"))

    index_path = os.path.join(OUTPUT_DIR, "index.json")
    if os.path.exists(index_path):
        pairs.append((index_path, "index.json"))

    if not pairs:
        log("アップロードするファイルがありません")
        return

    if dry_run:
        log(f"[dry-run] アップロードをスキップ ({len(pairs)} ファイル)")
        return

    ok, ng = upload_files(pairs, commit_prefix=f"Add hazard data: {pref_key}")
    log(f"アップロード完了: {ok} 成功 / {ng} 失敗")



# ─────────────────────────────────────────────
# メイン
# ─────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="GapLess 洪水ハザードデータ 都道府県別取得・変換")
    parser.add_argument("prefs", nargs="*",
                        help="処理する都道府県の英語名（例: tokyo miyagi）")
    parser.add_argument("--all",          action="store_true", help="47都道府県すべて処理")
    parser.add_argument("--dry-run",      action="store_true", help="ダウンロードせずキャッシュで変換のみ")
    parser.add_argument("--geojson-only", action="store_true", help="GeoJSON生成までで終了")
    parser.add_argument("--list",         action="store_true", help="都道府県一覧を表示")
    parser.add_argument("--from", dest="from_pref", metavar="PREF", help="指定した県から残りを実行（途中再開用）")
    args = parser.parse_args()

    if args.list:
        print(f"{'英語名':20s} {'コード':6s} 日本語名")
        print("-" * 40)
        for k, v in PREFECTURES.items():
            print(f"{k:20s} {v['code']:6s} {v['ja']}")
        return

    if args.from_pref:
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
        parser.print_help()
        sys.exit(1)

    unknown = [p for p in targets if p not in PREFECTURES]
    if unknown:
        print(f"不明な都道府県名: {unknown}")
        print("python3 fetch_hazard.py --list で一覧確認")
        sys.exit(1)

    log(f"対象: {targets}")
    succeeded = []
    failed    = []

    for pref_key in targets:
        ok = process_prefecture(pref_key, args.dry_run)
        if ok:
            succeeded.append(pref_key)
        else:
            failed.append(pref_key)
        # 連続ダウンロードの間隔
        if not args.dry_run and len(targets) > 1:
            time.sleep(3)

    if succeeded and not args.geojson_only:
        upload_hazard(succeeded, args.dry_run)

    log(f"\n完了: {len(succeeded)} 成功 / {len(failed)} 失敗")
    if failed:
        log(f"失敗した県: {failed}")
        log("失敗した県は手動でZIPをダウンロードして --dry-run で再実行できます")
        log("参照: https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-A31.html")


if __name__ == "__main__":
    main()
