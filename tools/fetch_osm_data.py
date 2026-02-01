import requests
import json
import math

# --- 設定エリア ---
# 1. 検索の中心地点（デモ拠点）
LOCATIONS = {
    "jp_osaki": {"lat": 38.5772, "lon": 140.9559, "radius": 3000},  # 大崎市役所 半径3km
    "jp_natori": {"lat": 38.1610, "lon": 140.8500, "radius": 3000}, # 仙台高専 半径3km
    "th_pathum": {"lat": 14.1109, "lon": 100.3977, "radius": 3000}, # タイPCSHS 半径3km
}

# 2. 抽出したい施設とOSMタグの対応
# type: アプリ内で使う識別子
TARGETS = {
    "hospital": ['"amenity"="hospital"', '"amenity"="clinic"'],
    "shelter": ['"emergency"="shelter"', '"emergency"="assembly_point"', '"amenity"="school"', '"amenity"="community_centre"'], # 学校・公民館も避難所候補として取得
    "water": ['"amenity"="drinking_water"', '"emergency"="water_tank"'],
    "fuel": ['"amenity"="fuel"'],
    "convenience": ['"shop"="convenience"', '"shop"="supermarket"'],
}

# ------------------

def build_query(lat, lon, radius):
    """Overpass APIクエリを構築"""
    query = "[out:json][timeout:120];("
    for type_key, tags in TARGETS.items():
        for tag in tags:
            # node, way, relationすべて検索し、中心座標周辺(around)でフィルタ
            query += f'node[{tag}](around:{radius},{lat},{lon});'
            query += f'way[{tag}](around:{radius},{lat},{lon});'
            # relationは処理が複雑になるため今回は除外（デモならnode/wayで十分）
    query += ");out center;" # wayの場合も中心座標を出力
    return query

def fetch_data():
    all_locations = []
    
    print("🌍 OSMからデータ抽出を開始します...")
    
    for region_key, loc in LOCATIONS.items():
        print(f"   Searching {region_key}...")
        query = build_query(loc['lat'], loc['lon'], loc['radius'])
        
        try:
            response = requests.post("https://overpass-api.de/api/interpreter", data=query)
            response.raise_for_status()
            data = response.json()
            
            elements = data.get("elements", [])
            print(f"   -> {len(elements)} 件ヒットしました")
            
            for el in elements:
                # 座標の取得（wayの場合はcenter内のlat/lon）
                lat = el.get("lat") or el.get("center", {}).get("lat")
                lon = el.get("lon") or el.get("center", {}).get("lon")
                
                if not lat or not lon:
                    continue

                # タグからタイプを判定
                tags = el.get("tags", {})
                name = tags.get("name", tags.get("name:en", "Unknown Spot"))
                
                # アプリ用のタイプ決定ロジック
                my_type = "unknown"
                if "hospital" in tags.get("amenity", "") or "clinic" in tags.get("amenity", ""):
                    my_type = "hospital"
                elif "school" in tags.get("amenity", "") or "shelter" in tags.get("emergency", "") or "community_centre" in tags.get("amenity", ""):
                    my_type = "shelter"
                elif "drinking_water" in tags.get("amenity", "") or "water_tank" in tags.get("emergency", ""):
                    my_type = "water"
                elif "fuel" in tags.get("amenity", ""):
                    my_type = "fuel"
                elif "convenience" in tags.get("shop", "") or "supermarket" in tags.get("shop", ""):
                    my_type = "convenience"

                # データ整形
                all_locations.append({
                    "id": str(el["id"]),
                    "region": region_key,
                    "name": name,
                    "lat": lat,
                    "lng": lon,
                    "type": my_type
                })
                
        except Exception as e:
            print(f"❌ Error in {region_key}: {e}")

    # JSON保存
    output_file = "locations.json"
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(all_locations, f, ensure_ascii=False, indent=2)
    
    print(f"\n✅ 完了！合計 {len(all_locations)} 件のデータを '{output_file}' に保存しました。")
    print("   このファイルをFlutterプロジェクトの assets フォルダに移動してください。")

if __name__ == "__main__":
    fetch_data()