# GeoJsonLoader 使用ガイド

## 📍 概要

`GeoJsonLoader`は、大きなGeoJSONファイル（10MB以上）を効率的に読み込むためのサービスクラスです。
別スレッド（Isolate）でJSONパースを行うことで、UIのフリーズを防ぎます。

## 🎯 配置場所

```
lib/services/geojson_loader.dart
```

## 💡 使用方法

### 基本的な使い方

```dart
import 'package:safejapan/services/geojson_loader.dart';

// インスタンスを作成
final loader = GeoJsonLoader();

// 日本の道路データを読み込む
final roadData = await loader.loadRoadDataJapan();

// タイの病院データを読み込む
final hospitalData = await loader.loadHospitalDataThailand();

// GeoJSONのfeaturesにアクセス
final features = roadData['features'] as List;
print('読み込んだ道路の数: ${features.length}');
```

### Provider内での使用例

```dart
import 'package:flutter/material.dart';
import '../services/geojson_loader.dart';

class MapDataProvider with ChangeNotifier {
  final GeoJsonLoader _geoJsonLoader = GeoJsonLoader();
  List<dynamic> _roads = [];
  bool _isLoading = false;

  List<dynamic> get roads => _roads;
  bool get isLoading => _isLoading;

  /// 道路データを読み込む
  Future<void> loadRoads() async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _geoJsonLoader.loadRoadDataJapan();
      _roads = data['features'] as List;
    } catch (e) {
      debugPrint('道路データの読み込みに失敗: $e');
      _roads = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

### カスタムGeoJSONファイルの読み込み

```dart
// 汎用メソッドを使用
final customData = await loader.loadGeoJson('assets/data/custom_location.geojson');
```

## 📦 利用可能なメソッド

| メソッド名 | 説明 | ファイルパス |
|-----------|------|------------|
| `loadRoadDataJapan()` | 日本の道路データを読み込む | `assets/data/roads_jp.geojson` |
| `loadRoadDataThailand()` | タイの道路データを読み込む | `assets/data/roads_th.geojson` |
| `loadHospitalDataThailand()` | タイの病院データを読み込む | `assets/data/hospital_th.geojson` |
| `loadStoreDataThailand()` | タイの店舗データを読み込む | `assets/data/store_th.geojson` |
| `loadShelterDataThailand()` | タイのシェルターデータを読み込む | `assets/data/shelter_th.geojson` |
| `loadGeoJson(String path)` | 任意のGeoJSONファイルを読み込む | カスタムパス |

## ⚡ パフォーマンスの特徴

- **非同期処理**: `async/await`を使用した非ブロッキング処理
- **別スレッド実行**: `compute()`を使用してIsolateで実行
- **UIフリーズ防止**: 10MB以上のファイルでもスムーズに動作

## 🛠️ エラーハンドリング

```dart
try {
  final data = await loader.loadRoadDataJapan();
  // データ処理
} catch (e) {
  // エラーハンドリング
  print('GeoJSONの読み込みに失敗しました: $e');
  // フォールバックデータを使用するなど
}
```

## 📝 注意事項

1. **assetsの登録**: `pubspec.yaml`に必ず追加してください
   ```yaml
   flutter:
     assets:
       - assets/data/roads_jp.geojson
       - assets/data/roads_th.geojson
       - assets/data/hospital_th.geojson
       - assets/data/store_th.geojson
       - assets/data/shelter_th.geojson
   ```

2. **メモリ使用量**: 非常に大きなファイル（100MB以上）の場合は、メモリ不足に注意

3. **初回読み込み**: 初回はファイルのデコードに時間がかかる可能性があるため、アプリ起動時に読み込むことを推奨

## 🔧 既存コード（ShelterProvider）への統合例

```dart
import '../services/geojson_loader.dart';

class ShelterProvider with ChangeNotifier {
  final GeoJsonLoader _geoJsonLoader = GeoJsonLoader();
  
  Future<void> loadHazardPolygons() async {
    try {
      // タイの病院データから危険エリアを読み込む
      final data = await _geoJsonLoader.loadHospitalDataThailand();
      final features = data['features'] as List;
      
      // ポリゴンデータを処理
      // ... 既存のロジック
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ ハザードポリゴン読み込みエラー: $e');
    }
  }
}
```

## ✅ テスト

```dart
void main() async {
  final loader = GeoJsonLoader();
  
  print('📍 GeoJSON読み込みテスト開始...');
  
  final data = await loader.loadRoadDataJapan();
  final features = data['features'] as List;
  
  print('✅ 成功: ${features.length}件のデータを読み込みました');
}
```
