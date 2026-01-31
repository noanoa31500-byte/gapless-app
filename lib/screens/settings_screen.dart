import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/localization.dart';
import '../providers/shelter_provider.dart';
import '../providers/location_provider.dart';
import '../providers/language_provider.dart';
import '../providers/user_profile_provider.dart';
import '../providers/alert_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 設定を読み込む
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentRegion = prefs.getString('target_region') ?? 'Japan';
      _demoHazardMode = prefs.getBool('demo_hazard_mode') ?? false;
    });
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
          content: SafeText('${AppLocalizations.t('set_region')}: $region'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// 言語を変更
  Future<void> _changeLanguage(String lang) async {
    await AppLocalizations.setLanguage(lang);
    
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
          content: SafeText('Language: ${AppLocalizations.currentLanguageName}'),
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
          content: SafeText(value ? AppLocalizations.t('demo_hazard') : AppLocalizations.t('status_safe')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// キャッシュをクリア
  Future<void> _clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    // デフォルトに戻す
    setState(() {
      _currentRegion = 'Japan';
      _demoHazardMode = false;
    });
    
    await AppLocalizations.setLanguage('en');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SafeText(AppLocalizations.t('clear_cache')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SafeText(AppLocalizations.t('set_region')),
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
// ...
          
          // Section 0: Emergency Gear (New)
          _buildSectionHeader(AppLocalizations.t('header_emergency_gear')),
          _buildProfileEditor(context),
          
          const Divider(),

          // Section 1: Localization
          _buildSectionHeader(AppLocalizations.t('set_region')),
          
          // 地域選択
          ListTile(
            leading: const Icon(Icons.public, color: Color(0xFFE53935)),
            title: Text(AppLocalizations.t('set_region')),
            subtitle: Text(_currentRegion == 'Japan'
                ? AppLocalizations.t('region_miyagi')
                : AppLocalizations.t('region_pathum')),
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
            title: Text(AppLocalizations.t('set_lang')),
            subtitle: Text(AppLocalizations.currentLanguageName),
            trailing: DropdownButton<String>(
              value: AppLocalizations.lang,
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
          _buildSectionHeader(AppLocalizations.t('set_demo')),
          
          SwitchListTile(
            secondary: const Icon(Icons.warning, color: Colors.orange),
            title: Text(AppLocalizations.t('demo_hazard')),
            subtitle: Text(AppLocalizations.t('demo_hazard_desc')),
            value: _demoHazardMode,
            onChanged: _toggleDemoHazardMode,
            activeThumbColor: const Color(0xFFE53935),
          ),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.cleaning_services, color: Color(0xFFE53935)),
            title: Text(AppLocalizations.t('clear_cache')),
            subtitle: Text(AppLocalizations.t('msg_reset_desc')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(AppLocalizations.t('clear_cache')),
                  content: const Text('Are you sure?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(AppLocalizations.t('btn_cancel')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(AppLocalizations.t('btn_clear')),
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
          
          // GPS位置情報セクション
          _buildSectionHeader(AppLocalizations.t('settings_gps')),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Consumer<LocationProvider>(
              builder: (context, locationProvider, _) {
                return Column(
                  children: [
                    // GPS追跡スイッチ
                    SwitchListTile(
                      title: SafeText(
                        AppLocalizations.t('lbl_gps_tracking'),
                        style: emergencyTextStyle(isBold: true),
                      ),
                      subtitle: SafeText(
                        locationProvider.isTracking
                            ? AppLocalizations.t('status_tracking_on')
                            : AppLocalizations.t('status_tracking_off'),
                      ),
                      value: locationProvider.isTracking,
                      onChanged: (value) async {
                        if (value) {
                          await locationProvider.startLocationTracking();
                          if (!context.mounted) return;
                                                    ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: SafeText(
                                  AppLocalizations.t('msg_tracking_start'),
                                ),
                              ),
                            );
                          } else {
                            locationProvider.stopLocationTracking();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: SafeText(
                                    AppLocalizations.t('msg_tracking_stop'),
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
                        AppLocalizations.t('lbl_current_location'),
                      ),
                      subtitle: locationProvider.currentLocation != null
                          ? SafeText(
                              '${locationProvider.currentLocationName}\n'
                              '${locationProvider.currentLocation!.latitude.toStringAsFixed(6)}, '
                              '${locationProvider.currentLocation!.longitude.toStringAsFixed(6)}',
                            )
                          : SafeText(
                              AppLocalizations.t('lbl_no_location'),
                            ),
                      trailing: locationProvider.currentLocation != null
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                locationProvider.exitDemoMode();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: SafeText(
                                      AppLocalizations.t('msg_location_cleared'),
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
          _buildSectionHeader(AppLocalizations.t('set_about')),
          
          GestureDetector(
            onLongPress: _showDeveloperMenu,
            child: ListTile(
              leading: const Icon(Icons.info, color: Color(0xFF43A047)),
              title: Text('${AppLocalizations.t('app_version')} 1.0.0'),
              subtitle: Text(AppLocalizations.t('label_gapless_project')),
            ),
          ),
          
          GestureDetector(
            onLongPress: _showDeveloperMenu,
            child: ListTile(
              leading: const Icon(Icons.developer_mode, color: Color(0xFF43A047)),
              title: Text(AppLocalizations.t('app_credit')),
              subtitle: Text(AppLocalizations.t('label_developed_for')),
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildProfileEditor(BuildContext context) {
    // 変更をリアルタイム反映するためConsumerでなくwatch/readとメソッド分離が望ましいが、
    // ここでは簡易編集UIとして実装
    final profileProvider = context.watch<UserProfileProvider>();
    final profile = profileProvider.profile;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Name
            TextField(
              decoration: InputDecoration(labelText: AppLocalizations.t('label_name'), hintText: AppLocalizations.t('hint_name')),
              controller: TextEditingController(text: profile.name)
                ..selection = TextSelection.fromPosition(TextPosition(offset: profile.name.length)),
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
                    decoration: InputDecoration(labelText: AppLocalizations.t('label_nation')),
                    controller: TextEditingController(text: profile.nationality)
                      ..selection = TextSelection.fromPosition(TextPosition(offset: profile.nationality.length)),
                    onChanged: (val) {
                      profile.nationality = val;
                      profileProvider.saveProfile(profile);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(labelText: AppLocalizations.t('label_blood')),
                    controller: TextEditingController(text: profile.bloodType)
                      ..selection = TextSelection.fromPosition(TextPosition(offset: profile.bloodType.length)),
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
                child: SafeText(AppLocalizations.t('label_allergies'), style: emergencyTextStyle(isBold: true, color: Colors.grey)),
              ),
            Wrap(
              spacing: 8,
              children: ['Eggs', 'Peanuts', 'Milk', 'Seafood', 'Wheat'].map((allergy) {
                final isSelected = profile.allergies.contains(allergy);
                
                // Map allergy ID to localization key
                String label = allergy;
                if (allergy == 'Eggs') label = AppLocalizations.t('allergy_eggs');
                else if (allergy == 'Peanuts') label = AppLocalizations.t('allergy_peanuts');
                else if (allergy == 'Milk') label = AppLocalizations.t('allergy_milk');
                else if (allergy == 'Seafood') label = AppLocalizations.t('allergy_seafood');
                else if (allergy == 'Wheat') label = AppLocalizations.t('allergy_wheat');

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
              child: SafeText(AppLocalizations.t('label_needs'), style: emergencyTextStyle(isBold: true, color: Colors.grey)),
            ),
             Wrap(
              spacing: 8,
              children: ['Wheelchair', 'Visual Impairment', 'Hearing Impairment', 'Pregnancy', 'Infant', 'Halal'].map((need) {
                final isSelected = profile.needs.contains(need);
                
                // Map need ID to localization key
                String label = need;
                if (need == 'Wheelchair') label = AppLocalizations.t('need_wheelchair');
                else if (need == 'Visual Impairment') label = AppLocalizations.t('need_visual');
                else if (need == 'Hearing Impairment') label = AppLocalizations.t('need_hearing');
                else if (need == 'Pregnancy') label = AppLocalizations.t('need_pregnancy');
                else if (need == 'Infant') label = AppLocalizations.t('need_infant');
                else if (need == 'Halal') label = AppLocalizations.t('need_halal');

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
    switch (AppLocalizations.lang) {
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
    switch (AppLocalizations.lang) {
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
               AppLocalizations.t('msg_teleport').replaceAll('@name', name),
            ),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF6B7280),
        ),
      );
    }
  }
}
