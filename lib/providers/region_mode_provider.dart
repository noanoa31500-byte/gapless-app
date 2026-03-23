import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// アプリ地域モード
enum AppRegion {
  /// 日本（地震・津波モード）
  japan('JP', '日本', 'Japan');

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

  RegionModeProvider() {
    _loadSavedRegion();
  }

  /// 保存された地域を読み込み
  Future<void> _loadSavedRegion() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString('last_region');

    if (savedCode != null) {
      // Always default to japan
      _currentRegion = AppRegion.japan;

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
    await prefs.setString('last_region', region.code.toLowerCase());

    if (kDebugMode) {
      debugPrint('🌏 Region changed to: ${region.nameEn}${devMode ? " (Dev Mode)" : ""}');
    }

    notifyListeners();
  }

  /// GPS座標から地域を判定して設定
  Future<void> detectRegionFromGPS(double latitude, double longitude) async {
    // デベロッパーモード中はGPS判定を無視
    if (_isDevMode) return;

    // Always Japan
    const detected = AppRegion.japan;

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
    return _getJapanSystemPrompt();
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

  /// UIテーマ色を取得
  Map<String, dynamic> getThemeColors() {
    return {
      'primary': '#E53935', // 赤（地震・緊急）
      'accent': '#FF6F00', // オレンジ（警告）
      'background': '#FAFAFA', // 明るいグレー
      'icon': '🇯🇵',
      'mode_label': 'Japan Earthquake Mode',
    };
  }

  /// AI分析中のラベルを取得
  String getAnalyzingLabel() {
    return '防災士が分析中...';
  }
}
