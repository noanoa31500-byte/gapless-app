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

### 5. 🧠 全画面強制割り込み（DisasterWatcher）
- **課題:** 設定や地図を見ているときに緊急地震速報が来ても操作できない
- **解決:** `DisasterWatcher` が常時ネット死活を監視。3エンドポイント同時チェックで単一障害誤検知を防ぎ、**アプリ内のどこにいても全履歴を消去してコンパス画面へ強制遷移**
- **実装:**
  - 3秒ごとのハートビート（Google / Apple / GitHub 並列チェック）
  - 3回連続失敗でのみ災害モード（ヒステリシス）
  - 復帰時は2秒ディレイ後に自動通常モードへ帰還

### 6. 🦶 Dead Reckoning（GPS断絶時の自律推測航法）
詳細は「オフライン自律ナビゲーション」を参照。

### 7. 🎯 リスクレーダー（360度危険度スキャン）
- **課題:** 自分の周囲どの方向が安全かわからない
- **解決:** 360度レーダーが周囲の危険ゾーンをリアルタイムスキャン
- **危険分類:**
  - 🌊 **深水リスク** — 洪水浸水深マップ
  - 🌀 **激流リスク** — 流速危険エリア
- **技術:** `RiskRadarScanner` + `OfflineRiskScanner` + RadarScanResult 数値化

### 8. 🩺 オフライントリアージ（5ステップ重症度判定）
- **課題:** 災害時、負傷者が「どの施設へ行くべきか」判断できない
- **解決:** 端末内で怪我の重症度を5ステップで判定し、適切な施設（医療設備の有無）へ自動ルート変更
- **技術:** ローカルルールベース判断システム → 最近傍病院/避難所へ自動ナビ起動

### 9. 🤖 多言語AIボット（全18言語対応）
- **課題:** 外国人・インバウンド旅行者が日本語の防災情報を読めない
- **解決:** ユーザーの言語設定に応じて官公庁ガイドライン準拠の防災アドバイスを自動生成
- **対応言語:** 日・英・中（簡/繁）・韓・タイ・フィリピン語・インドネシア語・ミャンマー語・ヒンディー・ネパール語・シンハラ語・ベンガル語・スペイン語・ポルトガル語・モンゴル語・ウズベク語（全18言語）
- **ガイド体系:** 内閣府・消防庁準拠 6項目 + AI拡張サポート 10項目
- **多言語フォント:** NotoSans 10フォントファミリー内蔵（豆腐文字・文字化け根絶）

### 10. 🗺️ 全国タイルマップ＋自動更新
- **課題:** 事前にどの地域にいるかわからない
- **解決:** 起動時・以降10分おきに現在地周辺3kmのタイルを自動取得・ローカル保存
- **仕組み:**
  - GitHub `maps` リポジトリの `index.json` で全国タイルを管理
  - 現在地から半径3km以内のタイルのみを選択的にDL
  - 遠方キャッシュは自動削除（ストレージ節約）
  - jsDelivr CDN をフォールバックURLとして設定（GitHub 不通時も継続DL）

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
| flutter_compass | 磁力計コンパス + カルマンフィルタ平滑化 |
| sensors_plus | 加速度センサー（Dead Reckoning 歩行検出）|
| 磁気偏角補正 | 地域別パラメータによる真北計算 |

### オフライン通信（BLE）
| 技術 | 用途 |
|------|------|
| flutter_blue_plus | BLE Central/Peripheral 双方向通信 |
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
| CBPeripheralManager | iOSネイティブBLEペリフェラル |

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
| 🚨 緊急対応 | DisasterWatcher 全画面強制遷移 | 🟡 | 開発機での手動切替確認 |
| 🚨 緊急対応 | コンパス画面ロック（PopScope）/ 超シンプル緊急UI | ✅ | |
| 📡 BLE | 道路レポート P2P 同期（iOS↔iOS） | 🟡 | 実機 3 台のみ、屋内 |
| 📡 BLE | SOSビーコン（長押し3秒） | 🟡 | 送信成功・距離未測定 |
| 📡 BLE | iOS バックグラウンド送信 | ⚠️ | Apple仕様上 overflow area へ後退、受信主体設計 |
| 📡 BLE | Android 送信 | 🔧 | パーミッション宣言含め未対応 |
| 🧭 ナビ | A* 経路計算（Isolate） | ✅ | |
| 🧭 ナビ | Dead Reckoning（GPS80%/DR20%） | ⚠️ | 屋外実走テスト未実施。誤差は理論推定 |
| 🧭 ナビ | TTS 音声ナビ（15秒間隔・ボリュームキー再生） | ✅ | |
| 🌐 情報 | JMA Atom 60秒ポーリング・XmlDocument パース | ✅ | |
| 🌐 情報 | 18言語 AI チャットボット | 🟡 | UI 確認済、応答品質は言語間差あり |
| 🗺️ 地図 | GPLB バイナリタイル読込 | ✅ | |
| 🗺️ 地図 | 全国タイル自動更新 | 🔧 | 現状は東京中心 / Thailand / 大崎の 3 リージョン |
| 🗺️ 地図 | 360度リスクレーダー（🌊深水・🌀激流） | ✅ | ⚡感電は廃止 |
| 🩺 医療 | 5ステップトリアージ / 最近傍病院ナビ | 🟡 | UI完成、医療監修なし |
| 🎨 UI/UX | Apple Design System / 緊急赤テーマ自動切替 | ✅ | |
| 🎨 UI/UX | 18言語ローカライズ | 🟡 | 主要画面のキー化完了、長文字列言語の overflow 未検証 |
| 🔒 セキュリティ | flutter_secure_storage マスター鍵 + HMAC デバイスID 時間ローテ | ✅ | |
| 🔒 セキュリティ | BLE ペイロード署名（Ed25519） | 🔧 | 未実装 — 受信側は範囲検証のみ |
| 🔒 セキュリティ | TLS 証明書ピンニング | 🔧 | 未実装 |

### 既知の限界
- **BLE 実機テスト:** iOS 3台のみ。Android送信・屋外距離・群衆環境は未検証
- **ユーザーテスト:** 高齢者・外国人・障害者を含む対象者テストは未実施
- **Dead Reckoning:** 磁気偏角・歩幅キャリブレーションを地下/屋内で実測していない

---

## 🌍 社会実装への道筋

### Phase 1: 地域実証実験（現在）
- **ターゲット:** 宮城県大崎市（人口13万人）
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
