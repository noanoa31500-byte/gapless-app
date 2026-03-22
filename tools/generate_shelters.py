import pandas as pd
import json
import os

# ==========================================
# ⚙️ 設定 (ここを自分のExcelに合わせて変更)
# ==========================================
INPUT_EXCEL = "hinanjo_fixed.xlsx"  # toolsフォルダ内のExcelファイル名
OUTPUT_JSON = "../assets/data/shelters.json" # 出力先

# 抽出したい市町村リスト
TARGET_CITIES = ["大崎市", "名取市"]

# Excelの列名のマッピング (あなたのExcelの列名に合わせて書き換えてください)
# 左側: アプリで使う名前, 右側: Excelの実際の列名
COLUMN_MAP = {
    "name": "名称",       # 例: "施設名", "名称" など
    "lat": "緯度",              # 例: "緯度"
    "lng": "経度",              # 例: "経度"
    "address": "住所",          # 例: "住所", "所在地"
    "city": "市町村名",         # 例: "市区町村"
}

# デモ用に手動で追加するタイのデータ (PCSHS周辺)
THAILAND_DATA = [
    {
        "id": "th_pcshs_school",
        "region": "Thailand",
        "name": "PCSHS Pathum Thani",
        "lat": 14.1109,
        "lng": 100.3977,
        "type": "school",
        "verified": True
    },
    {
        "id": "th_temple_1",
        "region": "Thailand",
        "name": "Wat Bang Kadi (Temple)",
        "lat": 13.98705,
        "lng": 100.54890,
        "type": "temple",
        "verified": False
    },
    {
        "id": "th_hospital_1",
        "region": "Thailand",
        "name": "Pathum Thani Hospital",
        "lat": 14.02055,
        "lng": 100.52388,
        "type": "hospital",
        "verified": True
    }
]

# ==========================================
# 🚀 変換ロジック
# ==========================================
def main():
    print(f"📂 Loading {INPUT_EXCEL}...")
    
    # Excelを読み込む (データが大きいと時間がかかります)
    try:
        df = pd.read_excel(INPUT_EXCEL)
    except FileNotFoundError:
        print(f"❌ Error: {INPUT_EXCEL} が見つかりません。toolsフォルダに置いてください。")
        return

    print("🔍 Inspecting columns...")
    # 列名が存在するかチェック (エラー回避用)
    missing_cols = [col for col in COLUMN_MAP.values() if col not in df.columns]
    if missing_cols:
        print(f"⚠️ Warning: 以下の列名がExcel内に見つかりません: {missing_cols}")
        print(f"   現在の列名: {list(df.columns)}")
        print("   スクリプト内の COLUMN_MAP を修正してください。")
        return

    # 1. 市町村でフィルタリング
    target_df = df[df[COLUMN_MAP["city"]].isin(TARGET_CITIES)].copy()
    print(f"✅ Found {len(target_df)} shelters in {TARGET_CITIES}.")

    shelters = []

    # 2. データをアプリ用フォーマットに変換
    for index, row in target_df.iterrows():
        # 緯度経度がないデータはスキップ
        if pd.isna(row[COLUMN_MAP["lat"]]) or pd.isna(row[COLUMN_MAP["lng"]]):
            continue
            
        # ID生成 (連番またはハッシュ)
        shelter_id = f"jp_{index}"
        
        # タイプの簡易判定 (名前から推測)
        name = str(row[COLUMN_MAP["name"]])
        shelter_type = "shelter"
        if "学校" in name or "小" in name or "高" in name:
            shelter_type = "school"
        elif "病院" in name:
            shelter_type = "hospital"
        elif "会館" in name or "センター" in name:
            shelter_type = "gov"

        shelter_data = {
            "id": shelter_id,
            "region": "Japan",
            "name": name,
            "lat": float(row[COLUMN_MAP["lat"]]),
            "lng": float(row[COLUMN_MAP["lng"]]),
            "type": shelter_type,
            "verified": True  # 自治体Excel由来なのでTrue
        }
        shelters.append(shelter_data)

    # 3. タイのデータを合体
    shelters.extend(THAILAND_DATA)
    print(f"🇹🇭 Added {len(THAILAND_DATA)} locations from Thailand.")

    # 4. JSON書き出し
    os.makedirs(os.path.dirname(OUTPUT_JSON), exist_ok=True)
    with open(OUTPUT_JSON, 'w', encoding='utf-8') as f:
        json.dump(shelters, f, indent=2, ensure_ascii=False)

    print(f"🎉 Success! Generated {len(shelters)} shelters at: {OUTPUT_JSON}")

if __name__ == "__main__":
    main()