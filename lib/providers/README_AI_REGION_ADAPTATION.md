# AI地域適応システム 実装ガイド

## 🤖 概要

地域（日本/タイ）に応じてAIキャラクターの振る舞いを動的に切り替えるシステム。
イースターエッグと連動し、ワープした瞬間にAIの性格が変化する劇的なデモを実現。

---

## 🎯 システム構成

### 1. AppRegion 列挙型

```dart
enum AppRegion {
  japan('JP', '日本', 'Japan'),
  thailand('TH', 'タイ', 'Thailand');
}
```

### 2. RegionModeProvider

**ファイル**: [`region_mode_provider.dart`](file:///Users/kusakariakiraakira/Desktop/GapLess/lib/providers/region_mode_provider.dart)

**主要機能**:
- 地域モードの管理（Japan/Thailand）
- AIシステムプロンプトの生成
- UIテーマ色の提供
- GPS自動判定 vs デベロッパーモード強制

---

## 📝 AIシステムプロンプト

### 日本モード（地震・津波）

```
あなたは経験豊富な日本の防災士です。

【専門分野】
- 地震・津波・土砂災害
- 避難所の選定
- ブロック塀倒壊リスク
- 木造密集地域の火災

【回答スタイル】
- 簡潔な日本語
- 箇条書きで要点
```

### タイモード（洪水・感電）

```
Sawatdee Ka! あなたはタイの災害対策専門家です。

【専門分野】
- 洪水・浸水災害
- 感電死リスク（最優先）
- ボート避難
- 寺院（Wat）への避難

【回答スタイル】
- 冒頭に「Sawatdee Ka/Krap」
- タイ文化への配慮
- 感電リスクを強調
```

---

## 🔄 使用方法

### 1. Providerの登録

`main.dart`で登録：

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => RegionModeProvider()),
    // ...他のProvider
  ],
  child: MyApp(),
)
```

### 2. AIチャット画面での使用

```dart
class AIChatScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final regionMode = context.watch<RegionModeProvider>();
    final theme = regionMode.getThemeColors();
    
    return Scaffold(
      appBar: AppBar(
        title: Text('AI ${theme['mode_label']}'),
        backgroundColor: Color(int.parse(
          theme['primary'].replaceFirst('#', '0xFF'),
        )),
      ),
      body: Column(
        children: [
          // ローディング表示
          if (isAnalyzing)
            Text(regionMode.getAnalyzingLabel()),
          
          // チャット履歴
          // ...
        ],
      ),
    );
  }
}
```

### 3. AIリクエスト時のプロンプト取得

```dart
Future<String> callAI(String userMessage) async {
  final regionMode = context.read<RegionModeProvider>();
  final systemPrompt = regionMode.getSystemPrompt();
  
  // Gemini APIへのリクエスト
  final response = await geminiModel.generateContent([
    Content.text(systemPrompt),  // ← 地域別プロンプト
    Content.text(userMessage),
  ]);
  
  return response.text ?? '';
}
```

---

## 🥚 イースターエッグとの統合

### 設定画面での実装

```dart
import 'package:provider/provider.dart';
import '../providers/region_mode_provider.dart';
import '../utils/developer_mode_manager.dart';

// バージョン表示
InkWell(
  onLongPress: () async {
    final regionMode = context.read<RegionModeProvider>();
    
    // 1. 地図をサトゥンへ移動
    await DeveloperModeManager.jumpToSatun();
    
    // 2. AIをタイモードへ切り替え
    await regionMode.setRegion(
      AppRegion.thailand,
      devMode: true, // デベロッパーモード
    );
    
    // 3. 通知表示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🚀 Developer Mode!\n'
          '🗺️ Map → Satun\n'
          '🤖 AI → Thai Flood Expert',
        ),
      ),
    );
  },
  child: ListTile(
    title: Text('アプリバージョン'),
    subtitle: Text('1.0.0'),
  ),
)
```

---

## 🎨 UIテーマの動的変更

### テーマ色の取得

```dart
final theme = regionMode.getThemeColors();

// 使用例
Container(
  color: Color(int.parse(
    theme['background'].replaceFirst('#', '0xFF'),
  )),
  child: Text('${theme['icon']} ${theme['mode_label']}'),
)
```

### テーマ一覧

**日本モード**:
```json
{
  "primary": "#E53935",     // 赤（緊急）
  "accent": "#FF6F00",      // オレンジ（警告）
  "background": "#FAFAFA",  // 明るいグレー
  "icon": "🇯🇵",
  "mode_label": "Japan Earthquake Mode"
}
```

**タイモード**:
```json
{
  "primary": "#1976D2",     // 青（水）
  "accent": "#FFC107",      // 黄色（感電警告）
  "background": "#E3F2FD",  // 明るい青
  "icon": "🇹🇭",
  "mode_label": "Thai Flood Mode"
}
```

---

## 📍 GPS自動判定

### 座標ベースの地域判定

```dart
// 位置情報取得時に自動判定
locationProvider.addListener(() {
  final location = locationProvider.currentLocation;
  if (location != null) {
    regionMode.detectRegionFromGPS(
      location.latitude,
      location.longitude,
    );
  }
});
```

### 判定ロジック

- **タイ**: 緯度 5-21°, 経度 97-106°
- **日本**: 緯度 24-46°, 経度 123-154°

### デベロッパーモード時の挙動

```dart
// デベロッパーモード中はGPS判定を無視
if (_isDevMode) return;
```

→ イースターエッグでタイモードに固定後、GPSで勝手に戻らない

---

## 🎬 デモシナリオ

### シーン1: 通常起動（日本）

```
1. アプリ起動
2. GPS: 東京（35.6895, 139.6917）
3. 自動判定 → Japan Mode
4. AI: 「地震発生時は...」（日本の防災士として）
```

### シーン2: イースターエッグ（タイ）

```
1. 設定画面を開く
2. バージョン表示を長押し
3. SnackBar: 「🚀 Developer Mode!」
4. 地図がサトゥンへワープ
5. AI即座に切り替え:
   - システムプロンプト → タイ専門家
   - 挨拶: 「Sawatdee Ka!」
   - UI背景 → 青色（水）
   - アイコン → 🇹🇭
6. ユーザー: 「避難経路は？」
7. AI: 「Sawatdee Ka! 感電リスクを最優先に...」
```

---

## 🎭 AIの振る舞い比較

### 同じ質問への回答

**質問**: 「今すぐ避難すべきですか？」

**日本モード**:
```
はい。以下の手順で避難してください：

1. 揺れが収まったことを確認
2. ガスの元栓を閉める
3. 大通りを使って避難所へ
4. ブロック塀から離れる

状況により津波警報が出る可能性があります。
高台への避難も準備してください。
```

**タイモード**:
```
Sawatdee Krap! はい、すぐに避難を開始してください。

⚠️ **感電リスクに注意**:
1. 電柱・鉄塔から20m以上離れる
2. 濁った水には絶対に入らない
3. 水深0.5m以上の道は避ける

📍 推奨避難先:
- 最寄りの寺院（Wat）
- 3階以上の頑丈な建物
- ボートでの避難も検討

雨季の特性上、水位は急上昇します。
早めの行動が命を救います。
```

---

## 🧪 テスト手順

### 1. 通常モードテスト

```dart
// 1. 日本の座標でテスト
await regionMode.detectRegionFromGPS(35.6895, 139.6917);
assert(regionMode.isJapanMode);

final prompt = regionMode.getSystemPrompt();
assert(prompt.contains('防災士'));

// 2. テーマ確認
final theme = regionMode.getThemeColors();
assert(theme['icon'] == '🇯🇵');
```

### 2. イースターエッグテスト

```dart
// 1. デベロッパーモード発動
await DeveloperModeManager.jumpToSatun();
await regionMode.setRegion(AppRegion.thailand, devMode: true);

// 2. モード確認
assert(regionMode.isThailandMode);
assert(regionMode.isDevMode);

// 3. プロンプト確認
final prompt = regionMode.getSystemPrompt();
assert(prompt.contains('Sawatdee'));
assert(prompt.contains('感電'));

// 4. GPS判定が無視されることを確認
await regionMode.detectRegionFromGPS(35.6895, 139.6917);
assert(regionMode.isThailandMode); // タイのまま
```

---

## ✨ まとめ

### この機能の価値

**劇的なデモ効果**:
- ワープと同時にAIの性格が変化
- 審査員に「技術力」と「遊び心」をアピール
- 言語・文化への配慮を示せる

**実用性**:
- GPS自動判定で通常使用も快適
- デベロッパーモードで確実なデモ
- 地域特化のアドバイスで実効性向上

**技術的な洗練**:
- Provider による状態管理
- システムプロンプトの動的生成
- UI/UXの完全な地域適応

---

## 📚 関連ファイル

- [`region_mode_provider.dart`](file:///Users/kusakariakiraakira/Desktop/GapLess/lib/providers/region_mode_provider.dart) - 地域モード管理
- [`developer_mode_manager.dart`](file:///Users/kusakariakiraakira/Desktop/GapLess/lib/utils/developer_mode_manager.dart) - イースターエッグ
- AI Chat画面（統合先）
- 設定画面（トリガー実装先）
