#!/usr/bin/env python3
# ============================================================
# compress.py  v2
# GeoJSONをGPLBバイナリに変換してgzip圧縮するスクリプト
#
# 使い方:
#   python3 compress.py <入力GeoJSON> <出力名> <種別> [出力先ディレクトリ]
#
# 例:
#   python3 compress.py tokyo_raw.geojson tokyo roads
#   python3 compress.py tokyo_poi.geojson tokyo_poi poi
#   python3 compress.py tokyo_hazard.geojson tokyo_hazard hazard
#   python3 compress.py tokyo_hazard.geojson tokyo_hazard hazard ../output/tokyo
#
# 種別:
#   roads  → 道路データ（GPLB v3: 交差点抽出+Douglas-Peucker+デルタ符号化）
#   poi    → POIデータ（GPLB v2: 避難所・病院・コンビニ・スーパー等）
#   hazard → ハザードゾーン（GPLH v3: Douglas-Peucker+デルタ符号化）
#
# v1からの変更点:
#   - POI: emergency=assembly_point / disaster=evacuation_site を避難所として取得
#   - POI: amenity=vending_machine["vending"="water"] を給水所(32)として取得
#   - hazard: Douglas-Peucker でポリゴン間引き追加（GPLH v3）
#   - hazard: デルタ符号化追加（GPLH v3）→ v2比で約50%削減
#   - 出力先ディレクトリを第4引数で指定可能
#   - デルタ値がオーバーフローする座標を検出してログ出力
# ============================================================

import sys
import json
import gzip
import struct
import math
import os

# ────────────────────────────────────────
# 道路種別マッピング
# ────────────────────────────────────────
ROAD_KEEP = {
    'residential':   1, 'unclassified':  2, 'tertiary':      3,
    'secondary':     4, 'primary':        5, 'trunk':          6,
    'pedestrian':    7, 'living_street':  8, 'secondary_link': 9,
    'tertiary_link': 10,'primary_link':  11, 'trunk_link':    12,
}

# amenity / shop タグの値 → POIタイプID
POI_TYPE_MAP = {
    'shelter':          20,
    'school':           21,
    'community_centre': 22,
    'townhall':         22,
    'hospital':         40,
    'clinic':           40,
    'convenience':      30,
    'supermarket':      31,
    'drinking_water':   32,
    'vending_machine':  33,
    'fuel':             34,
}

# ────────────────────────────────────────
# POIタイプ判定（v2: 複数タグに対応）
# ────────────────────────────────────────
def get_poi_type(props: dict) -> int | None:
    """
    OSM タグから GapLess の POI タイプ ID を返す。
    見つからなければ None。

    優先順位:
      1. emergency=assembly_point / disaster=evacuation_site → 20（避難所）
      2. amenity タグ → POI_TYPE_MAP で照合
      3. shop タグ → POI_TYPE_MAP で照合
      4. amenity=vending_machine かつ vending=water → 32（給水所）に上書き
    """
    # 避難所系の専用タグ（amenityタグがなくても避難所として扱う）
    emergency = props.get('emergency', '')
    disaster  = props.get('disaster', '')
    if emergency == 'assembly_point' or disaster == 'evacuation_site':
        return 20

    amenity = props.get('amenity', '')
    shop    = props.get('shop', '')

    # 自動販売機は vending=water の場合のみ給水所(32)として扱う
    if amenity == 'vending_machine':
        return 32 if props.get('vending', '') == 'water' else None

    poi_type = POI_TYPE_MAP.get(amenity) or POI_TYPE_MAP.get(shop)
    return poi_type


# ────────────────────────────────────────
# Douglas-Peucker（座標の間引き）
# ────────────────────────────────────────
def point_line_dist(p, a, b):
    if a == b:
        return math.hypot(p[0]-a[0], p[1]-a[1])
    dx, dy = b[0]-a[0], b[1]-a[1]
    t = ((p[0]-a[0])*dx + (p[1]-a[1])*dy) / (dx*dx + dy*dy)
    t = max(0, min(1, t))
    return math.hypot(p[0]-a[0]-t*dx, p[1]-a[1]-t*dy)

def douglas_peucker(coords, epsilon=0.00005):
    if len(coords) <= 2:
        return coords
    dmax, idx = 0, 0
    for i in range(1, len(coords)-1):
        d = point_line_dist(coords[i], coords[0], coords[-1])
        if d > dmax:
            dmax, idx = d, i
    if dmax > epsilon:
        left  = douglas_peucker(coords[:idx+1], epsilon)
        right = douglas_peucker(coords[idx:], epsilon)
        return left[:-1] + right
    return [coords[0], coords[-1]]


# ────────────────────────────────────────
# 道路データの変換（GPLB v3: 変更なし）
# ────────────────────────────────────────
def convert_roads(features):
    node_ref_count = {}
    way_nodes = []
    for feat in features:
        hw = feat['properties'].get('highway', '')
        if hw not in ROAD_KEEP:
            continue
        coords = feat['geometry']['coordinates']
        if feat['geometry']['type'] != 'LineString':
            continue
        keys = [f"{c[0]:.6f},{c[1]:.6f}" for c in coords]
        way_nodes.append((hw, feat['properties'], coords, keys))
        for k in keys:
            node_ref_count[k] = node_ref_count.get(k, 0) + 1

    intersection_keys = {k for k,v in node_ref_count.items() if v >= 2}

    segments = []
    total_before = total_after = 0
    delta_clips = 0
    for hw, props, coords, keys in way_nodes:
        type_id = ROAD_KEEP[hw]
        try:
            w = float(props.get('width', 0) or 0)
        except:
            w = 0
        width_byte = min(255, int(w * 10))
        seg_start = 0
        for i in range(1, len(coords)):
            is_end = (i == len(coords)-1) or (keys[i] in intersection_keys)
            if is_end:
                seg = coords[seg_start:i+1]
                total_before += len(seg)
                seg = douglas_peucker(seg)
                total_after += len(seg)
                if len(seg) >= 2:
                    segments.append((type_id, width_byte, seg))
                seg_start = i

    buf = bytearray()
    buf += b'GPLB'
    buf += struct.pack('B', 3)
    buf += struct.pack('<I', len(segments))
    for type_id, width_byte, coords in segments:
        buf += struct.pack('B', 1)
        buf += struct.pack('B', type_id)
        buf += struct.pack('B', width_byte)
        buf += struct.pack('<H', len(coords))
        buf += struct.pack('<i', int(coords[0][0] * 1e6))
        buf += struct.pack('<i', int(coords[0][1] * 1e6))
        prev_lng = int(coords[0][0] * 1e6)
        prev_lat = int(coords[0][1] * 1e6)
        for lng, lat in coords[1:]:
            cur_lng = int(lng * 1e6)
            cur_lat = int(lat * 1e6)
            dlng = cur_lng - prev_lng
            dlat = cur_lat - prev_lat
            if abs(dlng) > 32767 or abs(dlat) > 32767:
                delta_clips += 1
            buf += struct.pack('<h', max(-32767, min(32767, dlng)))
            buf += struct.pack('<h', max(-32767, min(32767, dlat)))
            prev_lng, prev_lat = cur_lng, cur_lat

    print(f'  道路セグメント数: {len(segments)}')
    print(f'  座標点数: {total_before:,} → {total_after:,} ({(1-total_after/max(total_before,1))*100:.0f}%削減)')
    if delta_clips > 0:
        print(f'  WARNING: デルタオーバーフロー {delta_clips} 箇所（エリアが広すぎる可能性）')
    return bytes(buf)


# ────────────────────────────────────────
# POIデータの変換（GPLB v2: タイプ判定拡充）
# ────────────────────────────────────────
def get_center(geom):
    if geom['type'] == 'Point':
        lng, lat = geom['coordinates']
        return lat, lng
    elif geom['type'] == 'Polygon':
        coords = geom['coordinates'][0]
        return sum(c[1] for c in coords)/len(coords), sum(c[0] for c in coords)/len(coords)
    elif geom['type'] == 'MultiPolygon':
        coords = geom['coordinates'][0][0]
        return sum(c[1] for c in coords)/len(coords), sum(c[0] for c in coords)/len(coords)
    return None, None

def convert_poi(features):
    buf = bytearray()
    buf += b'GPLB'
    buf += struct.pack('B', 2)

    pois = []
    skipped_types = {}
    for feat in features:
        props = feat.get('properties', {})
        geom  = feat.get('geometry', {})

        poi_type = get_poi_type(props)
        if poi_type is None:
            # デバッグ用：認識できなかったタグを集計
            key = props.get('amenity') or props.get('shop') or props.get('emergency') or '(unknown)'
            skipped_types[key] = skipped_types.get(key, 0) + 1
            continue

        lat, lng = get_center(geom)
        if lat is None:
            continue

        name = props.get('name:ja') or props.get('name') or ''
        name_bytes = name[:20].encode('utf-8')[:40]
        pois.append((poi_type, lat, lng, name_bytes))

    buf += struct.pack('<I', len(pois))
    for poi_type, lat, lng, name_bytes in pois:
        buf += struct.pack('B', poi_type)
        buf += struct.pack('<i', int(lat * 1e6))
        buf += struct.pack('<i', int(lng * 1e6))
        buf += struct.pack('<H', 0)
        buf += struct.pack('B', 0)
        buf += struct.pack('B', len(name_bytes))
        buf += name_bytes

    # タイプ別の内訳を表示
    type_labels = {20:'避難所',21:'学校',22:'公共施設',30:'コンビニ',31:'スーパー',
                   32:'給水所',33:'自販機',34:'ガソリンスタンド',40:'病院'}
    counts = {}
    for poi_type, *_ in pois:
        counts[poi_type] = counts.get(poi_type, 0) + 1
    print(f'  POI件数: {len(pois)}')
    for t, c in sorted(counts.items()):
        print(f'    {type_labels.get(t, f"type{t}")}: {c}')
    if skipped_types:
        top = sorted(skipped_types.items(), key=lambda x: -x[1])[:5]
        print(f'  スキップ（未対応タグ）: {dict(top)}')
    return bytes(buf)


# ────────────────────────────────────────
# ハザードデータの変換（GPLH v3: DP+デルタ符号化）
# ────────────────────────────────────────
# GPLH v3 フォーマット:
#   マジック:     b'GPLH'
#   バージョン:   0x03
#   ポリゴン数:   uint32
#   各ポリゴン:
#     haz_type:   uint8  （1=洪水）
#     risk_level: uint8  （1=high, 2=medium, 3=low）
#     点数:       uint16
#     先頭lat:    int32  （×1e6）
#     先頭lng:    int32  （×1e6）
#     以降デルタ: int16 × 2 × (点数-1)
# ────────────────────────────────────────
HAZARD_DP_EPSILON = 0.0001   # 道路より粗め（ポリゴンは大きいので十分）

def convert_hazard(features):
    buf = bytearray()
    buf += b'GPLH'
    buf += struct.pack('B', 3)   # v3

    risk_map = {'high': 1, 'medium': 2, 'low': 3}

    polygons = []
    total_before = total_after = 0
    delta_clips = 0

    for feat in features:
        props = feat.get('properties', {})
        geom  = feat.get('geometry', {})
        risk  = risk_map.get(props.get('risk_level', 'medium'), 2)

        rings = []
        if geom['type'] == 'Polygon':
            rings = [geom['coordinates'][0]]
        elif geom['type'] == 'MultiPolygon':
            rings = [ring[0] for ring in geom['coordinates']]

        for ring in rings:
            if len(ring) < 3:
                continue
            # [lng, lat] → tuple リストに変換
            coords = [(c[0], c[1]) for c in ring]
            total_before += len(coords)

            # Douglas-Peucker で間引き
            coords = douglas_peucker(coords, epsilon=HAZARD_DP_EPSILON)
            total_after += len(coords)

            if len(coords) < 3:
                continue

            # 閉じていない場合は閉じる
            if coords[0] != coords[-1]:
                coords.append(coords[0])

            polygons.append((1, risk, coords))

    buf += struct.pack('<I', len(polygons))
    for haz_type, risk_level, coords in polygons:
        buf += struct.pack('B', haz_type)
        buf += struct.pack('B', risk_level)
        buf += struct.pack('<H', len(coords))

        # 先頭座標は絶対値
        first_lat = int(coords[0][1] * 1e6)
        first_lng = int(coords[0][0] * 1e6)
        buf += struct.pack('<i', first_lat)
        buf += struct.pack('<i', first_lng)

        prev_lat, prev_lng = first_lat, first_lng
        for lng, lat in coords[1:]:
            cur_lat = int(lat * 1e6)
            cur_lng = int(lng * 1e6)
            dlat = cur_lat - prev_lat
            dlng = cur_lng - prev_lng
            if abs(dlat) > 32767 or abs(dlng) > 32767:
                delta_clips += 1
            buf += struct.pack('<h', max(-32767, min(32767, dlat)))
            buf += struct.pack('<h', max(-32767, min(32767, dlng)))
            prev_lat, prev_lng = cur_lat, cur_lng

    print(f'  ハザードポリゴン数: {len(polygons)}')
    print(f'  座標点数: {total_before:,} → {total_after:,} ({(1-total_after/max(total_before,1))*100:.0f}%削減)')
    if delta_clips > 0:
        print(f'  WARNING: デルタオーバーフロー {delta_clips} 箇所')
    return bytes(buf)


# ────────────────────────────────────────
# メイン処理
# ────────────────────────────────────────
def main():
    if len(sys.argv) < 4:
        print('使い方: python3 compress.py <入力GeoJSON> <出力名> <種別(roads/poi/hazard)> [出力先ディレクトリ]')
        print('例:     python3 compress.py tokyo_raw.geojson tokyo roads')
        sys.exit(1)

    input_path  = sys.argv[1]
    output_name = sys.argv[2]
    data_type   = sys.argv[3]

    # 出力先: 第4引数があればそこ、なければスクリプト基準の ../output/
    script_dir = os.path.dirname(os.path.abspath(__file__))
    if len(sys.argv) >= 5:
        output_dir = os.path.abspath(sys.argv[4])
    else:
        output_dir = os.path.normpath(os.path.join(script_dir, '..', 'maps'))
    os.makedirs(output_dir, exist_ok=True)

    print(f'読み込み中: {input_path}')
    with open(input_path, encoding='utf-8') as f:
        data = json.load(f)

    features = data.get('features', [])
    print(f'フィーチャー数: {len(features)}')

    if data_type == 'roads':
        ext = 'gplb'
        raw = convert_roads(features)
    elif data_type == 'poi':
        ext = 'gplb'
        raw = convert_poi(features)
    elif data_type == 'hazard':
        ext = 'gplh'
        raw = convert_hazard(features)
    else:
        print(f'不明な種別: {data_type}（roads/poi/hazardのいずれかを指定）')
        sys.exit(1)

    raw_path = os.path.join(output_dir, f'{output_name}.{ext}')
    gz_path  = os.path.join(output_dir, f'{output_name}.{ext}.gz')

    with open(raw_path, 'wb') as f: f.write(raw)
    gz = gzip.compress(raw, compresslevel=9)
    with open(gz_path, 'wb') as f: f.write(gz)
    # 生バイナリは gz があれば不要なので削除
    os.remove(raw_path)

    input_size = os.path.getsize(input_path)
    print(f'元のGeoJSON:  {input_size/1024/1024:.2f} MB')
    print(f'生バイナリ:   {len(raw)/1024:.1f} KB  → {raw_path}')
    print(f'gz圧縮済み:   {len(gz)/1024:.1f} KB  → {gz_path}')
    print(f'削減率: {(1-len(gz)/input_size)*100:.0f}%')
    print()
    print(f'GitHubにアップロードするファイル: {os.path.basename(gz_path)}')

if __name__ == '__main__':
    main()
