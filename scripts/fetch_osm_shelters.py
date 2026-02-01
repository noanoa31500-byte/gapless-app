#!/usr/bin/env python3
"""
大崎市の公式避難所データとOSMデータを照合して統合するスクリプト

公式データソース:
- 大崎市オープンデータ: 指定緊急避難場所等一覧（令和7年4月1日現在）
- OpenStreetMap (Overpass API)

出力: assets/data/shelter.json (GeoJSON形式)
"""

import requests
import json
import csv
from typing import List, Dict, Optional
from io import StringIO
import time

# API設定
OVERPASS_URL = "https://overpass-api.de/api/interpreter"
# ローカルの公式CSVファイル
import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OSAKI_OFFICIAL_CSV_PATH = os.path.join(SCRIPT_DIR, '..', 'tools', '【大崎市】指定緊急避難場所等一覧_20250401 .csv')

# 大崎市の境界（座標範囲）
OSAKI_BOUNDS = {
    "south": 38.40,
    "west": 140.60,
    "north": 38.75,
    "east": 141.20
}

def fetch_official_shelters() -> List[Dict]:
    """大崎市の公式避難所データをローカルCSVから取得"""
    print("📥 大崎市の公式避難所データを取得中...")
    
    try:
        # ローカルCSVファイルを読み込み
        with open(OSAKI_OFFICIAL_CSV_PATH, 'r', encoding='utf-8') as f:
            # CSVをパース
            reader = csv.DictReader(f)
            
            shelters = []
            for row in reader:
                shelter = parse_official_shelter(row)
                if shelter:
                    shelters.append(shelter)
        
        print(f"✅ 公式データから{len(shelters)}件の避難所を取得")
        return shelters
    
    except FileNotFoundError:
        print(f"⚠️ 公式CSVファイルが見つかりません: {OSAKI_OFFICIAL_CSV_PATH}")
        return []
    except Exception as e:
        print(f"⚠️ 公式データの取得に失敗: {e}")
        return []

def parse_official_shelter(row: Dict) -> Optional[Dict]:
    """公式CSVの行を避難所データに変換"""
    try:
        # CSVの列名は実際のデータに合わせて調整が必要
        # 一般的な列名の例: 名称, 所在地, 緯度, 経度, 収容人数, 災害種別, etc.
        
        # 緯度・経度が含まれている場合
        lat = row.get('緯度') or row.get('latitude') or row.get('lat')
        lon = row.get('経度') or row.get('longitude') or row.get('lon') or row.get('lng')
        
        if not lat or not lon:
            # 座標がない場合は住所からジオコーディング（別途実装が必要）
            return None
        
        return {
            "name": row.get('名称', row.get('施設名', '不明')),
            "name_ja": row.get('名称', row.get('施設名', '')),
            "lat": float(lat),
            "lon": float(lon),
            "type": determine_type_from_name(row.get('名称', '')),
            "capacity": row.get('収容人数', row.get('収容可能人数', '不明')),
            "address": row.get('所在地', row.get('住所', '')),
            "phone": row.get('電話番号', ''),
            "disaster_types": row.get('災害種別', ''),
            "source": "official"
        }
    except Exception as e:
        print(f"⚠️ 行のパースエラー: {e}")
        return None

def fetch_osm_shelters() -> List[Dict]:
    """OSMから避難所データを取得"""
    print("📥 OpenStreetMapから避難所データを取得中...")
    
    query = f"""
    [out:json][timeout:60];
    (
      // 指定避難所
      node["amenity"="shelter"]["shelter_type"="public_shelter"]({OSAKI_BOUNDS['south']},{OSAKI_BOUNDS['west']},{OSAKI_BOUNDS['north']},{OSAKI_BOUNDS['east']});
      way["amenity"="shelter"]["shelter_type"="public_shelter"]({OSAKI_BOUNDS['south']},{OSAKI_BOUNDS['west']},{OSAKI_BOUNDS['north']},{OSAKI_BOUNDS['east']});
      
      // 学校
      node["amenity"="school"]({OSAKI_BOUNDS['south']},{OSAKI_BOUNDS['west']},{OSAKI_BOUNDS['north']},{OSAKI_BOUNDS['east']});
      way["amenity"="school"]({OSAKI_BOUNDS['south']},{OSAKI_BOUNDS['west']},{OSAKI_BOUNDS['north']},{OSAKI_BOUNDS['east']});
      
      // 公民館
      node["amenity"="community_centre"]({OSAKI_BOUNDS['south']},{OSAKI_BOUNDS['west']},{OSAKI_BOUNDS['north']},{OSAKI_BOUNDS['east']});
      way["amenity"="community_centre"]({OSAKI_BOUNDS['south']},{OSAKI_BOUNDS['west']},{OSAKI_BOUNDS['north']},{OSAKI_BOUNDS['east']});
      
      // 体育館
      node["leisure"="sports_centre"]({OSAKI_BOUNDS['south']},{OSAKI_BOUNDS['west']},{OSAKI_BOUNDS['north']},{OSAKI_BOUNDS['east']});
      way["leisure"="sports_centre"]({OSAKI_BOUNDS['south']},{OSAKI_BOUNDS['west']},{OSAKI_BOUNDS['north']},{OSAKI_BOUNDS['east']});
      
      // 公共施設
      node["building"="public"]({OSAKI_BOUNDS['south']},{OSAKI_BOUNDS['west']},{OSAKI_BOUNDS['north']},{OSAKI_BOUNDS['east']});
      way["building"="public"]({OSAKI_BOUNDS['south']},{OSAKI_BOUNDS['west']},{OSAKI_BOUNDS['north']},{OSAKI_BOUNDS['east']});
    );
    out center;
    """
    
    try:
        response = requests.post(OVERPASS_URL, data={'data': query}, timeout=120)
        data = response.json()
        
        shelters = []
        for element in data['elements']:
            shelter = convert_osm_to_shelter(element)
            if shelter:
                shelters.append(shelter)
        
        print(f"✅ OSMから{len(shelters)}件の施設を取得")
        return shelters
    
    except Exception as e:
        print(f"⚠️ OSMデータの取得に失敗: {e}")
        return []

def convert_osm_to_shelter(element: Dict) -> Optional[Dict]:
    """OSMデータを避難所データに変換"""
    tags = element.get('tags', {})
    
    # 座標を取得
    if element['type'] == 'node':
        lat = element['lat']
        lon = element['lon']
    elif element['type'] == 'way' and 'center' in element:
        lat = element['center']['lat']
        lon = element['center']['lon']
    else:
        return None
    
    # 名前がない施設は除外
    if 'name' not in tags:
        return None
    
    return {
        "name": tags.get('name', f"施設 {element['id']}"),
        "name_ja": tags.get('name:ja', tags.get('name', '')),
        "name_en": tags.get('name:en', ''),
        "lat": lat,
        "lon": lon,
        "type": determine_shelter_type(tags),
        "capacity": tags.get('capacity', '不明'),
        "address": tags.get('addr:full', tags.get('addr:street', '')),
        "phone": tags.get('phone', ''),
        "osm_id": element['id'],
        "source": "osm"
    }

def determine_shelter_type(tags: Dict) -> str:
    """OSMタグから避難所タイプを判定"""
    amenity = tags.get('amenity', '')
    leisure = tags.get('leisure', '')
    building = tags.get('building', '')
    
    if amenity == 'shelter':
        return 'shelter'
    elif amenity == 'school':
        return 'school'
    elif amenity == 'community_centre':
        return 'community_centre'
    elif leisure == 'sports_centre':
        return 'sports_centre'
    elif amenity == 'place_of_worship':
        return 'temple'
    elif building == 'public':
        return 'gov'
    else:
        return 'shelter'

def determine_type_from_name(name: str) -> str:
    """施設名からタイプを判定"""
    if '小学校' in name or '中学校' in name or '高校' in name or '学校' in name:
        return 'school'
    elif '公民館' in name:
        return 'community_centre'
    elif '体育館' in name:
        return 'sports_centre'
    elif '寺' in name or '神社' in name:
        return 'temple'
    elif '市役所' in name or '役場' in name or '支所' in name:
        return 'gov'
    else:
        return 'shelter'

def calculate_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """2点間の距離を計算（km）"""
    from math import radians, cos, sin, asin, sqrt
    
    lon1, lat1, lon2, lat2 = map(radians, [lon1, lat1, lon2, lat2])
    
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
    c = 2 * asin(sqrt(a))
    r = 6371  # 地球の半径（km）
    
    return c * r

def merge_shelters(official: List[Dict], osm: List[Dict]) -> List[Dict]:
    """公式データとOSMデータを統合"""
    print("🔄 データを統合中...")
    
    merged = []
    matched_osm_ids = set()
    threshold_km = 0.1  # 100m以内なら同じ施設とみなす
    
    # 公式データ優先で統合
    for official_shelter in official:
        best_match = None
        best_distance = float('inf')
        
        # OSMデータから最も近い施設を探す
        for osm_shelter in osm:
            if osm_shelter['osm_id'] in matched_osm_ids:
                continue
            
            distance = calculate_distance(
                official_shelter['lat'], official_shelter['lon'],
                osm_shelter['lat'], osm_shelter['lon']
            )
            
            if distance < best_distance and distance < threshold_km:
                best_distance = distance
                best_match = osm_shelter
        
        if best_match:
            # マッチした場合、公式データを優先しつつOSMの情報も保持
            merged_shelter = official_shelter.copy()
            merged_shelter['osm_id'] = best_match['osm_id']
            if not merged_shelter.get('name_en'):
                merged_shelter['name_en'] = best_match.get('name_en', '')
            merged.append(merged_shelter)
            matched_osm_ids.add(best_match['osm_id'])
        else:
            # マッチしない場合、公式データのみ追加
            merged.append(official_shelter)
    
    # マッチしなかったOSMデータも追加
    for osm_shelter in osm:
        if osm_shelter['osm_id'] not in matched_osm_ids:
            merged.append(osm_shelter)
    
    print(f"✅ 統合完了: 公式{len(official)}件 + OSM{len(osm)}件 → 統合後{len(merged)}件")
    print(f"   - 一致: {len(matched_osm_ids)}件")
    print(f"   - 公式のみ: {len(official) - len(matched_osm_ids)}件")
    print(f"   - OSMのみ: {len(osm) - len(matched_osm_ids)}件")
    
    return merged

def save_as_geojson(shelters: List[Dict], output_path: str):
    """GeoJSON形式で保存"""
    geojson = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "geometry": {
                    "type": "Point",
                    "coordinates": [s['lon'], s['lat']]
                },
                "properties": {
                    k: v for k, v in s.items() 
                    if k not in ['lat', 'lon']
                }
            }
            for s in shelters
        ]
    }
    
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(geojson, f, ensure_ascii=False, indent=2)
    
    print(f"💾 GeoJSONファイルを保存: {output_path}")

def main():
    print("=" * 60)
    print("大崎市避難所データ統合スクリプト")
    print("=" * 60)
    
    # 1. 公式データ取得
    official_shelters = fetch_official_shelters()
    
    # 2. OSMデータ取得
    time.sleep(1)  # API制限を考慮
    osm_shelters = fetch_osm_shelters()
    
    # 3. データ統合
    if not official_shelters and not osm_shelters:
        print("❌ データの取得に失敗しました")
        return
    
    if official_shelters and osm_shelters:
        merged_shelters = merge_shelters(official_shelters, osm_shelters)
    elif official_shelters:
        print("⚠️ OSMデータなし、公式データのみ使用")
        merged_shelters = official_shelters
    else:
        print("⚠️ 公式データなし、OSMデータのみ使用")
        merged_shelters = osm_shelters
    
    # 4. GeoJSON形式で保存
    import os
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, '..', 'assets', 'data', 'shelter.json')
    save_as_geojson(merged_shelters, output_path)
    
    print("=" * 60)
    print("✅ 処理完了！")
    print(f"   出力ファイル: {output_path}")
    print(f"   総避難所数: {len(merged_shelters)}件")
    print("=" * 60)

if __name__ == '__main__':
    main()
