# イースターエッグ機能 実装ガイド

## 🥚 概要

審査員・デモ用の「隠しジャンプ機能」。設定画面のバージョン表示を長押しすると、タイ・サトゥン校（PCSHS Satun）へ瞬時にジャンプします。

---

## 🎯 機能仕様

### ターゲット座標
- **緯度**: 6.7374°N
- **経度**: 100.0799°E  
- **ズームレベル**: 15.0
- **場所**: PCSHS Satun, Thailand

### トリガー条件
設定画面のアプリバージョン表示を**3秒間長押し**

---

## 🚀 実装内容

### 1. DeveloperModeManager

**ファイル**: [`developer_mode_manager.dart`](file:///Users/kusakariakiraakira/Desktop/GapLess/lib/utils/developer_mode_manager.dart)

**主要メソッド**:

```dart
// サトゥンへジャンプ（ワンライナー）
await DeveloperModeManager.jumpToSatun();

// イースターエッグトリガー（設定画面用）
await DeveloperModeManager.triggerEasterEgg(context);

// デベロッパーモードが有効か確認
final isActive = await DeveloperModeManager.isDeveloperModeActive();

// ターゲット座標を取得
final target = await DeveloperModeManager.getTargetLocation();
```

---

## 📝 設定画面への実装

### Before（通常のバージョン表示）

```dart
ListTile(
  title: Text('アプリバージョン'),
  subtitle: Text('1.0.0'),
)
```

### After（イースターエッグ追加）

```dart
InkWell(
  onLongPress: () async {
    await DeveloperModeManager.triggerEasterEgg(context);
  },
  child: ListTile(
    title: Text('アプリバージョン'),
    subtitle: Text('1.0.0'),
    trailing: Icon(Icons.info_outline),
  ),
)
```

---

## 🗺️ 地図画面側の実装

### home_screen.dartへの統合

`initState()`または`didChangeDependencies()`で、デベロッパーモードをチェック：

```dart
@override
void initState() {
  super.initState();
  
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // デベロッパーモードチェック
    final isDevMode = await DeveloperModeManager.isDeveloperModeActive();
    
    if (isDevMode) {
      final target = await DeveloperModeManager.getTargetLocation();
      
      if (target != null && _mapController != null) {
        // 地図をアニメーション移動
        _mapController!.move(target, 15.0);
        
        // モード無効化（1回限り）
        await DeveloperModeManager.deactivateDeveloperMode();
      }
    }
  });
}
```

---

## 🎭 GPSロジックとの競合回避

### 問題
- GPS優先ロジックがすぐにユーザーの現在地に戻してしまう

### 解決策

**SharedPreferencesで「デモモードフラグ」を管理**:

```dart
// デベロッパーモード中はGPS無視
final isDevMode = await DeveloperModeManager.isDeveloperModeActive();

if (!isDevMode && locationProvider.currentLocation != null) {
  // 通常のGPS追従ロジック
  _mapController.move(locationProvider.currentLocation!, zoom);
}
```

---

## ✨ ユーザーフィードバック

### SnackBar通知

```
🚀 Developer Mode: Jumping to Satun...
```

- 背景色: Deep Purple
- 表示時間: 3秒
- 動作: Floating SnackBar
- ボタン: 「OK」

### デバッグログ

```
🚀 Developer Mode Activated!
   Target: 6.7374, 100.0799
   Region: th_satun
```

---

## 🔄 実行フロー

```
1. ユーザーが設定画面でバージョン表示を長押し
   ↓
2. DeveloperModeManager.triggerEasterEgg()が実行
   ↓
3. SharedPreferencesに以下を保存:
   - developer_mode_active = true
   - dev_target_location = "6.7374,100.0799"
   - last_region = "th_satun"
   ↓
4. SnackBarで通知
   ↓
5. ナビゲーションでホーム画面に戻る
   ↓
6. home_screen.dartのinitState()でフラグを検出
   ↓
7. 地図をサトゥンへアニメーション移動（ズーム15.0）
   ↓
8. デベロッパーモードフラグを削除（1回限り）
   ↓
9. 完了！
```

---

## 🎪 デモでの使い方

### シナリオ1: 素早いジャンプ

1. 設定画面を開く
2. 「アプリバージョン」を長押し（3秒）
3. 自動的にサトゥンへジャンプ

### シナリオ2: 審査員への説明

> 「この機能は審査員の皆様のために用意した隠し機能です。
> バージョン情報を長押しすることで、
> タイのサトゥン県へ瞬時に移動し、
> 洪水・感電リスクモードのデモを
> その場で体験していただけます。」

---

## ⚠️ 注意事項

### 1. リリース前の処理

本番リリース時は、この機能を無効化するかどうか検討：

```dart
// リリースビルドでは無効化
if (kReleaseMode) {
  return; // イースターエッグ無効
}
```

### 2. セキュリティ

- ユーザーデータの改変はしない
- 一時的な座標ジャンプのみ

### 3. パフォーマンス

- SharedPreferencesの読み書きは軽量
- 地図のアニメーション移動もスムーズ

---

## 🧪 テスト手順

### 1. 機能テスト

```dart
// 1. ジャンプ機能
await DeveloperModeManager.jumpToSatun();
final target = await DeveloperModeManager.getTargetLocation();
assert(target == LatLng(6.7374, 100.0799));

// 2. 地域変更
final prefs = await SharedPreferences.getInstance();
final region = prefs.getString('last_region');
assert(region == 'th_satun');

// 3. フラグ削除
await DeveloperModeManager.deactivateDeveloperMode();
final isActive = await DeveloperModeManager.isDeveloperModeActive();
assert(!isActive);
```

### 2. UI統合テスト

1. アプリを起動
2. 設定画面を開く
3. バージョン表示を長押し
4. SnackBarが表示されるか確認
5. ホーム画面に自動遷移するか確認
6. 地図がサトゥンにジャンプするか確認

---

## 🎉 まとめ

### この機能の価値

**デモの成功率を100%にする**:
- GPS待ち時間ゼロ
- 確実にタイモードを表示
- 審査員に好印象を与える遊び心

**実装の堅牢性**:
- SharedPreferencesで永続化
- 1回限りの実行（フラグ削除）
- GPS優先ロジックと競合しない

**プロフェッショナリズム**:
- デバッグログで動作確認可能
- SnackBarで明確なフィードバック
- クリーンなコード設計

---

## 📚 関連ファイル

- [`developer_mode_manager.dart`](file:///Users/kusakariakiraakira/Desktop/GapLess/lib/utils/developer_mode_manager.dart) - デベロッパーモード管理
- `home_screen.dart` - 地図画面（統合先）
- `settings_screen.dart` - 設定画面（イースターエッグ実装先）
