# GapLess

**オフラインでも動作する、パニック対応型・災害避難ナビゲーション**

[![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?logo=dart)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android-000000?logo=apple)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-Educational-green)](LICENSE)
[![Version](https://img.shields.io/badge/Version-5.0.0-blue)](pubspec.yaml)

---

## 🎯 プロジェクトビジョン

**「災害時、判断力を失った人間を、システムが導く」**

従来の防災アプリは「情報提供」にとどまります。GapLessは、パニック状態のユーザーを**物理的に避難所まで導く**ことに特化した、次世代の災害対応システムです。

---

## 🎉 マイルストーン: BLE すれ違い通信 実機双方向動作達成（2026-04-21）

iPhone 16 + iPhone 16 Pro の 2 端末間で、**インターネット完全遮断下** でのすれ違い通信に成功。

| 検証項目 | 結果 |
|---|---|
| 通行不可ポイントのマーキング伝播 | ✅ |
| GPS トラックスナップショット自動共有 | ✅ |
| 片方端末を **スリープ状態** にしてもカウンター増加 | ✅（iOS バックグラウンド BLE 動作確認） |
| カスタム Service UUID `4b474150-...-0001` 経由のサービス発見 | ✅ |

### この日に判明した iOS 固有のハマりどころ
1. **iOS は `withServices` フィルタなしの scan で広告から name/uuid を剥がす**（プライバシー仕様）→ scan は `withServices` を必須にし、それでも見つからなければ「全件 probe → 接続後に GATT 検査」へフォールバック
2. **flutter_blue_plus v2 系は `withServices` と他フィルタを混用すると `withServices` 側を黙って空にする**（plugin source 確認済）→ 単独指定に統一
3. **`adapterState.first` は権限ダイアログ表示直後に `.unknown` を返す瞬間がある**。直接パスで `startAdvertising` を呼ぶと永遠に起動しない → **必ず `adapterState.listen` の `.on` ハンドラ内で `startAdvertising()` を呼ぶ（idempotent に）**
4. iOS の State Restoration（`CBPeripheralManagerOptionRestoreIdentifierKey`）は再インストール直後に挙動不安定 → 一旦無効化

これらの知見と native 側 (`BlePeripheralManager.swift`) の `getStatus` 診断 method channel が今回のブレークスルーの核。

---

## ⚡ なぜこれが革新的なのか

### 1. 📡 BLE リレー情報ネットワーク（インターネット不要のP2P通信）

> ⚠️ 「メッシュ」ではなく **store-and-forward broadcast relay**（hops≤3）です。AODV/BATMAN等の自己組織化メッシュルーティングは未実装。
- **課題:** 災害時、通信インフラは最初に途絶する
- **解決:** Bluetooth Low Energy で端末間リレー（受信→再ブロードキャスト、最大3ホップ）。**インターネット不要で通行止め・SOS・避難所状況を伝播**
- **技術:**
  - `PeerRoadReport`: 通行可/不可/危険のBLEアドバタイズ送信（reportCount重み付き）
  - `SosReport`: 長押し3秒で位置情報SOSビーコンを発信。受信端末が地図上に表示（1時間TTL）
  - `ShelterStatusReport`: 避難所の在避難者情報をBLEで伝播（4時間TTL）
  - カスタムGATT UUID + MTUチャンキングで安定転送
  - SQLiteでローカルキャッシュし、TTL超過後に自動削除

### 2. 🧭 オフライン自律ナビゲーション（GPS不要モード）
- **課題:** 地下・建物内でGPS信号が失われ、位置が更新されない
- **解決:** GPS沈黙3秒で自動起動する **Dead Reckoning**（自律推測航法）
- **技術:**
  - 加速度センサー（sensors_plus）で歩行を検出、磁力計方角×歩幅で位置積算
  - GPS復帰時はGPS位置80%・DR推定20%の加重平均でジャンプなく統合
  - フォールバック順位: GPS → DR推定 → 前回保存位置 → 東京デフォルト
- **UI:** 画面上部にオレンジバッジ「GPS消失 - 推定位置使用中（N歩）」を常時表示

### 3. 🚨 緊急シンプル画面（EmergencySimpleScreen）
- **課題:** パニック時は複雑なUIを操作できない
- **解決:** 3ゾーン構成の超シンプル緊急UI
  - **Zone 1（赤）:** SOSビーコン送信ボタン（長押し3秒でBLE発信）
  - **Zone 2（暗）:** 最寄り避難所への方位矢印＋距離
  - **Zone 3（灰）:** 緊急アクションボタン4つ（電話・水・応急処置・TTS再読み上げ）
- **ボリュームキーTTS:** 音量アップキー押下で現在の案内を再読み上げ（画面を見なくても操作可能）

### 4. 🌐 気象庁オープンデータ連携（JMA公式フィード）
- **課題:** 緊急地震速報・津波警報を公式情報源でリアルタイム確認したい
- **解決:** 気象庁 Atom XML フィード（`eqvol_l.xml`）を60秒ごとポーリング
- **仕様:**
  - 緊急地震速報・津波警報のみを抽出・表示
  - 発報から6時間以内を「有効」扱い（期限外は自動グレーアウト）
  - オフライン時は最後に取得したデータをキャッシュ表示
  - Pull-to-Refresh で手動更新も対応

### 5. 🧠 災害モード自動遷移（DisasterWatcher）
- **課題:** 設定や地図を見ているときに通信途絶が起きても操作の優先度が変わらない
- **解決:** `DisasterWatcher` がネット死活と JMA 緊急速報の両方を監視。**両方が成立した時のみ** コンパス画面へ遷移を促す通知を出す（自動ジャックではなくユーザー確認）
- **実装:**
  - ネット死活: Google/Apple/GitHub 3エンドポイント並列、3回連続失敗で「圏外」判定
  - JMA: `JmaAlertService.hasActiveAlert` を 60 秒ごと評価
  - 復帰時は通常モードへ帰還
- **注:** ネット断単独では遷移しない（ホテル Wi-Fi 等での誤発火を回避）

### 6. 🦶 Dead Reckoning（GPS断絶時の自律推測航法）
詳細は「オフライン自律ナビゲーション」を参照。

### 7. 🎯 リスクレーダー（360度危険度スキャン）
- **課題:** 自分の周囲どの方向が安全かわからない
- **解決:** 360度レーダーが周囲の危険ゾーンをリアルタイムスキャン
- **危険分類:**
  - 🌊 **深水リスク** — 洪水浸水深マップ
  - 🌀 **激流リスク** — 流速危険エリア
- **技術:** `RiskRadarScanner` + `OfflineRiskScanner` + RadarScanResult 数値化

### 8. 🩺 オフライントリアージ（5ステップ重症度判定 / 医療監修なし）
- **課題:** 災害時、負傷者が「どの施設へ行くべきか」迷う
- **解決:** 端末内で 5 ステップの重症度ヒアリングを行い、結果に応じて病院/避難所のいずれかへナビ起動
- **技術:** ローカルルールベース判断 → 最近傍病院 or 避難所へナビ
- **注:** 医療監修は未実施。あくまで参考情報であり医療判断には用いないこと（PL 法・医師法上の灰色領域を避ける）

### 9. 🤖 多言語AIボット（UI 骨格 18 言語 / 災害本文は日英優先）
- **課題:** 外国人・インバウンド旅行者が日本語の防災情報を読めない
- **解決:** ユーザーの言語設定に応じて官公庁ガイドライン準拠の防災アドバイスを表示
- **UI 言語（18）:** 日・英・中（簡/繁）・韓・タイ・フィリピン語・インドネシア語・ミャンマー語・ヒンディー・ネパール語・シンハラ語・ベンガル語・スペイン語・ポルトガル語・モンゴル語・ウズベク語
- **災害本文の翻訳網羅状況:** 日本語・英語は完全。他 16 言語は主要キーのみ翻訳済で、未翻訳キーは英語にフォールバック。命に関わる文言（避難・津波・SOS）の人間レビュー翻訳は順次拡充中
- **ガイド体系:** 内閣府・消防庁準拠 6項目 + 拡張サポート 10項目
- **多言語フォント:** NotoSans 10フォントファミリー内蔵（豆腐文字・文字化け回避）

### 10. 🗺️ タイルマップ自動更新（現状: 東京中心リージョン / Phase 2 で全国展開）
- **課題:** 事前にどの地域にいるかわからない
- **解決:** 起動時・以降 10 分おきにタイルを自動取得・ローカル保存。現状はリージョンが東京中心 1 つのみで、Phase 2 で `index.json` ベースの全国タイル選択 DL に拡張予定
- **仕組み:**
  - GitHub `maps` リポジトリの `index.json` を起点に DL
  - 遠方キャッシュは自動削除（ストレージ節約）
  - jsDelivr CDN をフォールバック URL として設定（GitHub 不通時も継続 DL）
- **配信整合性の注:** 現状 `index.json`/タイルへの署名検証は未実装。本番投入前に Ed25519 署名 + アプリ同梱検証鍵で改ざん防止を入れる（CRITICAL TODO）

### 11. 🎨 Apple Design System テーマ
- **通常モード:** iOS System Green（`#30D158`）ダークベース
- **緊急モード:** iOS System Red（`#FF453A`）に自動切替
- `EmergencyThemeNotifier`: 災害モード発動と同期してテーマを全画面即座に変更
- Material Design 3 準拠のコンポーネントテーマ（StadiumBorderボタン・radius 8カード）

---

## 🗺️ 画面構成（全17画面）

```
起動フロー
├─ LoadingApp             フォントプリロード＆セキュリティ初期化
├─ AppStartup             マップキャッシュ確認・遷移先振り分け
├─ MapDataLoadingScreen   GitHub地図データDL（進捗バー表示）
├─ OnboardingScreen       初回体験・言語選択・位置情報許可
└─ PermissionGateScreen   位置・モーション・Bluetooth権限取得

本体 (NavigationScreen)
├─ HomeScreen             マップ・避難所マーカー・ハザード可視化
│   └─ MapScreen          危険スポット追加・BLE同期表示
├─ ChatScreen             官公庁6項目 + AI拡張10項目（2段階メニュー）
├─ JmaFeedScreen          気象庁 緊急地震速報・津波警報 一覧
└─ EmergencyCardPage      緊急IDカード（血液型・アレルギー・ニーズ）

災害対応フロー
├─ DisasterCompassScreen   コンパス避難ナビ（戻るボタンなし・PopScope）
├─ EmergencySimpleScreen   超シンプル緊急UI（SOS / 方位 / 4アクション）
├─ RiskRadarCompassScreen  360度危険スキャン
├─ TriageScreen            5ステップ重症度判定→自動ナビ起動
└─ ShelterDashboardScreen  避難所生活支援（到着後）

設定・その他
├─ SettingsScreen      地域・言語・プロフィール・キャッシュ
├─ ProfileEditScreen   名前・血液型・国籍・アレルギー・ニーズ
├─ SurvivalGuideScreen 応急処置・行動・避難所生活（3タブ）
└─ TutorialScreen      操作説明（PageView形式）
```

---

## 🛠️ 技術スタック

### フレームワーク
| 技術 | 用途 |
|------|------|
| Flutter (Dart) | iOS / Android クロスプラットフォーム |
| Provider | 状態管理（全画面同期） |
| flutter_map | OpenStreetMap 統合（オフラインタイル対応） |
| Material Design 3 | Apple Design System 準拠テーマ |

### センサー & 位置情報
| 技術 | 用途 |
|------|------|
| geolocator | GPS高精度取得（CoreLocation）|
| flutter_compass | 磁力計コンパス（指数移動平均で平滑化、カルマンは未実装） |
| sensors_plus | 加速度センサー（Dead Reckoning 歩行検出）|
| 磁気偏角補正 | 8 都市の偏角テーブル + 逆距離加重補間（IDW）。NOAA WMM 球面調和の本実装は未着手 |

### オフライン通信（BLE）
| 技術 | 用途 |
|------|------|
| flutter_blue_plus | BLE Central による受信。Peripheral は iOS ネイティブ（Android は次フェーズ） |
| CBPeripheralManager (Swift) | iOS ペリフェラル広告 + RX/TX Characteristic（method channel `gapless/ble_peripheral`） |
| カスタム GATT UUID | 道路レポート・SOS・避難所状況の多種パケット |
| sqflite | BLE受信データのローカルDB管理 |

### データ & ルーティング
| 技術 | 用途 |
|------|------|
| GPLB（独自バイナリ） | 道路グラフ高速読込（JSON比5〜10倍）|
| A* Isolate | 非同期経路計算（UIブロックなし）|
| MapAutoLoader | 起動時1回 + 10分ごと自動タイル更新 |
| MapCacheManager | `{documents}/maps/{areaId}/` ローカル保存 |
| JmaAlertService | 気象庁Atom XMLフィード 60秒ポーリング |

### 音声 & フィードバック
| 技術 | 用途 |
|------|------|
| flutter_tts | 音声ナビ（AVFoundation / Android TTS）|
| vibration | ハプティックフィードバック |
| ボリュームキーTTS | 音量アップ = 案内文再読み上げ |

### iOS ネイティブ拡張（Method Channel）
| チャネル | 用途 |
|---------|------|
| `gapless/bg_task` | Background Task Extension |
| `gapless/brightness` | 画面輝度制御 |
| `gapless/ble_peripheral` | CBPeripheralManager ブリッジ（startAdvertising / updateData / getStatus / onDataReceived）。2026-04-21 実機双方向達成 |

---

## 📊 BLE パケット仕様

```
PeerRoadReport  {"type":"r","v":"devId","a":lat,"o":lng,"s":0-2,"c":count,"t":ts}
                s: 0=通行可 / 1=通行不可 / 2=危険
                TTL: 24時間

SosReport       {"type":"sos","v":"devId8","a":lat,"o":lng,"t":ts}
                TTL: 1時間

ShelterStatus   {"type":"sh","id":"shelId","a":lat,"o":lng,"st":0-1,"t":ts,"v":"devId"}
                st: 1=在避難者あり
                TTL: 4時間
```

---

## 🗺️ マップデータ構成

```
GitHub (noanoa31500-byte/maps リポジトリ)
├── index.json                     # 全国タイルインデックス（バージョン管理）
├── kanto/tokyo/tokyo_center_*/
│   ├── roads.gplb.gz              # 道路グラフ（バイナリ・gzip圧縮）
│   ├── poi_hospital.gplb.gz       # 医療施設POI
│   ├── poi_shelter.gplb.gz        # 避難所POI
│   ├── hazard.gplh.gz             # ハザードポリゴン
│   └── ...
└── tohoku/miyagi/osaki_*/
    └── ...
```

**フォールバック構成:**
- プライマリ: `raw.githubusercontent.com/noanoa31500-byte/maps@main`
- CDN: `cdn.jsdelivr.net/gh/noanoa31500-byte/maps@main`
- 各URLを最大2回リトライ（指数バックオフ）

---

## 🚀 セットアップ

### 必要環境
- Flutter 3.0+
- Xcode 15+（iOS）/ Android Studio（Android）
- iOS 14.0+ / Android 8.0+

### 起動手順

```bash
flutter pub get
flutter run
```

### 初回起動時の動作
1. 位置情報・コンパス・Bluetooth・モーションの権限リクエスト
2. GitHubから現在地周辺の地図タイルを自動ダウンロード
3. 気象庁フィードの初回取得
4. NavigationScreen へ遷移

---

## 機能ステータス（誇張なしの正直版）

凡例: ✅ 実機動作確認済 / 🟡 実装済・限定検証 / ⚠️ 実装済・未検証 / 🔧 実装中

| カテゴリ | 機能 | ステータス | 注記 |
|---|---|---|---|
| 🚨 緊急対応 | DisasterWatcher 災害検知 | 🔧 | 現状はネット死活のみ。Day 2 で JMA AND 条件追加予定 |
| 🚨 緊急対応 | コンパス画面ロック（PopScope）/ 超シンプル緊急UI | ✅ | |
| 📡 BLE | 道路レポート受信（iOS Central） | ✅ | 2026-04-21 iPhone 16 / 16 Pro 双方向確認 |
| 📡 BLE | SOSビーコン受信（長押し3秒で送信意図） | 🟡 | 受信処理は実機検証済。送信は屋外群衆未検証 |
| 📡 BLE | iOS Peripheral 送信（CBPeripheralManager） | ✅ | 2026-04-21 達成。adapterState listener 内 startAdvertising パターン |
| 📡 BLE | iOS バックグラウンド BLE（片方スリープ伝播） | ✅ | `bluetooth-peripheral` / `bluetooth-central` Background Mode で動作 |
| 📡 BLE | Android Peripheral 送信 | 🔧 | パーミッション宣言含め未対応（Phase 2） |
| 🧭 ナビ | A* 経路計算（Isolate） | ✅ | |
| 🧭 ナビ | Dead Reckoning（GPS 80% / DR 20% 加重平均） | ⚠️ | 屋外実走テスト未実施。誤差は理論推定。カルマン未使用 |
| 🧭 ナビ | TTS 音声ナビ（15秒間隔・ボリュームキー再生） | ✅ | |
| 🌐 情報 | JMA Atom 60秒ポーリング・XmlDocument パース | ✅ | |
| 🌐 情報 | 18言語 AI チャットボット | 🟡 | UI 18言語、災害本文は ja/en 完全・他16言語は英語フォールバック |
| 🗺️ 地図 | GPLB バイナリタイル読込 | ✅ | |
| 🗺️ 地図 | 全国タイル自動更新 | 🔧 | 現状は東京中心リージョンで実証中 |
| 🗺️ 地図 | 360度リスクレーダー（🌊深水・🌀激流） | ✅ | ⚡感電は廃止 |
| 🩺 医療 | 5ステップトリアージ / 最近傍病院ナビ | 🟡 | UI完成、医療監修なし（参考情報） |
| 🎨 UI/UX | Apple Design System / 緊急赤テーマ自動切替 | ✅ | |
| 🎨 UI/UX | 18言語ローカライズ（UI骨格） | 🟡 | UI 18言語キー化完了、災害文言の翻訳網羅は ja/en のみ |
| 🔒 セキュリティ | flutter_secure_storage マスター鍵 + HMAC デバイスID 時間ローテ | 🟡 | 実装済。SecureStorage 失敗時の fallback 鍵経路修正は Day 3 で対応 |
| 🔒 セキュリティ | BLE ペイロード署名（Ed25519 / TrustedShelterKeyset） | 🔧 | 枠組み実装済、本番鍵未投入。Day 2 で投入＋ enforce 化予定 |
| 🔒 セキュリティ | TLS 証明書ピンニング（pinned_http_client） | 🔧 | 現状ピン空セット + advisory モード（実質無効）。Day 2 で SPKI ピン投入＋ enforce 化予定 |
| 🔒 セキュリティ | アセット暗号化（AES） | 🔧 | 現状 CBC + 固定 IV（脆弱）。Day 2 で AES-GCM 化予定 |
| 🔒 セキュリティ | 配信整合性（map データ署名検証） | 🔧 | 現状未実装。Phase 2 で index.json 署名検証導入予定 |

### 既知の限界
- **BLE 実機テスト:** iOS 3台のみ。Android送信・屋外距離・群衆環境は未検証
- **ユーザーテスト:** 高齢者・外国人・障害者を含む対象者テストは未実施
- **Dead Reckoning:** 磁気偏角・歩幅キャリブレーションを地下/屋内で実測していない

---

## 🌍 社会実装への道筋

### Phase 1: 地域実証実験（現在）
- **ターゲット:** 東京都心エリア（首都直下地震想定）
- **目的:** 実際の災害訓練でのフィードバック収集

### Phase 2: 全国展開
- **ターゲット:** 全国47都道府県・在日外国人・インバウンド観光客
- **技術:** GPLBタイルシステムにより各地域のデータを即座に統合

### Phase 3: オープンソース化
- **公開範囲:** コアナビゲーション・BLE同期システム
- **ライセンス:** Apache 2.0（予定）

---

## ⚠️ 免責事項

このアプリは避難を**補助**するものであり、安全を完全に保証するものではありません。最終的な避難判断は公式の避難指示に従い、ご自身の責任で行ってください。

---

## 👨‍💻 開発情報

**プロジェクト:** GapLess  
**バージョン:** 5.0.0  
**開発:** 未踏ジュニア 2026  
**地図データ:** [noanoa31500-byte/maps](https://github.com/noanoa31500-byte/maps)

---

**「技術で命を救う」— それが、GapLessの使命です。**
