import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/localization.dart';

/// ============================================================================
/// Region — 地域メタデータ
/// ============================================================================
/// Region クラスは「地域固有のデータ」を一元管理することで、
/// `if (currentRegion == AppRegion.japan)` のような分岐を排除する。
/// ============================================================================
class Region {
  /// 地域ID（小文字、例: 'japan'）
  final String id;

  /// 国コード（例: 'JP'）
  final String countryCode;

  /// 多言語表示名 (lang code -> name)
  final Map<String, String> _displayNames;

  /// 地図初期表示の中心座標
  final LatLng defaultCenter;

  /// マップアセット (.gplb) のプレフィックス。例: 'tokyo_center'
  final String gplbAssetPath;

  /// 推奨/対応言語コード
  final List<String> supportedLanguages;

  /// AIシステムプロンプト
  final String systemPrompt;

  /// UIテーマ色 (16進文字列など)
  final Map<String, dynamic> themeColors;

  /// AI分析中ラベル
  final String analyzingLabel;

  const Region({
    required this.id,
    required this.countryCode,
    required Map<String, String> displayNames,
    required this.defaultCenter,
    required this.gplbAssetPath,
    required this.supportedLanguages,
    required this.systemPrompt,
    required this.themeColors,
    required this.analyzingLabel,
  }) : _displayNames = displayNames;

  /// 言語コードに応じた表示名
  String displayName(String lang) =>
      _displayNames[lang] ?? _displayNames['en'] ?? id;
}

/// ============================================================================
/// RegionRegistry — 地域定義の中央レジストリ
/// ============================================================================
class RegionRegistry {
  RegionRegistry._();

  /// 日本（東京）地域
  static final Region japan = Region(
    id: 'japan',
    countryCode: 'JP',
    displayNames: const {
      'ja': '日本',
      'en': 'Japan',
    },
    // 東京駅周辺。都庁(35.6895/139.6917)ではなく代表座標を使用
    defaultCenter: const LatLng(35.6762, 139.6503),
    gplbAssetPath: 'current',
    supportedLanguages: const ['ja', 'en', 'zh', 'ko', 'vi'],
    systemPrompt: '''あなたは経験豊富な日本の防災士です。

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

ユーザーの命を最優先に、冷静かつ的確なアドバイスを提供してください。''',
    themeColors: const {
      'primary': '#E53935',
      'accent': '#FF6F00',
      'background': '#FAFAFA',
      'icon': '🇯🇵',
      'mode_label': 'Japan Earthquake Mode',
    },
    analyzingLabel: '防災士が分析中...',
  );

  /// 全地域
  static final List<Region> all = [japan];

  /// IDで地域を取得
  static Region byId(String id) =>
      all.firstWhere((r) => r.id == id, orElse: () => japan);

  /// 国コードで地域を取得
  static Region byCountryCode(String code) =>
      all.firstWhere((r) => r.countryCode == code, orElse: () => japan);

  /// GPS座標から地域を判定
  static Region detectFromGPS(double latitude, double longitude) {
    return japan;
  }
}

/// アプリ地域モード（旧 enum 互換）
/// 新規コードは [RegionRegistry] を直接使用すること。
@Deprecated('Use RegionRegistry — kept for backward compatibility')
enum AppRegion {
  japan('JP', '日本', 'Japan');

  final String code;
  final String nameJa;
  final String nameEn;

  const AppRegion(this.code, this.nameJa, this.nameEn);

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
  Region _currentRegion = RegionRegistry.japan;
  bool _isDevMode = false; // デベロッパーモード（強制モード）

  /// 現在の地域 (Region オブジェクト)
  Region get region => _currentRegion;

  /// 旧API: AppRegion 列挙体での取得
  AppRegion get currentRegion => AppRegion.japan;

  bool get isDevMode => _isDevMode;

  /// 日本モードか
  bool get isJapanMode => _currentRegion.id == 'japan';

  RegionModeProvider() {
    _loadSavedRegion();
  }

  /// 保存された地域を読み込み
  Future<void> _loadSavedRegion() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('last_region');

    if (savedId != null) {
      _currentRegion = RegionRegistry.byId(savedId);
      if (kDebugMode) {
        debugPrint('📍 Loaded region: ${_currentRegion.displayName('en')}');
      }
    }

    notifyListeners();
  }

  /// 地域を変更（Region オブジェクト版）
  Future<void> setRegionByObject(Region region, {bool devMode = false}) async {
    _currentRegion = region;
    _isDevMode = devMode;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_region', region.id);

    if (kDebugMode) {
      debugPrint('🌏 Region changed to: ${region.displayName('en')}'
          '${devMode ? " (Dev Mode)" : ""}');
    }

    notifyListeners();
  }

  /// 地域を変更（旧API互換）
  Future<void> setRegion(AppRegion region, {bool devMode = false}) async {
    await setRegionByObject(RegionRegistry.japan, devMode: devMode);
  }

  /// GPS座標から地域を判定して設定
  Future<void> detectRegionFromGPS(double latitude, double longitude) async {
    if (_isDevMode) return;
    final detected = RegionRegistry.detectFromGPS(latitude, longitude);
    if (detected.id != _currentRegion.id) {
      await setRegionByObject(detected);
    }
  }

  /// デベロッパーモードを解除
  Future<void> exitDevMode() async {
    _isDevMode = false;
    notifyListeners();
  }

  /// AIシステムプロンプトを取得 (現在地域から)
  String getSystemPrompt() => _currentRegion.systemPrompt;

  /// UIテーマ色を取得 (現在地域から)
  Map<String, dynamic> getThemeColors() => _currentRegion.themeColors;

  /// AI分析中のラベルを取得 (現在地域から)
  String getAnalyzingLabel() => _currentRegion.analyzingLabel;

  /// 現在地域のデフォルト座標 (35.6895/139.6917 のハードコード排除用)
  LatLng get defaultCenter => _currentRegion.defaultCenter;

  /// 現在地域の表示名
  String displayName([String? lang]) =>
      _currentRegion.displayName(lang ?? GapLessL10n.lang);
}
