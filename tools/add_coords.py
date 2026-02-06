import pandas as pd
from geopy.geocoders import Nominatim
from geopy.exc import GeocoderTimedOut
import time
import os

# ==========================================
# ⚙️ 設定
# ==========================================
INPUT_EXCEL = "hinanjo.xlsx"          # 元のファイル
OUTPUT_EXCEL = "hinanjo_fixed.xlsx"   # 座標付きで保存する新しいファイル

# 処理する市町村（全国やると終わらないので絞る）
TARGET_CITIES = ["大崎市", "名取市"]

# Excelの列名設定 (あなたのExcelに合わせて調整してください)
COL_ADDRESS = "住所"      # 住所が書かれている列名
COL_CITY = "市町村名"     # 市町村が書かれている列名
COL_NAME = "名称"  # 施設名

# ==========================================
# 🚀 実行ロジック
# ==========================================
def main():
    print(f"📂 Loading {INPUT_EXCEL}...")
    try:
        df = pd.read_excel(INPUT_EXCEL)
    except FileNotFoundError:
        print("❌ ファイルが見つかりません。")
        return

    # 1. 大崎市と名取市だけ抜き出す
    # (列名が合っているか確認してください)
    if COL_CITY not in df.columns:
        print(f"⚠️ 列 '{COL_CITY}' が見つかりません。Excelの列名を確認してください。")
        print(f"   現在の列: {list(df.columns)}")
        return

    target_df = df[df[COL_CITY].isin(TARGET_CITIES)].copy()
    print(f"✅ 対象データ: {len(target_df)} 件 (大崎市・名取市)")

    # 2. ジオコーディング (住所 -> 緯度経度)
    geolocator = Nominatim(user_agent="safe_japan_app_student_project")
    
    print("🌍 Fetching coordinates... (時間がかかります/1件1秒)")

    # 緯度・経度の列を作る
    lats = []
    lngs = []

    for index, row in target_df.iterrows():
        address = str(row[COL_ADDRESS])
        name = str(row[COL_NAME])
        
        # 住所に「宮城県」がついてなければつける（精度向上）
        full_address = address
        if "宮城県" not in full_address:
            full_address = "宮城県" + full_address

        try:
            print(f"   📍 Searching: {full_address} ({name})...")
            location = geolocator.geocode(full_address, timeout=10)
            
            if location:
                lats.append(location.latitude)
                lngs.append(location.longitude)
                print(f"      -> OK! {location.latitude}, {location.longitude}")
            else:
                lats.append(None)
                lngs.append(None)
                print("      -> ❌ Not Found")
            
            # サーバーに負荷をかけないよう1秒待つ (マナー)
            time.sleep(1.1)

        except Exception as e:
            print(f"      -> Error: {e}")
            lats.append(None)
            lngs.append(None)

    # 3. データフレームに追加
    target_df["緯度"] = lats
    target_df["経度"] = lngs

    # 4. 保存
    target_df.to_excel(OUTPUT_EXCEL, index=False)
    print(f"🎉 完了！座標付きデータを保存しました: {OUTPUT_EXCEL}")
    print("👉 次は generate_shelters.py の INPUT_EXCEL を 'hinanjo_fixed.xlsx' に書き換えて実行してください。")

if __name__ == "__main__":
    main()