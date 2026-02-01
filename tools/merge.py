import json
import os

# --- ここが修正ポイント ---
# このスクリプトがある場所（toolsフォルダ）を基準にする
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# ファイルパスを絶対パスで作る（これで迷子にならない）
MAIN_FILE = os.path.join(BASE_DIR, "locations.json")
ADD_FILE = os.path.join(BASE_DIR, "shelters.json")
OUTPUT_FILE = os.path.join(BASE_DIR, "locations_merged.json")
# -----------------------

def main():
    print(f"📍 作業場所: {BASE_DIR}")
    
    # ファイル存在チェック
    if not os.path.exists(MAIN_FILE):
        print(f"❌ エラー: locations.json が見つかりません。")
        print(f"   探している場所: {MAIN_FILE}")
        return
    if not os.path.exists(ADD_FILE):
        print(f"❌ エラー: shelters.json が見つかりません。")
        print(f"   探している場所: {ADD_FILE}")
        return

    try:
        # 1. メイン読み込み
        with open(MAIN_FILE, "r", encoding="utf-8") as f:
            main_data = json.load(f)
        print(f"✅ メインデータ読込成功: {len(main_data)} 件")

        # 2. 追加データ読み込み
        with open(ADD_FILE, "r", encoding="utf-8") as f:
            add_data = json.load(f)
        print(f"✅ 追加データ読込成功: {len(add_data)} 件")

        # 3. 統合処理
        merged_list = list(main_data)
        existing_ids = {item["id"] for item in main_data} # ID重複チェック用

        count = 0
        for item in add_data:
            # タイのリージョンコード補正
            if item.get("region") == "Thailand":
                item["region"] = "th_pathum"
            
            # IDが被っていなければ追加
            if item["id"] not in existing_ids:
                merged_list.append(item)
                existing_ids.add(item["id"])
                count += 1
            else:
                # 重複していたらスキップ
                pass

        # 4. 保存
        with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
            json.dump(merged_list, f, ensure_ascii=False, indent=2)

        print(f"\n🎉 成功！ {count} 件追加して合計 {len(merged_list)} 件になりました。")
        print(f"💾 出力ファイル: {OUTPUT_FILE}")
        print("👉 これを 'locations.json' にリネームしてアプリに入れてください！")

    except Exception as e:
        print(f"❌ エラー発生: {e}")

if __name__ == "__main__":
    main()