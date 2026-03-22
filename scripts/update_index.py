#!/usr/bin/env python3
# ============================================================
# update_index.py  v2
# GitHubのindex.jsonにエリア情報を追加するスクリプト
#
# 使い方（v1互換）:
#   python3 update_index.py <エリア名> <南緯> <西経> <北緯> <東経>
#
# 使い方（v2拡張: 出力先指定）:
#   python3 update_index.py <エリア名> <南緯> <西経> <北緯> <東経> [index.jsonのパス]
#
# 例:
#   python3 update_index.py tokyo_center 35.60 139.60 35.78 139.85
#   python3 update_index.py miyagi_sendai 38.20 140.80 38.35 141.00 ../output/miyagi/index.json
# ============================================================

import sys
import json
import os
import time

def main():
    if len(sys.argv) < 6:
        print('使い方: python3 update_index.py <エリア名> <南緯> <西経> <北緯> <東経> [index.jsonのパス]')
        sys.exit(1)

    area_name = sys.argv[1]
    min_lat   = float(sys.argv[2])
    min_lng   = float(sys.argv[3])
    max_lat   = float(sys.argv[4])
    max_lng   = float(sys.argv[5])

    script_dir = os.path.dirname(os.path.abspath(__file__))

    # 第6引数があればそのパスに書き込む。なければデフォルト（../output/index.json）
    if len(sys.argv) >= 7:
        index_path = os.path.abspath(sys.argv[6])
        output_dir = os.path.dirname(index_path)
    else:
        output_dir = script_dir
        index_path = os.path.join(output_dir, 'index.json')

    os.makedirs(output_dir, exist_ok=True)

    # ── ファイルサイズ集計 ──────────────────────────────
    # output_dir 内の該当ファイルを探す。
    # 県サブフォルダ構成（output/miyagi/）でも output/ 直下でも両方対応する。
    def find_gz(filename):
        """output_dir 直下 → スクリプト基準の ../output/ の順で探す。"""
        candidates = [
            os.path.join(output_dir, filename),
            os.path.join(script_dir, filename),
        ]
        for p in candidates:
            p = os.path.normpath(p)
            if os.path.exists(p):
                return p
        return None

    roads_gz  = find_gz(f'{area_name}_roads.gplb.gz')
    poi_gz    = find_gz(f'{area_name}_poi.gplb.gz')
    hazard_gz = find_gz(f'{area_name}_hazard.gplh.gz')

    size_kb = 0
    if roads_gz:  size_kb += os.path.getsize(roads_gz)  // 1024
    if poi_gz:    size_kb += os.path.getsize(poi_gz)    // 1024
    if hazard_gz: size_kb += os.path.getsize(hazard_gz) // 1024

    # ── files エントリ構築 ──────────────────────────────
    files = {
        'roads': f'{area_name}_roads.gplb.gz',
        'poi':   f'{area_name}_poi.gplb.gz',
    }
    if hazard_gz:
        files['hazard'] = f'{area_name}_hazard.gplh.gz'

    today = time.strftime('%Y-%m-%d')

    new_tile = {
        'id':         area_name,
        'lat_min':    min_lat,
        'lat_max':    max_lat,
        'lng_min':    min_lng,
        'lng_max':    max_lng,
        'files':      files,
        'size_kb':    size_kb,
        'updated_at': today,
    }

    # ── index.json 読み書き ────────────────────────────
    if os.path.exists(index_path):
        with open(index_path, encoding='utf-8') as f:
            index = json.load(f)
    else:
        index = {'version': 2, 'updated_at': '', 'tiles': []}

    existing_ids = [t['id'] for t in index['tiles']]
    if area_name in existing_ids:
        index['tiles'][existing_ids.index(area_name)] = new_tile
        print(f'更新: {area_name}')
    else:
        index['tiles'].append(new_tile)
        print(f'追加: {area_name}')

    index['updated_at'] = today

    with open(index_path, 'w', encoding='utf-8') as f:
        json.dump(index, f, ensure_ascii=False, indent=2)

    # ── サマリー出力 ────────────────────────────────────
    print(f'index.json を更新しました: {index_path}')
    print(f'登録済みエリア数: {len(index["tiles"])} 件')
    if size_kb > 0:
        print(f'合計サイズ: {size_kb} KB')
    else:
        print(f'サイズ: ファイルが output_dir に見つかりませんでした（index のみ更新）')
        print(f'  探した場所: {output_dir}')
    print()
    print(f'次の手順: index.json を GitHub にアップロードしてください')
    print(f'  {index_path}')

if __name__ == '__main__':
    main()
