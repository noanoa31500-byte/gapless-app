/*
【AIへの包括的開発指令書】
以下の3つのセクション（UI/UX、ウェイポイント、国別ロジック）にある指示は、
本プロジェクトにおいて絶対的な優先権を持ちます。これらに従い、コードを全面的に刷新してください。

=======================================================
指令1：UI/UXの完全刷新と脱・デフォルト化
=======================================================
あなたは世界的に有名なUI/UXデザイナーです。
現在の「機能は動くが、デザインがいかにもAIが作ったデフォルト感（ダサい）」を撤廃してください。

1. 脱・AIっぽさ（脱・デフォルトデザイン）
- 【禁止】Flutter標準の「鮮やかな青（Colors.blue）」は使用禁止。
    - 代わりに、防災アプリらしい「信頼感のある濃いネイビー」と「警告色の暖色オレンジ」の
      モダンな配色パレットを定義し、ThemeData全体に適用せよ。
- 【禁止】過度なドロップシャドウ（elevation）は排除せよ。
    - フラットデザイン、またはニューモーフィズムを取り入れ、elevationは原則0〜2に抑えること。
- 【ボタン】
    - 角丸（BorderRadius）は `8.0` ではなく `16.0` や `30.0` を採用し、親しみやすさを出すこと。
    - ボタンの高さは最低 `56.0` を確保し、押しやすくすること（Fittsの法則）。

2. UX（使いやすさ）の向上
- 【文字】重要な情報は大きく、太く。階層構造（Heading vs Body）を明確にする。
    - 専門用語や英語のエラーメッセージは排除し、日本の高校生やお年寄りでもわかる「優しい日本語」にする。
- 【余白】パディング不足は素人っぽさの原因。
    - 画面端や要素間には十分な余白（最低 16.0〜24.0）を設け、呼吸できるレイアウトにする。
- 【導線】
    - 「戻るボタン」が遠い、「次に何を押せばいいかわからない」状態をなくす。
    - 主要アクション（避難所を探す、連絡する）は、画面下部の押しやすい位置に配置する。

=======================================================
指令2：オフライン対応・危険回避型ウェイポイントナビゲーション
=======================================================
あなたは高度な地理情報システム(GIS)エンジニアです。
現在の「直線ナビゲーション」を廃止し、「動的危険回避ルーティング」へ書き換えてください。

1. ナビゲーション方式の根本変更（直線 → ウェイポイント）
- 目的地までの詳細な経路座標（List<LatLng> waypoints）を取得・保存する。
- オフライン移行後は、保存されたウェイポイントを順にたどる方式へ移行する。

2. コンパスの「次へ次へ」誘導ロジック
- コンパスの矢印は、「最終目的地」ではなく、常に「直近のウェイポイント（次の経由地）」を指すこと。
- ユーザーが現在のターゲット地点から「半径15メートル以内」に入ったら、自動的に「到達」と判定する。
- 到達判定後、即座にターゲットを「次のウェイポイント」に更新し、矢印の向きを変更する。
- ウェイポイント通過時に、画面を見なくてもわかるようデバイスを振動（HapticFeedback）させる。

3. バックグラウンド先読みとキャッシュ
- アプリ起動中（オンライン時）、ユーザーが移動するたびに周辺施設への「最大安全ルート」を裏で再計算・キャッシュし、突然のオフラインに備える。

=======================================================
指令3：国別・災害回避アルゴリズムの厳密な分岐
=======================================================
国モード（Japan/Thailand）に応じて、ルート計算の「コスト関数（重み付け）」を明確に区別してください。

1. 日本モード (Japan Mode: Osaki/Natori)
- 【回避対象】洪水浸水想定区域
- 【優先判断】道路の幅員 (Road Width) を最重視
    - 日本の都市部は狭い道が多く、災害時に閉塞や渋滞が発生しやすい。
    - OpenStreetMapデータの `width` や `lanes` を参照し、「広い道路」を優先的に算出せよ。
    - 計算式イメージ: `Cost = Distance + (FloodRisk * Max) + (1.0 / RoadWidth)`

2. タイモード (Thailand Mode: Satun/PCSHS)
- 【回避対象】
    1. 洪水浸水想定区域
    2. 感電危険区域 (Electric Shock Risk Polygons) ← !!最重要!!
- 【優先判断】感電リスクの完全排除
    - タイの洪水時は、水没した電線や漏電による事故が致命的であるため、
      道路の広さよりも「感電リスクエリアを1ミリでも踏まないこと」を絶対優先とする。
    - データ不足時は、PCSHS周辺にテスト用の「仮想感電危険エリア」を定義して実装すること。

=======================================================
*/

import 'package:flutter/material.dart';
// これ以降は既存のコードを維持

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';
import 'providers/shelter_provider.dart';
import 'providers/user_profile_provider.dart';
import 'providers/compass_provider.dart';
import 'providers/alert_provider.dart';
import 'providers/location_provider.dart';
import 'providers/language_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/disaster_compass_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'utils/web_bridge.dart';
import 'screens/shelter_dashboard_screen.dart';
import 'utils/styles.dart';
import 'screens/emergency_card_screen.dart';
import 'screens/survival_guide_screen.dart';
import 'screens/triage_screen.dart';
import 'screens/tutorial_screen.dart';
import 'screens/onboarding_screen.dart';
import 'utils/localization.dart';
import 'services/font_service.dart'; // Import FontService
import 'services/security_service.dart';
import 'utils/apple_animations.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  // グローバルエラーハンドリング（Red Screen of Death防止）
  runZonedGuarded(() {
    // Flutterフレームワークのエラーをキャッチ
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      // 本番環境では詳細をログに記録するだけ
      debugPrint('Flutter Error: ${details.exception}');
    };
    
    // ステータスバーの設定（モダンな外観）
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    
    // Start with LoadingApp to preload resources
    runApp(const LoadingApp());
  }, (error, stack) {
    // 非同期エラーをキャッチ
    debugPrint('Async Error: $error');
    debugPrint('Stack: $stack');
  });
}

class GapLessApp extends StatelessWidget {
  const GapLessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LanguageProvider(),
      child: Consumer<LanguageProvider>(
        builder: (context, languageProvider, _) {
          return MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => UserProfileProvider()), // New Profile Provider
              ChangeNotifierProvider(create: (_) => ShelterProvider()),
              ChangeNotifierProvider(create: (_) => CompassProvider()),
              ChangeNotifierProvider(create: (_) => AlertProvider()),
              ChangeNotifierProvider(create: (_) => LocationProvider()),
            ],
            child: MaterialApp(
              title: 'GapLess',
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              scrollBehavior: const CustomScrollBehavior(),
              // Apple HIG準拠のライト/ダークテーマ
              theme: _buildAppTheme(languageProvider.currentLanguage, isDark: false),
              darkTheme: _buildAppTheme(languageProvider.currentLanguage, isDark: true),
              themeMode: ThemeMode.system, // システム設定に追従
              home: const AppStartup(),
              // Apple HIG準拠の画面遷移アニメーション
              onGenerateRoute: (settings) {
                Widget page;
                bool isModal = false;
                
                switch (settings.name) {
                  case '/onboarding':
                    page = const OnboardingScreen();
                    break;
                  case '/splash':
                    page = const SplashScreen();
                    break;
                  case '/home':
                    page = const HomeScreen();
                    break;
                  case '/compass':
                    page = const DisasterCompassScreen();
                    break;
                  case '/dashboard':
                    page = const ShelterDashboardScreen();
                    break;
                  case '/emergency_card':
                    page = const EmergencyCardScreen();
                    isModal = true;
                    break;
                  case '/survival_guide':
                    page = const SurvivalGuideScreen();
                    break;
                  case '/triage':
                    page = const TriageScreen();
                    break;
                  case '/tutorial':
                    page = TutorialScreen(onComplete: () {
                      Navigator.pushReplacementNamed(navigatorKey.currentContext!, '/home');
                    });
                    break;
                  default:
                    return null;
                }
                
                // モーダルページはボトムシートスタイル
                if (isModal) {
                  return AppleModalRoute(page: page);
                }
                // 通常の画面遷移はスライド
                return ApplePageRoute(page: page);
              },
               builder: (context, child) {
                // アプリ全体を監視ラップ + フォント強制 (Nuclear Option)
                // 万が一Themeが効かない場所でも、強制的にNotoAppを適用する
                return DisasterWatcher(
                  child: child!,
                );
              },
            ),
          );
        },
      ),
    );
  }



  /// Apple HIG準拠のテーマデザインを構築
  /// "Safety & Clarity" - 災害時のパニック状態でも誤操作を防ぐデザイン
  ThemeData _buildAppTheme(String lang, {bool isDark = false}) {
    // Dynamic Font Selection (言語対応)
    final String primaryFont = lang == 'th' ? 'NotoSansThai' : 'NotoSansJP';
    final List<String> fallbackFonts = lang == 'th' 
        ? ['NotoSansJP', 'sans-serif', 'Arial'] 
        : ['NotoSansThai', 'sans-serif', 'Arial'];
    
    // Apple HIG Semantic Colors (Light/Dark対応)
    const Color actionBlue = Color(0xFF007AFF);
    const Color safetyGreen = Color(0xFF34C759);
    const Color warningOrange = Color(0xFFFF9500);
    const Color dangerRed = Color(0xFFFF3B30);
    
    // ダークモード対応カラー
    final Color systemBackground = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final Color secondaryBackground = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final Color label = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

    return ThemeData(
      useMaterial3: true,
      fontFamily: primaryFont,
      fontFamilyFallback: fallbackFonts,
      brightness: isDark ? Brightness.dark : Brightness.light,
      
      // Apple HIG ColorScheme
      colorScheme: isDark 
          ? ColorScheme.dark(
              primary: actionBlue,
              secondary: safetyGreen,
              tertiary: warningOrange,
              error: dangerRed,
              surface: secondaryBackground,
              onPrimary: Colors.white,
              onSecondary: Colors.white,
              onError: Colors.white,
              onSurface: label,
            )
          : ColorScheme.light(
              primary: actionBlue,
              secondary: safetyGreen,
              tertiary: warningOrange,
              error: dangerRed,
              surface: systemBackground,
              onPrimary: Colors.white,
              onSecondary: Colors.white,
              onError: Colors.white,
              onSurface: label,
            ),
      
      // Scaffold背景色 (Apple: Clean White/Black)
      scaffoldBackgroundColor: systemBackground,

      // AppBarテーマ (Apple: Translucent with blur effect)
      appBarTheme: AppBarTheme(
        backgroundColor: secondaryBackground.withValues(alpha: 0.9),
        foregroundColor: label,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: primaryFont,
          fontFamilyFallback: fallbackFonts,
          fontSize: 17, 
          fontWeight: FontWeight.w600, 
          color: label,
          letterSpacing: -0.41,
        ),
        iconTheme: const IconThemeData(color: actionBlue),
      ),

      // Cardテーマ (Apple: Subtle elevation)
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: secondaryBackground,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // ElevatedButtonテーマ (Apple: Prominent action)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: actionBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontFamily: primaryFont,
            fontFamilyFallback: fallbackFonts,
            fontWeight: FontWeight.bold, 
            fontSize: 16,
          ),
        ),
      ),

      // OutlinedButtonテーマ (GapLess: Red accent)
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.redAccent,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: Colors.redAccent, width: 2),
           textStyle: TextStyle(
             fontFamily: primaryFont,
             fontFamilyFallback: fallbackFonts,
             fontWeight: FontWeight.bold, 
             fontSize: 16,
           ),
        ),
      ),

      // FloatingActionButtonテーマ (GapLess: Red accent)
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: dangerRed,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      // InputDecorationテーマ
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: dangerRed, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),

      // ChipThemeData (GapLess: Red accent)
      chipTheme: ChipThemeData(
        backgroundColor: Colors.grey.shade100,
        selectedColor: Colors.redAccent,
        labelStyle: TextStyle(
           fontFamily: primaryFont,
           fontFamilyFallback: fallbackFonts,
           fontWeight: FontWeight.bold, 
           fontSize: 14,
           color: Colors.black87,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // IconTheme
      iconTheme: IconThemeData(
        color: label,
        size: 24,
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade300,
        thickness: 1,
        space: 1,
      ),

      // SnackBar Theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: label,
        contentTextStyle: TextStyle(
           fontFamily: primaryFont,
           fontFamilyFallback: fallbackFonts,
           color: Colors.white, 
           fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),

      // BottomSheet Theme
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // PopupMenu Theme
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? secondaryBackground : Colors.white,
        surfaceTintColor: isDark ? secondaryBackground : Colors.white,
        textStyle: TextStyle(fontFamily: primaryFont, fontFamilyFallback: fallbackFonts, color: label, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      
      // Banner Theme
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: isDark ? secondaryBackground : Colors.white,
        contentTextStyle: TextStyle(fontFamily: primaryFont, fontFamilyFallback: fallbackFonts, color: label, fontSize: 14),
      ),
    );
  }
}

class DisasterWatcher extends StatefulWidget {
  final Widget child;
  const DisasterWatcher({super.key, required this.child});

  @override
  State<DisasterWatcher> createState() => _DisasterWatcherState();
}

// ... unchanged ...

class _DisasterWatcherState extends State<DisasterWatcher> {
  bool? _wasDisasterMode;
  bool? _wasSafeInShelter;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _heartbeatTimer;
  Timer? _recoveryTimer; // デバウンス用タイマー

  @override
  void initState() {
    super.initState();
    // アプリ起動時に位置情報をリクエスト
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocationProvider>().initLocation();
    });

    // 1. Connectivity Monitoring (Standard)
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        _triggerDisasterMode("Connectivity API");
      } else {
        // 接続が戻った場合 (Mobile or Wifi)
        _onNetworkRestored("Connectivity API");
      }
    });

    // 2. JS Bridge / Web Event (Instant)
    WebBridgeInterface.listenForOfflineEvent(() {
      _triggerDisasterMode("JS Event (offline)");
    });
    WebBridgeInterface.listenForOnlineEvent(() {
       _onNetworkRestored("JS Event (online)");
    });

    // 3. Frequency Heartbeat (Active Polling)
    // UIスレッドを最優先するため、間隔を3秒(3000ms)に拡大
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      // 災害モードが既にONなら何もしない
      if (context.read<ShelterProvider>().isDisasterMode) return;

      try {
        // Web対応: Googleへの直接PingはCORSエラーになるため、自分のサーバー(Origin)を確認する
        // Mobile: Google (8.8.8.8的な信頼性) を確認
        Uri targetUri;
        if (kIsWeb) {
          // キャッシュ回避
          targetUri = Uri.parse('${Uri.base.origin}/?_t=${DateTime.now().millisecondsSinceEpoch}');
        } else {
          targetUri = Uri.parse('https://www.google.com');
        }

        // 1秒での検知を目指すため、Timeoutを厳格に設定 (RCA対策)
        await http.head(targetUri).timeout(const Duration(seconds: 1));
      } catch (e) {
        // タイムアウトやDNSエラー、サーバダウン = オフライン判定
        _triggerDisasterMode("Heartbeat Failure: $e");
      }
    });
  }

  void _triggerDisasterMode(String reason) {
    debugPrint('⚠️ Offline detected! Triggering Disaster Mode immediately. Reason: $reason');
    if (mounted) {
       final provider = context.read<ShelterProvider>();
       if (!provider.isDisasterMode) {
         provider.setDisasterMode(true);
       }
    }
  }

  /// ネットワーク復旧検知 (デバウンス付き)
  void _onNetworkRestored(String reason) {
    // そもそも災害モードでなければ何もしない
    // ※ 起動直後など、Providerが未初期化のタイミングでの呼び出しを避けるためmountedチェック
    if (!mounted) return;
    if (!context.read<ShelterProvider>().isDisasterMode) return; 

    debugPrint('ℹ️ Network restored signal received: $reason. Waiting for stability...');
    
    // 既存のタイマーをキャンセル (チャタリング防止)
    _recoveryTimer?.cancel();
    
    // 2秒間安定したら復旧とみなす
    _recoveryTimer = Timer(const Duration(seconds: 2), () {
      _executeRecovery();
    });
  }

  /// 復旧処理実行
  void _executeRecovery() {
    debugPrint('✅ Network confirmed stable. Returning to Home.');
    if (!mounted) return;

    final shelterProvider = context.read<ShelterProvider>();
    final locationProvider = context.read<LocationProvider>();

    if (!shelterProvider.isDisasterMode) return;

    // 1. UIフィードバック
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.t('msg_network_restored'),
          style: emergencyTextStyle(color: Colors.white, isBold: true),
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );

    // 2. ステートのリセット
    shelterProvider.setDisasterMode(false);
    shelterProvider.setSafeInShelter(false);

    // 3. データ再取得 (バックグラウンド)
    shelterProvider.loadShelters();
    shelterProvider.loadHazardPolygons();
    locationProvider.initLocation();

    // 4. ホームへ遷移（履歴を置き換え）
    navigatorKey.currentState?.pushReplacementNamed('/home');
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _heartbeatTimer?.cancel();
    _recoveryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 災害モードの変化を監視
    final isDisasterMode = context.select<ShelterProvider, bool>((p) => p.isDisasterMode);
    // 避難完了状態を監視
    final isSafeInShelter = context.select<ShelterProvider, bool>((p) => p.isSafeInShelter);

    if (_wasDisasterMode != isDisasterMode) {
      if (isDisasterMode) {
        // ONになった瞬間 -> コンパス画面へ（履歴を置き換え）
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // pushReplacementNamedを使用して履歴エントリの追加を最小化
          navigatorKey.currentState?.pushReplacementNamed('/compass');
        });
      } else if (_wasDisasterMode == true && !isDisasterMode) {
        // OFFになった瞬間 -> ホームへ復帰
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigatorKey.currentState?.pushReplacementNamed('/home');
        });
      }
      _wasDisasterMode = isDisasterMode;
    }

    // 避難完了時の画面遷移 (ダッシュボードへ)
    if (_wasSafeInShelter != isSafeInShelter) {
      if (isSafeInShelter) {
         // Arrived -> Dashboard（履歴を置き換え）
         WidgetsBinding.instance.addPostFrameCallback((_) {
            navigatorKey.currentState?.pushReplacementNamed('/dashboard');
         });
      } else if (_wasSafeInShelter == true && !isSafeInShelter) {
         // Reset -> Back to Compass (if disaster) or Home (if safe)
         WidgetsBinding.instance.addPostFrameCallback((_) {
            if (isDisasterMode) {
              navigatorKey.currentState?.pushReplacementNamed('/compass');
            } else {
              navigatorKey.currentState?.pushReplacementNamed('/home');
            }
         });
      }
      _wasSafeInShelter = isSafeInShelter;
    }

    return widget.child;
  }
}


class CustomScrollBehavior extends MaterialScrollBehavior {
  const CustomScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
      };
}

/// アプリ起動時のルーティング
/// オンボーディング完了状態をチェックして適切な画面へ遷移
class AppStartup extends StatefulWidget {
  const AppStartup({super.key});

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  String _loadingMessage = 'データを準備中...';
  bool _isLatest = false;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    // 言語設定を読み込み（LanguageProviderと同期）
    final languageProvider = context.read<LanguageProvider>();
    await languageProvider.loadLanguage();
    
    // オンボーディング完了状態をチェック
    final isOnboardingCompleted = await OnboardingScreen.isCompleted();
    
    if (!mounted) return;
    
    if (isOnboardingCompleted) {
      // 完了済み → 毎回言語選択画面を表示してからホームへ
      // 少し待ってから遷移することで「準備中」の質感を出す
      await Future.delayed(const Duration(milliseconds: 500));
      await _showLanguageSelectionThenHome();
    } else {
      // 未完了 → オンボーディングへ（言語選択含む）
      Navigator.pushReplacementNamed(context, '/onboarding');
    }
  }
  
  /// 言語選択画面を表示してからホームへ遷移
  Future<void> _showLanguageSelectionThenHome() async {
    // 言語選択画面へ遷移（全画面）
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const _LanguageSelectionScreen(),
        fullscreenDialog: true, // モーダル遷移アニメーションを使用
      ),
    );
    
    if (!mounted) return;
    
    // 言語選択後、データロードしてホームへ
    await _loadDataAndGoHome();
  }

  Future<void> _loadDataAndGoHome() async {
    try {
      final shelterProvider = context.read<ShelterProvider>();
      final locationProvider = context.read<LocationProvider>();
      
      // 保存された地域を読み込んでShelterProviderに設定
      // これにより言語と地域が独立して動作する
      final prefs = await SharedPreferences.getInstance();
      final savedRegion = prefs.getString('target_region') ?? 'Japan';
      
      // 地域を設定（これにより正しいサバイバルガイドが表示される）
      await shelterProvider.setRegion(savedRegion);
      
      // 並行でデータロード (Parallel Execution)
      // shelterProvider.setRegion -> loadShelters (Decoupled, so only loads shelters)
      // We need to call loadHazardPolygons and loadRoadData explicitly now.
      
      final initLocationFuture = locationProvider.initLocation();
      final loadHazardsFuture = shelterProvider.loadHazardPolygons();
      final loadRoadsFuture = shelterProvider.loadRoadData();
      
      // We invoke setRegion first to ensure correct shelters are loaded? 
    // setRegion calls loadShelters internally.
    // So:
    
    setState(() => _loadingMessage = '避難所情報を読込中...');
    await shelterProvider.setRegion(savedRegion); // Loads shelters for region
    
    setState(() => _loadingMessage = 'ハザード情報を準備中...');
    await Future.wait([
      initLocationFuture,
      loadHazardsFuture,
      loadRoadsFuture,
    ]);
    
    // GPSが取得できていれば、地域を自動補正する
    if (locationProvider.currentLocation != null) {
      final loc = locationProvider.currentLocation!;
      setState(() => _loadingMessage = '地域を自動調整中...');
      await shelterProvider.setRegionFromCoordinates(loc.latitude, loc.longitude);
      
      // Start Compass Listener
      if (context.mounted) {
         await context.read<CompassProvider>().startListening();
      }
      
      // Pre-calculate Routes (Offline Ready) - "Calculating..."回避
      if (context.mounted) {
         setState(() => _loadingMessage = '最新ルートを計算中...');
         await shelterProvider.updateBackgroundRoutes(loc);
      }
      
      setState(() {
        _loadingMessage = '準備完了！データ: 最新';
        _isLatest = true;
      });
    } else {
      // 位置情報が取得できない場合でも、最新状態であることを伝える
      setState(() {
        _loadingMessage = '準備完了！データ: 最新';
        _isLatest = true;
      });
    }

    // 「データ：最新」をユーザーが認識できるように最低1.5秒待機
    await Future.delayed(const Duration(milliseconds: 1500));

    } catch (e) {
      debugPrint('Data loading error: $e');
    }
    
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // GapLess Logo
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFE53935).withValues(alpha: 0.15),
                    const Color(0xFFE53935).withValues(alpha: 0.05),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield_rounded,
                size: 48,
                color: Color(0xFFE53935),
              ),
            ),
            const SizedBox(height: 24),
            // GapLess Text
            RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: 'Gap',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                    ),
                  ),
                  TextSpan(
                    text: 'Less',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE53935),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: Color(0xFFE53935),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _loadingMessage,
              style: TextStyle(
                color: _isLatest ? const Color(0xFF4CAF50) : const Color(0xFF6B7280),
                fontSize: 14,
                fontWeight: _isLatest ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoadingApp extends StatefulWidget {
  const LoadingApp({super.key});

  @override
  State<LoadingApp> createState() => _LoadingAppState();
}

class _LoadingAppState extends State<LoadingApp> {
  @override
  void initState() {
    super.initState();
    _preloadResources();
  }

  Future<void> _preloadResources() async {
    // フォントのロードを待機
    // UX向上のため、最低2秒はロード画面を見せて「準備中」であることを伝える
    final minWait = Future.delayed(const Duration(milliseconds: 2000));
    final fontLoad = FontService.loadFonts();
    final securityInit = SecurityService().init();
    
    await Future.wait([minWait, fontLoad, securityInit]);

    // 本アプリへ切り替え
    if (mounted) {
      runApp(const GapLessApp());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // GapLess Logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFE53935).withValues(alpha: 0.15),
                      const Color(0xFFE53935).withValues(alpha: 0.05),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  size: 48,
                  color: Color(0xFFE53935),
                ),
              ),
              const SizedBox(height: 24),
              // GapLess Text
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'Gap',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    TextSpan(
                      text: 'Less',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE53935),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  color: Color(0xFFE53935),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'データ: 最新 [JAN 31]',
                style: TextStyle(
                  color: Color(0xFF4CAF50),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 起動時に毎回表示される言語選択画面（全画面）
class _LanguageSelectionScreen extends StatefulWidget {
  const _LanguageSelectionScreen();

  @override
  State<_LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<_LanguageSelectionScreen> {
  String _selectedLanguage = AppLocalizations.lang;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2), // Top spacing
              
              // Icon
              Container(
                width: 100, // Slightly larger for fullscreen
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1976D2).withValues(alpha: 0.15),
                      const Color(0xFF1976D2).withValues(alpha: 0.05),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.language_rounded,
                  size: 48,
                  color: Color(0xFF1976D2),
                ),
              ),
              const SizedBox(height: 32),
              
              // Title
              const Text(
                'Select Language',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28, // Larger title
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '言語を選択 / เลือกภาษา',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF6B7280),
                ),
              ),
              
              const SizedBox(height: 48), // More breathing room
              
              // Language Options
              _buildLanguageOption('🇯🇵', '日本語', 'ja'),
              const SizedBox(height: 12),
              _buildLanguageOption('🇬🇧', 'English', 'en'),
              const SizedBox(height: 12),
              _buildLanguageOption('🇹🇭', 'ไทย (Thai)', 'th'),
              
              const Spacer(flex: 2), // Bottom spacing
              
              // Confirm Button (Premium Style)
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1976D2).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () async {
                    // 言語を保存
                    await AppLocalizations.setLanguage(_selectedLanguage);
                    if (context.mounted) {
                      // LanguageProviderを更新
                      context.read<LanguageProvider>().setLanguage(_selectedLanguage);
                      
                      // TTS言語も更新
                      try {
                        context.read<AlertProvider>().onLanguageChanged();
                      } catch (_) {
                        // AlertProviderがまだ初期化されていない場合は無視
                      }
                      
                      Navigator.pop(context);
                    }
                  },
                  child: Center(
                    child: Text(
                      _selectedLanguage == 'ja' ? 'はじめる' 
                          : (_selectedLanguage == 'th' ? 'เริ่มต้น' : 'Get Started'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        height: 1.2, // Safari fix
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildLanguageOption(String flag, String name, String code) {
    final isSelected = _selectedLanguage == code;
    
    return GestureDetector(
      onTap: () => setState(() => _selectedLanguage = code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: isSelected 
              ? const Color(0xFF1976D2).withValues(alpha: 0.1)
              : const Color(0xFFF3F4F6), // Slightly darker grey for better visibility on white
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF1976D2) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 32)), // Larger flag
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 18, // Larger text
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? const Color(0xFF1976D2) : const Color(0xFF374151),
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFF1976D2), size: 26),
          ],
        ),
      ),
    );
  }
}
