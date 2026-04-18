# GapLess UI Redesign — Claude Code Prompt

## 目的

Apple Design System（DESIGN.md）をベースに、GapLessアプリのUIテーマを全画面に適用する。  
**言語・l１０n関連のコードは一切変更しない。**

---

## 変更禁止ファイル（絶対に触れないこと）

- `l10n/` 以下のすべてのファイル（ARBファイル含む）
- `l10n.dart`（存在する場合）
- `AppLocalizations` を参照・生成するすべてのファイル
- フォント切り替えロジック（Noto Sansのfontファミリー切り替え、Impeller無効化設定）
- `pubspec.yaml` の `flutter > assets > fonts` セクション（フォント定義部分）
- `lib/generated/` 以下のすべての自動生成ファイル

---

## 作成・変更するファイル

### 1. `lib/theme/app_colors.dart`（新規作成）

以下の色定数を定義すること。

```dart
// ── ベースカラー（Apple Design System）──────────────────────
pureBlack    = Color(0xFF000000)  // Hero背景
nearBlack    = Color(0xFF1D1D1F)  // 本文テキスト
lightGray    = Color(0xFFF5F5F7)  // セクション背景
white        = Color(0xFFFFFFFF)  // 逆色テキスト

// ── GapLess プライマリ（通常モード = 緑）────────────────────
// ライトモード
primaryGreen       = Color(0xFF34C759)  // iOS System Green
primaryGreenDark   = Color(0xFF30D158)  // iOS System Green (Dark)
primaryGreenMuted  = Color(0xFF1A6B2F)  // 暗い背景上のアクセント
linkGreen          = Color(0xFF248A3D)  // テキストリンク（ライト）
linkGreenDark      = Color(0xFF30D158)  // テキストリンク（ダーク）

// ── GapLess 緊急モード（emergency = 赤）─────────────────────
emergencyRed       = Color(0xFFFF3B30)  // iOS System Red（ライト）
emergencyRedDark   = Color(0xFFFF453A)  // iOS System Red（ダーク）
emergencyRedMuted  = Color(0xFF7A0000)  // 暗い背景上の背景色
emergencyRedSurface = Color(0xFF2C0000) // 緊急時の背景サーフェス

// ── セマンティック ──────────────────────────────────────────
warningOrange  = Color(0xFFFF9F0A)  // 警告（iOS System Orange）
border         = Color(0xFFD2D2D7)

// ── ダークサーフェス ────────────────────────────────────────
darkSurface1   = Color(0xFF272729)
darkSurface2   = Color(0xFF28282A)
darkSurface3   = Color(0xFF2A2A2D)

// ── テキスト透明度 ──────────────────────────────────────────
textSecondaryLight  = Color(0x7A000000)  // rgba(0,0,0,0.48)
textPrimaryLight    = Color(0xCC000000)  // rgba(0,0,0,0.80)
textSecondaryDark   = Color(0x7AFFFFFF)  // rgba(255,255,255,0.48)
textPrimaryDark     = Color(0xCCFFFFFF)  // rgba(255,255,255,0.80)

// ── オーバーレイ ────────────────────────────────────────────
overlayLight   = Color(0xA3D2D2D7)
overlayDark    = Color(0xA33C3C43)
navBgLight     = Color(0xCC000000)
navBgDark      = Color(0xE1000000)
```

---

### 2. `lib/theme/app_text_styles.dart`（新規作成）

Apple Design Systemのタイポグラフィスケールを定義すること。  
`fontFamily` は `null` にすること（iOSでSF Proが自動適用されるため）。  
**多言語テキストにNoto Sansを適用するロジックはここに含めない。**

```
displayLarge:  56px / w600 / height 1.07 / ls -0.28
displayMedium: 40px / w600 / height 1.10 / ls -0.28
displaySmall:  28px / w400 / height 1.14 / ls +0.196
titleLarge:    21px / w700 / height 1.19 / ls +0.231
titleMedium:   21px / w400 / height 1.19 / ls +0.231
bodyLarge:     17px / w400 / height 1.47 / ls -0.374
bodyEmphasis:  17px / w600 / height 1.24 / ls -0.374
bodyMedium:    14px / w400 / height 1.43 / ls -0.224
bodySmall:     12px / w400 / height 1.33 / ls -0.12
labelLarge:    14px / w600 / ls -0.224
labelSmall:    12px / w600 / ls +0.5（大文字ラベル用）
nano:          10px / w400 / height 1.47 / ls -0.08
```

---

### 3. `lib/theme/app_theme.dart`（新規作成）

`AppTheme` クラスに以下のstaticゲッターを実装すること。

```
AppTheme.normal   → ThemeData（通常時、緑プライマリ）
AppTheme.emergency → ThemeData（緊急時、赤プライマリ）
```

**両テーマ共通のルール：**

- `useMaterial3: true`
- ダークテーマベース（`Brightness.dark`）
- `scaffoldBackgroundColor: pureBlack`

**通常テーマ（AppTheme.normal）の ColorScheme：**

```
primary:              primaryGreenDark   (#30D158)
onPrimary:            pureBlack
primaryContainer:     darkSurface1       (#272729)
onPrimaryContainer:   lightGray
surface:              pureBlack
onSurface:            lightGray
surfaceContainerHigh: darkSurface1
outline:              border
error:                emergencyRedDark
```

**緊急テーマ（AppTheme.emergency）の ColorScheme：**

```
primary:              emergencyRedDark   (#FF453A)
onPrimary:            white
primaryContainer:     emergencyRedSurface (#2C0000)
onPrimaryContainer:   white
surface:              pureBlack
onSurface:            white
surfaceContainerHigh: emergencyRedSurface
outline:              emergencyRedMuted
error:                emergencyRedDark
```

**両テーマに適用するコンポーネントテーマ（Apple Design Systemルール）：**

ElevatedButton:
- shape: StadiumBorder（radius 980px相当）
- padding: horizontal 22 / vertical 8
- elevation: 0

OutlinedButton:
- shape: StadiumBorder
- padding: horizontal 22 / vertical 8
- borderSide: primaryカラー、1px

FilledButton（ダーク塗り）:
- backgroundColor: nearBlack
- shape: RoundedRectangleBorder(radius: 8)

Card:
- elevation: 0
- shape: RoundedRectangleBorder(radius: 8)
- shadowColor: rgba(0,0,0,0.5)

InputDecoration:
- borderRadius: 8
- focusedBorder: primaryカラー 1.5px
- errorBorder: emergencyRedDark
- contentPadding: horizontal 14 / vertical 10

AppBar:
- backgroundColor: navBgDark（rgba(0,0,0,0.88)）
- elevation: 0
- scrolledUnderElevation: 0
- centerTitle: true

Divider:
- color: border (#D2D2D7)、thickness: 1

Chip（フィルター型）:
- borderRadius: 11
- padding: horizontal 14 / vertical 6

---

### 4. `lib/theme/emergency_theme_notifier.dart`（新規作成）

```dart
class EmergencyThemeNotifier extends ChangeNotifier {
  bool _isEmergency = false;
  bool get isEmergency => _isEmergency;

  void activateEmergency() {
    _isEmergency = true;
    notifyListeners();
  }

  void deactivateEmergency() {
    _isEmergency = false;
    notifyListeners();
  }
}
```

---

### 5. `lib/main.dart`（変更）

既存の `MaterialApp` または `MaterialApp.router` を以下のように変更すること。  
**既存のlocalizationsDelegates・supportedLocales・locale関連のコードは変更しない。**

```dart
// 既存のlocale関連コードはそのまま残す
// 変更するのはtheme/darkThemeのみ

return ChangeNotifierProvider(
  create: (_) => EmergencyThemeNotifier(),
  child: Consumer<EmergencyThemeNotifier>(
    builder: (context, notifier, _) {
      return MaterialApp.router( // または MaterialApp
        // --- ここから変更 ---
        theme:     AppTheme.normal,
        darkTheme: notifier.isEmergency
            ? AppTheme.emergency
            : AppTheme.normal,
        themeMode: ThemeMode.dark,
        // --- ここまで変更 ---

        // 以下は既存コードをそのまま維持
        localizationsDelegates: /* 既存のまま */,
        supportedLocales:       /* 既存のまま */,
        locale:                 /* 既存のまま */,
        routerConfig:           /* 既存のまま */,
      );
    },
  ),
);
```

`provider` が未追加の場合は `pubspec.yaml` に追加すること：

```yaml
dependencies:
  provider: ^6.1.2
```

---

### 6. 緊急モード切替の呼び出し方

緊急ボタン・BLEハザード受信時など、緊急状態に入るコードから以下を呼ぶ：

```dart
context.read<EmergencyThemeNotifier>().activateEmergency();
```

解除時：

```dart
context.read<EmergencyThemeNotifier>().deactivateEmergency();
```

---

## 画面ごとの注意点

| 画面 | 対応 |
|------|------|
| メインコンパス画面 | テーマカラーを使用。CustomPainterのハードコード色（純黒背景、目盛り色）はテーマから `Theme.of(context).colorScheme` で取得するよう変更する |
| 設定画面 | `ListTile`・`Switch`・`Divider` は自動適用。特別な対応不要 |
| オンボーディング画面 | `ElevatedButton`（丸角pill）・`Card` は自動適用 |
| 言語選択画面 | **テーマのみ適用。言語一覧ロジック・ARB参照は変更しない** |
| ハザード通知画面 | `emergencyRedSurface` を背景に使う。`EmergencyThemeNotifier.activateEmergency()` を呼ぶ |

---

## スペーシングスケール（参考）

```
2, 4, 6, 8, 10, 14, 17, 20, 24, 32, 48, 64, 80, 96 (dp)
```

## 角丸スケール（参考）

```
5   = マイクロ要素
8   = ボタン・カード・入力欄
11  = フィルターチップ・検索
12  = フィーチャーカード
980 = Pillボタン（StadiumBorder使用）
円形 = メディアボタン（CircleBorder）
```

---

## 完了条件

- `flutter analyze` でエラーが出ないこと
- `flutter build apk --debug` が通ること
- ARBファイル・ロケール関連ファイルの差分が一切ないこと
- 通常状態では緑プライマリ、緊急状態では赤プライマリに切り替わること
