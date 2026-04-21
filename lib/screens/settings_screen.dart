import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/localization.dart';
import '../providers/location_provider.dart';
import '../providers/language_provider.dart';
import '../providers/alert_provider.dart';
import '../data/map_repository.dart';
import '../utils/styles.dart';
import '../widgets/safe_text.dart';
import 'tutorial_screen.dart';

// Design system constants
const _kEmerald      = Color(0xFF00C896);
const _kAmber        = Color(0xFFFF6B35);
const _kDark         = Color(0xFF1A1A2E);
const _kSurface      = Color(0xFFF8F9FE);
const _kCardBg       = Colors.white;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 機能2: GPLB キャッシュ状態
  bool _isCached = false;
  int _cacheBytes = 0;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadCacheStatus();
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// 設定を読み込む
  Future<void> _loadSettings() async {
    // 設定ロードのフック (現状は地域固定のため何もしない)
  }

  /// 機能2: GPLBキャッシュの状態を読み込む
  Future<void> _loadCacheStatus() async {
    final repo = MapRepository.instance;
    final cached = await repo.isAllDataReady();
    int totalBytes = 0;
    if (cached) {
      for (final name in const [
        'current_roads.gplb',
        'current_poi.gplb',
        'current_hazard.gplh',
      ]) {
        final path = await repo.localPath(name);
        try {
          totalBytes += await File(path).length();
        } catch (_) {}
      }
    }
    if (mounted) {
      setState(() {
        _isCached = cached;
        _cacheBytes = totalBytes;
      });
    }
  }

  /// 機能2: GPLBキャッシュを強制更新する
  Future<void> _refreshGplbCache() async {
    setState(() => _isRefreshing = true);
    try {
      await MapRepository.instance.clearAndRefresh();
      await _loadCacheStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(GapLessL10n.t('settings_map_updated')),
            backgroundColor: _kEmerald,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(GapLessL10n.t('settings_update_failed').replaceAll('@error', '$e')),
            backgroundColor: _kAmber,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  /// 言語を変更
  Future<void> _changeLanguage(String lang) async {
    await GapLessL10n.setLanguage(lang);

    // LanguageProviderを更新して全画面を再描画
    if (mounted) {
      final languageProvider = context.read<LanguageProvider>();
      languageProvider.setLanguage(lang);

      // TTS言語も更新
      final alertProvider = context.read<AlertProvider>();
      alertProvider.onLanguageChanged();

      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SafeText('Language: ${GapLessL10n.currentLanguageName}'),
          duration: const Duration(seconds: 1),
          backgroundColor: _kDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  /// キャッシュをクリア
  ///
  /// 注意: ユーザープロファイル(user_profile_data)・オンボーディング完了フラグ・
  /// パーミッション承認フラグは削除しない。アプリ設定と地図キャッシュのみリセット。
  Future<void> _clearCache() async {
    final prefs = await SharedPreferences.getInstance();

    // 削除するキー: アプリ設定・デモ・GPLB関連のみ（ユーザーデータは保持）
    for (final key in const [
      'target_region',
      'gplb_version',
      'gplb_etag',
      'current_language',
    ]) {
      await prefs.remove(key);
    }

    // マップデータキャッシュファイルも削除
    try {
      await MapRepository.instance.clearAndRefresh();
    } catch (_) {
      // ネットワーク不可の場合は無視（ファイルは削除済み）
    }

    // デフォルトに戻す
    await GapLessL10n.setLanguage('en');

    // キャッシュUIを更新
    await _loadCacheStatus();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SafeText(GapLessL10n.t('clear_cache')),
          duration: const Duration(seconds: 2),
          backgroundColor: _kDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // 言語変更時に再描画
    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _kDark,
        foregroundColor: Colors.white,
        title: Text(
          GapLessL10n.t('set_region'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // Section 1: Localization
          _buildSectionHeader(GapLessL10n.t('set_region')),
          _buildSettingsCard([
            // 地域選択 (現在は日本のみ)
            _buildSettingsRow(
              icon: Icons.public_rounded,
              iconColor: _kAmber,
              title: GapLessL10n.t('set_region'),
              subtitle: GapLessL10n.t('region_japan_tokyo'),
              trailing: const Text('🇯🇵', style: TextStyle(fontSize: 22)),
            ),
            _buildDivider(),
            // 言語選択
            _buildSettingsRow(
              icon: Icons.language_rounded,
              iconColor: _kEmerald,
              title: GapLessL10n.t('set_lang'),
              subtitle: GapLessL10n.currentLanguageName,
              trailing: DropdownButton<String>(
                value: GapLessL10n.lang,
                underline: const SizedBox(),
                icon: const Icon(Icons.expand_more_rounded, color: _kEmerald),
                style: const TextStyle(
                  color: _kDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                items: GapLessL10n.availableLanguages.map((lang) {
                  final flag = GapLessL10n.flagForLanguage(lang);
                  final name = GapLessL10n.nameForLanguage(lang);
                  return DropdownMenuItem(
                    value: lang,
                    child: Text('$flag $name'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) _changeLanguage(value);
                },
              ),
            ),
            _buildDivider(),
            // チュートリアルを見る
            _buildSettingsRow(
              icon: Icons.school_rounded,
              iconColor: const Color(0xFF5B9CF6),
              title: _getTutorialLabel(),
              subtitle: _getTutorialDescription(),
              trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFBDBDBD)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TutorialScreen(
                      onComplete: () => Navigator.pop(context),
                    ),
                  ),
                );
              },
            ),
          ]),

          const SizedBox(height: 24),

          _buildSettingsCard([
            _buildSettingsRow(
              icon: Icons.cleaning_services_rounded,
              iconColor: _kAmber,
              title: GapLessL10n.t('clear_cache'),
              subtitle: GapLessL10n.t('msg_reset_desc'),
              trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFBDBDBD)),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: Text(
                      GapLessL10n.t('clear_cache'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _kDark,
                      ),
                    ),
                    content: Text(GapLessL10n.t('label_are_you_sure')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(
                          GapLessL10n.t('btn_cancel'),
                          style: TextStyle(color: _kDark.withOpacity(0.5)),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(
                          GapLessL10n.t('btn_clear'),
                          style: const TextStyle(
                            color: _kAmber,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await _clearCache();
                }
              },
            ),
          ]),

          const SizedBox(height: 24),

          // 機能2: GPLBオフライン地図データ管理
          _buildSectionHeader(GapLessL10n.t('section_offline_map')),
          _buildSettingsCard([
            _buildSettingsRow(
              icon: _isCached ? Icons.map_rounded : Icons.map_outlined,
              iconColor: _isCached ? _kEmerald : const Color(0xFFBDBDBD),
              title: _isCached ? '${GapLessL10n.t("section_offline_map")}: ${GapLessL10n.t("map_data_cached")}' : '${GapLessL10n.t("section_offline_map")}: ${GapLessL10n.t("map_data_not_cached")}',
              subtitle: _isCached
                  ? GapLessL10n.tParams('map_data_size', {'size': (_cacheBytes / 1024).toStringAsFixed(0)})
                  : GapLessL10n.t('map_data_download_needed'),
              trailing: _isRefreshing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(_kEmerald),
                      ),
                    )
                  : GestureDetector(
                      onTap: _refreshGplbCache,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _kEmerald.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.refresh_rounded, color: _kEmerald, size: 20),
                      ),
                    ),
            ),
            if (_isCached) ...[
              _buildDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: _kEmerald, size: 16),
                    const SizedBox(width: 8),
                    SafeText(
                      GapLessL10n.t('offline_nav_ok'),
                      style: safeStyle(size: 13, color: _kEmerald),
                    ),
                  ],
                ),
              ),
            ],
          ]),

          const SizedBox(height: 24),

          // GPS位置情報セクション
          _buildSectionHeader(GapLessL10n.t('settings_gps')),
          _buildSettingsCard([
            Consumer<LocationProvider>(
              builder: (context, locationProvider, _) {
                return Column(
                  children: [
                    // GPS追跡スイッチ
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _kEmerald.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.gps_fixed_rounded, color: _kEmerald, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SafeText(
                                  GapLessL10n.t('lbl_gps_tracking'),
                                  style: emergencyTextStyle(isBold: true),
                                ),
                                SafeText(
                                  locationProvider.isTracking
                                      ? GapLessL10n.t('status_tracking_on')
                                      : GapLessL10n.t('status_tracking_off'),
                                  style: emergencyTextStyle(size: 13, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: locationProvider.isTracking,
                            activeColor: _kEmerald,
                            onChanged: (value) async {
                              if (value) {
                                await locationProvider.startLocationTracking();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: SafeText(GapLessL10n.t('msg_tracking_start')),
                                    backgroundColor: _kDark,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14)),
                                    margin: const EdgeInsets.all(16),
                                  ),
                                );
                              } else {
                                locationProvider.stopLocationTracking();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: SafeText(GapLessL10n.t('msg_tracking_stop')),
                                      backgroundColor: _kDark,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14)),
                                      margin: const EdgeInsets.all(16),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    _buildDivider(),
                    // 現在位置情報表示
                    _buildSettingsRow(
                      icon: Icons.location_on_rounded,
                      iconColor: _kAmber,
                      title: GapLessL10n.t('lbl_current_location'),
                      subtitleWidget: locationProvider.currentLocation != null
                          ? SafeText(
                              '${locationProvider.currentLocationName}\n'
                              '${locationProvider.currentLocation!.latitude.toStringAsFixed(6)}, '
                              '${locationProvider.currentLocation!.longitude.toStringAsFixed(6)}',
                              style: emergencyTextStyle(size: 12, color: Colors.grey),
                            )
                          : SafeText(
                              GapLessL10n.t('lbl_no_location'),
                              style: emergencyTextStyle(size: 13, color: Colors.grey),
                            ),
                      trailing: locationProvider.currentLocation != null
                          ? GestureDetector(
                              onTap: () {
                                locationProvider.exitDemoMode();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: SafeText(GapLessL10n.t('msg_location_cleared')),
                                    backgroundColor: _kDark,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14)),
                                    margin: const EdgeInsets.all(16),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.clear_rounded, color: Colors.red, size: 18),
                              ),
                            )
                          : null,
                    ),
                  ],
                );
              },
            ),
          ]),

          const SizedBox(height: 24),

          // Section 3: About
          _buildSectionHeader(GapLessL10n.t('set_about')),
          _buildSettingsCard([
            _buildSettingsRow(
              icon: Icons.info_rounded,
              iconColor: _kEmerald,
              title: '${GapLessL10n.t('app_version')} 1.0.0',
              subtitle: GapLessL10n.t('label_gapless_project'),
            ),
            _buildDivider(),
            _buildSettingsRow(
              icon: Icons.developer_mode_rounded,
              iconColor: const Color(0xFF5B9CF6),
              title: GapLessL10n.t('app_credit'),
              subtitle: GapLessL10n.t('label_developed_for'),
            ),
          ]),

          const SizedBox(height: 48),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Design helpers
  // -----------------------------------------------------------------------

  /// Section header: small caps emerald label
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _kEmerald,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  /// Rounded card that wraps a group of settings rows
  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 70,
      endIndent: 0,
      color: _kDark.withOpacity(0.06),
    );
  }

  /// A single settings row with icon badge, title, optional subtitle and trailing
  Widget _buildSettingsRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? subtitleWidget,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Icon badge
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              // Texts
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kDark,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (subtitleWidget != null) ...[
                      const SizedBox(height: 2),
                      subtitleWidget,
                    ] else if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: _kDark.withOpacity(0.45),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// チュートリアルラベル
  String _getTutorialLabel() {
    switch (GapLessL10n.lang) {
      case 'ja':
        return 'チュートリアルを見る';
      case 'th':
        return 'ดูบทช่วยสอน';
      default:
        return 'View Tutorial';
    }
  }

  /// チュートリアル説明
  String _getTutorialDescription() {
    switch (GapLessL10n.lang) {
      case 'ja':
        return 'アプリの使い方を確認';
      case 'th':
        return 'ดูวิธีใช้แอป';
      default:
        return 'Learn how to use the app';
    }
  }
}
