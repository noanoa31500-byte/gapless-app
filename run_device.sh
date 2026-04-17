#!/bin/bash
# ================================================================
# GapLess 実機高速ビルド スクリプト
#
# 使い方:
#   ./run_device.sh         # 通常の差分ビルド（2回目以降: 数分）
#   ./run_device.sh --clean # 依存関係変更後のフルビルド
# ================================================================

set -e

DEVICE_ID="00008140-00091C5E0113801C"  # 完熟マンゴー (ワイヤレス)

# ── 引数処理 ──────────────────────────────────────────────────
CLEAN=false
for arg in "$@"; do
  case $arg in
    --clean) CLEAN=true ;;
    --help)
      echo "Usage: ./run_device.sh [--clean]"
      echo "  (no flag)  差分ビルド: 2回目以降は数分で完了"
      echo "  --clean    pubspec.yaml や Podfile を変えたときだけ使う"
      exit 0
      ;;
  esac
done

# ── クリーンモード（pubspec/Podfile変更時のみ） ──────────────
if [ "$CLEAN" = true ]; then
  echo "🧹 クリーンビルド開始（初回・依存関係変更後のみ実行してください）"
  flutter clean
  flutter pub get
  cd ios && pod install && cd ..
  echo "✅ クリーン完了"
fi

# ── 差分ビルド & 実機転送 ────────────────────────────────────
echo "📱 実機ビルド開始: $DEVICE_ID"
echo "💡 ヒント: USBケーブルで接続するとワイヤレスより10倍速くなります"
echo ""

flutter run \
  --device-id "$DEVICE_ID" \
  --debug \
  --no-pub \
  --dart-define=FLUTTER_BUILD_MODE=debug

# ── 終了メッセージ ────────────────────────────────────────────
echo ""
echo "✅ 完了"
