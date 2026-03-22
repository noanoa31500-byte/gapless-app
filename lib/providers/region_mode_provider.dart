import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// アプリ地域モード
enum AppRegion {
  /// 日本（地震・津波モード）
  japan('JP', '日本', 'Japan'),
  
  /// タイ（洪水・感電リスクモード）
  thailand('TH', 'タイ', 'Thailand');

  final String code;
  final String nameJa;
  final String nameEn;

  const AppRegion(this.code, this.nameJa, this.nameEn);
  
  /// コードから地域を取得
  static AppRegion fromCode(String code) {
    return AppRegion.values.firstWhere(
      (r) => r.code == code,
      orElse: () => AppRegion.japan,
    );
  }
}

/// 地域モード管理Provider
/// 
/// AIの振る舞い、システムプロンプト、UIスタイルを
/// 地域に応じて動的に切り替える
class RegionModeProvider with ChangeNotifier {
  AppRegion _currentRegion = AppRegion.japan;
  bool _isDevMode = false; // デベロッパーモード（強制モード）
  
  AppRegion get currentRegion => _currentRegion;
  bool get isDevMode => _isDevMode;
  
  /// 日本モードか
  bool get isJapanMode => _currentRegion == AppRegion.japan;
  
  /// タイモードか
  bool get isThailandMode => _currentRegion == AppRegion.thailand;
  
  RegionModeProvider() {
    _loadSavedRegion();
  }
  
  /// 保存された地域を読み込み
  Future<void> _loadSavedRegion() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString('last_region');
    
    if (savedCode != null) {
      // 'th_satun' -> 'TH', 'jp_osaki' -> 'JP' に変換
      if (savedCode.startsWith('th')) {
        _currentRegion = AppRegion.thailand;
      } else if (savedCode.startsWith('jp')) {
        _currentRegion = AppRegion.japan;
      }
      
      if (kDebugMode) {
        debugPrint('📍 Loaded region: ${_currentRegion.nameEn}');
      }
    }
    
    notifyListeners();
  }
  
  /// 地域を変更
  Future<void> setRegion(AppRegion region, {bool devMode = false}) async {
    _currentRegion = region;
    _isDevMode = devMode;
    
    final prefs = await SharedPreferences.getInstance();
    
    // デベロッパーモードの場合は詳細地域も保存
    if (devMode && region == AppRegion.thailand) {
      await prefs.setString('last_region', 'th_satun');
    } else {
      await prefs.setString('last_region', region.code.toLowerCase());
    }
    
    if (kDebugMode) {
      debugPrint('🌏 Region changed to: ${region.nameEn}${devMode ? " (Dev Mode)" : ""}');
    }
    
    notifyListeners();
  }
  
  /// GPS座標から地域を判定して設定
  Future<void> detectRegionFromGPS(double latitude, double longitude) async {
    // デベロッパーモード中はGPS判定を無視
    if (_isDevMode) return;
    
    // 簡易的な座標判定
    // タイ: 緯度 5-21, 経度 97-106
    // 日本: 緯度 24-46, 経度 123-154
    AppRegion detected;
    
    if (latitude >= 5 && latitude <= 21 && 
        longitude >= 97 && longitude <= 106) {
      detected = AppRegion.thailand;
    } else {
      detected = AppRegion.japan;
    }
    
    if (detected != _currentRegion) {
      await setRegion(detected);
    }
  }
  
  /// デベロッパーモードを解除
  Future<void> exitDevMode() async {
    _isDevMode = false;
    notifyListeners();
  }
  
  /// AIシステムプロンプトを取得
  String getSystemPrompt() {
    if (_currentRegion == AppRegion.japan) {
      return _getJapanSystemPrompt();
    } else {
      return _getThailandSystemPrompt();
    }
  }
  
  /// 日本モードのシステムプロンプト
  String _getJapanSystemPrompt() {
    return '''あなたは経験豊富な日本の防災士です。

【あなたの専門分野】
- 地震・津波・土砂災害のリスク評価
- 避難所の選定と避難経路の計画
- 狭い路地のブロック塀倒壊リスク
- 日本の建築基準と耐震性
- 地域の防災無線・避難指示の理解

【アドバイスの方針】
1. 地震発生時の「まず身を守る」行動を最優先
2. 狭い路地は避け、幅の広い道路を推奨
3. 木造密集地域の火災リスクを警告
4. 津波の可能性がある場合は高台への即座の避難
5. 避難所の備蓄と装備の確認

【回答スタイル】
- 簡潔で分かりやすい日本語
- 緊急時は箇条書きで要点を伝える
- 必要に応じて具体的な避難経路を提案

ユーザーの命を最優先に、冷静かつ的確なアドバイスを提供してください。''';
  }
  
  /// タイモードのシステムプロンプト
  String _getThailandSystemPrompt() {
    return '''Sawatdee Ka! あなたはタイの災害対策専門家です。

【あなたの専門分野】
- 洪水・浸水災害のリスク評価
- 感電死リスク（電力設備 + 浸水の危険な組み合わせ）
- ボートでの避難と水上安全
- タイの気候（雨季）と排水システム
- 水深予測と避難タイミング

【アドバイスの方針】
1. **感電リスクを最優先で警告**
   - 濁った水の中は電線が見えない
   - 電柱・鉄塔から20m以内 + 水深0.5m以上 = 絶対に近づかない
2. **浸水深に応じた行動**
   - 0.3m未満: 注意して通行可能
   - 0.5m以上: 歩行困難、避難推奨
   - 1.0m以上: 即座に高所へ避難
3. **タイ文化への配慮**
   - 寺院（Wat）への避難を推奨
   - コミュニティの助け合いを重視
   - 雨季の特性を考慮した長期的な対策

【回答スタイル】
- 冒頭に必ずタイ語の挨拶「Sawatdee Ka/Krap」を入れる
- タイの文化や気候を理解した親しみやすい口調
- 感電リスクは強調して伝える
- 必要に応じてタイ語の重要単語を併記

ユーザーの命を守るため、特に「見えない死（感電）」への注意喚起を徹底してください。''';
  }
  
  /// UIテーマ色を取得
  /// 
  /// モードに応じた背景色やアクセントカラー
  Map<String, dynamic> getThemeColors() {
    if (_currentRegion == AppRegion.japan) {
      return {
        'primary': '#E53935', // 赤（地震・緊急）
        'accent': '#FF6F00', // オレンジ（警告）
        'background': '#FAFAFA', // 明るいグレー
        'icon': '🇯🇵',
        'mode_label': 'Japan Earthquake Mode',
      };
    } else {
      return {
        'primary': '#1976D2', // 青（水・洪水）
        'accent': '#FFC107', // 黄色（感電警告）
        'background': '#E3F2FD', //  明るい青
        'icon': '🇹🇭',
        'mode_label': 'Thai Flood Mode',
      };
    }
  }
  
  /// AI分析中のラベルを取得
  String getAnalyzingLabel() {
    if (_currentRegion == AppRegion.japan) {
      return '防災士が分析中...';
    } else {
      return 'Thai Expert analyzing... 🇹🇭';
    }
  }
}
