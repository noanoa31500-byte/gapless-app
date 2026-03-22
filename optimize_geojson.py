import json
import os

def optimize_geojson(input_path, output_path):
    print(f"Processing {input_path}...")
    
    try:
        with open(input_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            
        original_count = len(data.get('features', []))
        optimized_features = []
        
        for feature in data.get('features', []):
            # 3. 無効なデータの除外: LineString以外はスキップ
            geometry = feature.get('geometry')
            if not geometry or geometry.get('type') != 'LineString':
                continue
                
            # 1. 座標の精度削減 (小数点以下5桁)
            coordinates = geometry.get('coordinates', [])
            rounded_coords = [[round(lat, 5), round(lng, 5)] for lat, lng in coordinates]
            feature['geometry']['coordinates'] = rounded_coords
            
            # 2. 不要属性の削除 (highway, id のみ保持)
            properties = feature.get('properties', {})
            new_properties = {}
            
            if 'highway' in properties:
                new_properties['highway'] = properties['highway']
            
            # idはproperties内にある場合と、featureのルートにある場合がある
            # GeoJSONの標準としてはルートのidだが、OSMデータなどはpropertiesに@idなどが含まれることがある
            # ここではproperties内のidと、ユーザー要件に従い保持する
            if 'id' in properties:
                new_properties['id'] = properties['id']
                
            feature['properties'] = new_properties
            
            optimized_features.append(feature)
            
        data['features'] = optimized_features
        final_count = len(optimized_features)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, separators=(',', ':'), ensure_ascii=False)
            
        original_size = os.path.getsize(input_path) / (1024 * 1024)
        new_size = os.path.getsize(output_path) / (1024 * 1024)
        
        print(f"Done! {input_path} -> {output_path}")
        print(f"Features: {original_count} -> {final_count}")
        print(f"Size: {original_size:.2f} MB -> {new_size:.2f} MB ({100 - (new_size/original_size*100):.1f}% reduction)")
        
    except Exception as e:
        print(f"Error processing {input_path}: {e}")

# 実行
base_dir = '/Users/kusakariakiraakira/Desktop/GapLess/assets/data'
files = [
    ('roads_jp.geojson', 'roads_jp_min.geojson'),
    ('roads_th.geojson', 'roads_th_min.geojson')
]

for input_file, output_file in files:
    input_path = os.path.join(base_dir, input_file)
    output_path = os.path.join(base_dir, output_file)
    
    if os.path.exists(input_path):
        optimize_geojson(input_path, output_path)
    else:
        print(f"File not found: {input_path}")
