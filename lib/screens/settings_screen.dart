import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/localization.dart';
import '../providers/shelter_provider.dart';
import '../providers/location_provider.dart';
import '../providers/language_provider.dart';
import '../providers/user_profile_provider.dart';
import '../providers/alert_provider.dart';
import '../data/map_repository.dart';
import '../utils/styles.dart';
import '../widgets/safe_text.dart';
import 'tutorial_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _currentRegion = 'Japan';
  bool _demoHazardMode = false;

  // 機能2: GPLB キャッシュ状態
  bool _isCached = false;
  int _cacheBytes = 0;
  bool _isRefreshing = false;

  // バグ修正: TextEditingController をライフサイクル管理して毎ビルドでの生成・リークを防ぐ
  late final TextEditingController _nameCtrl;
  late final TextEditingController _nationalityCtrl;
  late final TextEditingController _bloodCtrl;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadCacheStatus();
    _nameCtrl = TextEditingController();
    _nationalityCtrl = TextEditingController();
    _bloodCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nationalityCtrl.dispose();
    _bloodCtrl.dispose();
    super.dispose();
  }

  /// 設定を読み込む
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _currentRegion = prefs.getString('target_region') ?? 'Japan';
      _demoHazardMode = prefs.getBool('demo_hazard_mode') ?? false;
    });
  }

  /// 機能2: GPLBキャッシュの状態を読み込む
  Future<void> _loadCacheStatus() async {
    final repo = MapRepository.instance;
    final cached = await repo.isAllDataReady();
    int totalBytes = 0;
    if (cached) {
      for (final f in mapFiles) {
        final path = await repo.localPath(f.localName);
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
            backgroundColor: const Color(0xFF388E3C),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(GapLessL10n.t('settings_update_failed').replaceAll('@error', '$e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  /// 地域を変更
  /// 注意: 地域と言語は独立して管理される。地域を変更しても言語は自動変更しない。
  Future<void> _changeRegion(String region) async {
    setState(() => _currentRegion = region);
    
    // SharedPreferencesに保存
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('target_region', region);
    
    // データを再読み込み
    if (mounted) {
      final provider = context.read<ShelterProvider>();
      provider.setRegion(region);
      
      // 地域と言語は独立 - 地域を変えても言語は変更しない
      // ユーザーが選択した言語で、どの地域のデータも表示される
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SafeText('${GapLessL10n.t('set_region')}: $region'),
          duration: const Duration(seconds: 1),
        ),
      );
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
        ),
      );
    }
  }

  /// デモハザードモードを切り替え
  Future<void> _toggleDemoHazardMode(bool value) async {
    setState(() => _demoHazardMode = value);
    
    // Providerの状態を即座に更新 -> DisasterWatcherが検知して遷移
    if (mounted) {
      context.read<ShelterProvider>().setDisasterMode(value);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('demo_hazard_mode', value);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SafeText(value ? GapLessL10n.t('demo_hazard') : GapLessL10n.t('status_safe')),
          duration: const Duration(seconds: 2),
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
      'demo_hazard_mode',
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
    setState(() {
      _currentRegion = 'Japan';
      _demoHazardMode = false;
    });

    await GapLessL10n.setLanguage('en');

    // キャッシュUIを更新
    await _loadCacheStatus();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SafeText(GapLessL10n.t('clear_cache')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SafeText(GapLessL10n.t('set_region')),
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
// ...
          
          // Section 0: Emergency Gear (New)
          _buildSectionHeader(GapLessL10n.t('header_emergency_gear')),
          _buildProfileEditor(context),
          
          const Divider(),

          // Section 1: Localization
          _buildSectionHeader(GapLessL10n.t('set_region')),
          
          // 地域選択
          ListTile(
            leading: const Icon(Icons.public, color: Color(0xFFE53935)),
            title: Text(GapLessL10n.t('set_region')),
            subtitle: Text(_currentRegion == 'Japan'
                ? GapLessL10n.t('region_miyagi')
                : GapLessL10n.t('region_satun')),
            trailing: DropdownButton<String>(
              value: _currentRegion,
              items: const [
                DropdownMenuItem(value: 'Japan', child: Text('🇯🇵')),
                DropdownMenuItem(value: 'Thailand', child: Text('🇹🇭')),
              ],
              onChanged: (value) {
                if (value != null) _changeRegion(value);
              },
            ),
          ),
          
          const Divider(),
          
          // 言語選択
          ListTile(
            leading: const Icon(Icons.language, color: Color(0xFFE53935)),
            title: Text(GapLessL10n.t('set_lang')),
            subtitle: Text(GapLessL10n.currentLanguageName),
            trailing: DropdownButton<String>(
              value: GapLessL10n.lang,
              items: const [
                DropdownMenuItem(value: 'ja', child: Text('🇯🇵')),
                DropdownMenuItem(value: 'en', child: Text('🇬🇧')),
                DropdownMenuItem(value: 'th', child: Text('🇹🇭')),
              ],
              onChanged: (value) {
                if (value != null) _changeLanguage(value);
              },
            ),
          ),
          
          const Divider(),
          
          // チュートリアルを見る
          ListTile(
            leading: const Icon(Icons.school, color: Color(0xFF43A047)),
            title: Text(_getTutorialLabel()),
            subtitle: Text(_getTutorialDescription()),
            trailing: const Icon(Icons.chevron_right),
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
          
          // 言語選択画面を表示 (DELETED)
          // ListTile( ... )
          
          const SizedBox(height: 24),
          
          // Section 2: Demo Simulation
          _buildSectionHeader(GapLessL10n.t('set_demo')),
          
          SwitchListTile(
            secondary: const Icon(Icons.warning, color: Colors.orange),
            title: Text(GapLessL10n.t('demo_hazard')),
            subtitle: Text(GapLessL10n.t('demo_hazard_desc')),
            value: _demoHazardMode,
            onChanged: _toggleDemoHazardMode,
            activeThumbColor: const Color(0xFFE53935),
          ),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.cleaning_services, color: Color(0xFFE53935)),
            title: Text(GapLessL10n.t('clear_cache')),
            subtitle: Text(GapLessL10n.t('msg_reset_desc')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(GapLessL10n.t('clear_cache')),
                  content: const Text('Are you sure?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(GapLessL10n.t('btn_cancel')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(GapLessL10n.t('btn_clear')),
                    ),
                  ],
                ),
              );
              
              if (confirm == true) {
                await _clearCache();
              }
            },
          ),
          
          const SizedBox(height: 16),
          
          // 機能2: GPLBオフライン地図データ管理
          _buildSectionHeader('オフライン地図データ'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    _isCached ? Icons.map : Icons.map_outlined,
                    color: _isCached ? const Color(0xFF388E3C) : Colors.grey,
                  ),
                  title: Text(_isCached ? '地図データ: キャッシュ済み' : '地図データ: 未ダウンロード'),
                  subtitle: Text(
                    _isCached
                        ? 'サイズ: ${(_cacheBytes / 1024).toStringAsFixed(0)} KB'
                        : 'オフライン使用にはダウンロードが必要です',
                  ),
                  trailing: _isRefreshing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: '地図データを更新',
                          onPressed: _refreshGplbCache,
                        ),
                ),
                if (_isCached)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF388E3C), size: 16),
                        const SizedBox(width: 8),
                        SafeText(
                          GapLessL10n.t('offline_nav_ok'),
                          style: safeStyle(size: 13, color: const Color(0xFF388E3C)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // GPS位置情報セクション
          _buildSectionHeader(GapLessL10n.t('settings_gps')),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Consumer<LocationProvider>(
              builder: (context, locationProvider, _) {
                return Column(
                  children: [
                    // GPS追跡スイッチ
                    SwitchListTile(
                      title: SafeText(
                        GapLessL10n.t('lbl_gps_tracking'),
                        style: emergencyTextStyle(isBold: true),
                      ),
                      subtitle: SafeText(
                        locationProvider.isTracking
                            ? GapLessL10n.t('status_tracking_on')
                            : GapLessL10n.t('status_tracking_off'),
                      ),
                      value: locationProvider.isTracking,
                      onChanged: (value) async {
                        if (value) {
                          await locationProvider.startLocationTracking();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: SafeText(
                                GapLessL10n.t('msg_tracking_start'),
                              ),
                            ),
                          );
                        } else {
                          locationProvider.stopLocationTracking();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: SafeText(
                                  GapLessL10n.t('msg_tracking_stop'),
                                ),
                              ),
                            );
                          }
                        }
                      },
                    ),
                    const Divider(height: 1),
                    // 現在位置情報表示
                    ListTile(
                      leading: const Icon(Icons.location_on),
                      title: SafeText(
                        GapLessL10n.t('lbl_current_location'),
                      ),
                      subtitle: locationProvider.currentLocation != null
                          ? SafeText(
                              '${locationProvider.currentLocationName}\n'
                              '${locationProvider.currentLocation!.latitude.toStringAsFixed(6)}, '
                              '${locationProvider.currentLocation!.longitude.toStringAsFixed(6)}',
                            )
                          : SafeText(
                              GapLessL10n.t('lbl_no_location'),
                            ),
                      trailing: locationProvider.currentLocation != null
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                locationProvider.exitDemoMode();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: SafeText(
                                      GapLessL10n.t('msg_location_cleared'),
                                    ),
                                  ),
                                );
                              },
                            )
                          : null,
                    ),
                  ],
                );
              },
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Section 3: About
          _buildSectionHeader(GapLessL10n.t('set_about')),
          
          GestureDetector(
            onLongPress: _showDeveloperMenu,
            child: ListTile(
              leading: const Icon(Icons.info, color: Color(0xFF43A047)),
              title: Text('${GapLessL10n.t('app_version')} 1.0.0'),
              subtitle: Text(GapLessL10n.t('label_gapless_project')),
            ),
          ),
          
          GestureDetector(
            onLongPress: _showDeveloperMenu,
            child: ListTile(
              leading: const Icon(Icons.developer_mode, color: Color(0xFF43A047)),
              title: Text(GapLessL10n.t('app_credit')),
              subtitle: Text(GapLessL10n.t('label_developed_for')),
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildProfileEditor(BuildContext context) {
    final profileProvider = context.watch<UserProfileProvider>();
    final profile = profileProvider.profile;

    // コントローラーのテキストをプロファイルと同期（フォーカスがない場合のみ）
    if (!_nameCtrl.value.composing.isValid || _nameCtrl.text.isEmpty) {
      if (_nameCtrl.text != profile.name) {
        _nameCtrl.value = TextEditingValue(
          text: profile.name,
          selection: TextSelection.collapsed(offset: profile.name.length),
        );
      }
    }
    if (_nationalityCtrl.text != profile.nationality && !_nationalityCtrl.value.composing.isValid) {
      _nationalityCtrl.value = TextEditingValue(
        text: profile.nationality,
        selection: TextSelection.collapsed(offset: profile.nationality.length),
      );
    }
    if (_bloodCtrl.text != profile.bloodType && !_bloodCtrl.value.composing.isValid) {
      _bloodCtrl.value = TextEditingValue(
        text: profile.bloodType,
        selection: TextSelection.collapsed(offset: profile.bloodType.length),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Name
            TextField(
              decoration: InputDecoration(labelText: GapLessL10n.t('label_name'), hintText: GapLessL10n.t('hint_name')),
              controller: _nameCtrl,
              onChanged: (val) {
                profile.name = val;
                profileProvider.saveProfile(profile);
              },
            ),
            const SizedBox(height: 12),
            // Nation & Blood
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(labelText: GapLessL10n.t('label_nation')),
                    controller: _nationalityCtrl,
                    onChanged: (val) {
                      profile.nationality = val;
                      profileProvider.saveProfile(profile);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(labelText: GapLessL10n.t('label_blood')),
                    controller: _bloodCtrl,
                    onChanged: (val) {
                      profile.bloodType = val;
                      profileProvider.saveProfile(profile);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Medical / Allergies
              Align(
                alignment: Alignment.centerLeft,
                child: SafeText(GapLessL10n.t('label_allergies'), style: emergencyTextStyle(isBold: true, color: Colors.grey)),
              ),
            Wrap(
              spacing: 8,
              children: ['Eggs', 'Peanuts', 'Milk', 'Seafood', 'Wheat'].map((allergy) {
                final isSelected = profile.allergies.contains(allergy);
                
                // Map allergy ID to localization key
                String label = allergy;
                if (allergy == 'Eggs') label = GapLessL10n.t('allergy_eggs');
                else if (allergy == 'Peanuts') label = GapLessL10n.t('allergy_peanuts');
                else if (allergy == 'Milk') label = GapLessL10n.t('allergy_milk');
                else if (allergy == 'Seafood') label = GapLessL10n.t('allergy_seafood');
                else if (allergy == 'Wheat') label = GapLessL10n.t('allergy_wheat');

                return FilterChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      profile.allergies.add(allergy);
                    } else {
                      profile.allergies.remove(allergy);
                    }
                    profileProvider.saveProfile(profile);
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),
            
            // Needs
             Align(
              alignment: Alignment.centerLeft,
              child: SafeText(GapLessL10n.t('label_needs'), style: emergencyTextStyle(isBold: true, color: Colors.grey)),
            ),
             Wrap(
              spacing: 8,
              children: ['Wheelchair', 'Visual Impairment', 'Hearing Impairment', 'Pregnancy', 'Infant', 'Halal'].map((need) {
                final isSelected = profile.needs.contains(need);
                
                // Map need ID to localization key
                String label = need;
                if (need == 'Wheelchair') label = GapLessL10n.t('need_wheelchair');
                else if (need == 'Visual Impairment') label = GapLessL10n.t('need_visual');
                else if (need == 'Hearing Impairment') label = GapLessL10n.t('need_hearing');
                else if (need == 'Pregnancy') label = GapLessL10n.t('need_pregnancy');
                else if (need == 'Infant') label = GapLessL10n.t('need_infant');
                else if (need == 'Halal') label = GapLessL10n.t('need_halal');

                return FilterChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      profile.needs.add(need);
                    } else {
                      profile.needs.remove(need);
                    }
                    profileProvider.saveProfile(profile);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  /// セクションヘッダーを構築 (Existing Method)
  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: SafeText(
        title,
        style: emergencyTextStyle(
          size: 14,
          isBold: true,
          color: const Color(0xFF6B7280),
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




  /// 隠しデベロッパーメニューを表示（LocationProvider対応）
  void _showDeveloperMenu() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: Row(
           children: [
             const Icon(Icons.code, color: Color(0xFF6B7280)),
             const SizedBox(width: 12),
             SafeText(
               '📍 Debug Teleport',
               style: emergencyTextStyle(isBold: true),
             ),
           ],
        ),
        children: [
          // School (Here)
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _teleportToLocation('school');
            },
            child: const ListTile(
              leading: Icon(Icons.school, color: Color(0xFFE53935)),
              title: SafeText('🏫 School (Here)'),
              subtitle: SafeText('Demo Venue'),
            ),
          ),
          
          const Divider(),
          
          // Osaki City Hall
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _teleportToLocation('osaki');
            },
            child: const ListTile(
              leading: Icon(Icons.location_city, color: Color(0xFFE53935)),
              title: SafeText('🇯🇵 Osaki City Hall'),
              subtitle: SafeText('Miyagi, Japan'),
            ),
          ),
          
          const Divider(),
          
          // Thailand (PCSHS Satun)
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _teleportToLocation('thailand');
            },
            child: const ListTile(
              leading: Icon(Icons.public, color: Color(0xFFE53935)),
              title: SafeText('🇹🇭 PCSHS Thailand'),
              subtitle: SafeText('สตูล (Satun)'),
            ),
          ),
        ],
      ),
    );
  }

  /// テレポート機能（LocationProvider使用）
  void _teleportToLocation(String locationKey) {
    if (!mounted) return;
    
    // LocationProviderを使用してテレポート
    final locationProvider = context.read<LocationProvider>();
    locationProvider.teleportForDemo(locationKey);
    
    // 地域を自動設定
    final region = locationProvider.getRegionForLocation(locationKey);
    if (region != null) {
      _changeRegion(region);
    }
    
    // フィードバック
    if (mounted) {
      final name = locationProvider.currentLocationName;
            ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SafeText(
               GapLessL10n.t('msg_teleport').replaceAll('@name', name),
            ),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF6B7280),
        ),
      );
    }
  }
}
