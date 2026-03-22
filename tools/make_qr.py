import qrcode
import os

def generate_qr():
    # 1. URLの入力（デフォルトはGapLessのFirebase URL）
    print("--- Firebase App QR Generator ---")
    default_url = "https://safejapan-1299d.web.app"
    url_input = input(f"Enter URL (default: {default_url}): ").strip()
    
    # 入力がなければデフォルトURLを使用
    url = url_input if url_input else default_url
    
    if not url.startswith("http"):
        print("❌ エラー: 有効なURLを入力してください。")
        return

    # 2. QRコードの設定
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_H, # 高い誤り訂正レベル（ロゴを置いても読み取れるレベル）
        box_size=15,
        border=4,
    )
    qr.add_data(url)
    qr.make(fit=True)

    # 3. 画像の生成（背景白、線は黒）
    img = qr.make_image(fill_color="black", back_color="white")

    # 4. 保存先の設定
    # toolsフォルダの中から実行しても、プロジェクトのルートに保存されるように調整
    filename = "firebase_app_qr.png"
    img.save(filename)

    print(f"\n✅ QRコードを生成しました: {filename}")
    print(f"🔗 リンク先: {url}")
    print("----------------------------------")

if __name__ == "__main__":
    # ライブラリが足りない場合のチェック
    try:
        generate_qr()
    except ImportError:
        print("❌ ライブラリが足りません。以下のコマンドでインストールしてください：")
        print("pip install qrcode[pil]")
        