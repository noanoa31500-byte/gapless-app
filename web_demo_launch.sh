#!/bin/bash

# SafeJapan Web Demo Launcher
# このスクリプトはFlutter Webをビルドし、ローカルサーバーを起動します

echo "🚀 SafeJapan Web Demo Launcher"
echo "================================"
echo ""

# Step 1: Flutter Webをビルド
echo "📦 Step 1: Building Flutter Web (Release Mode)..."
flutter build web --release

# ビルドが成功したか確認
if [ $? -ne 0 ]; then
    echo "❌ Build failed! Please check the error messages above."
    exit 1
fi

echo ""
echo "✅ Build Complete!"
echo ""

# Step 2: ローカルサーバーを起動
echo "🌐 Step 2: Starting local web server on port 8000..."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ SafeJapan is now running locally!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📱 Local Access:"
echo "   http://localhost:8000"
echo ""
echo "🌍 Public Access (for Demo):"
echo "   1. Open a NEW terminal window"
echo "   2. Run: ngrok http 8000"
echo "   3. Share the HTTPS URL with reviewers"
echo ""
echo "💡 TIP: Keep this terminal open while demoing!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Pythonサーバーを起動
cd build/web
python3 -m http.server 8000
