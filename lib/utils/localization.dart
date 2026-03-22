import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 緊急時に最適化された短文ローカライゼーション
/// 0.1秒で理解できる体言止め・単語を中心とした翻訳
class GapLessL10n {
  // 現在の言語 ('ja' or 'en' or 'th')
  static String lang = 'ja';
  
  static const String _langKey = 'app_language';

  // 短文・体言止めを中心とした翻訳辞書
  static const Map<String, Map<String, String>> _values = {
    'ja': {
      'title': 'GapLess',
      // Safety Check Dialog
      'dialog_safety_title': '安全確認',
      'dialog_safety_desc': '避難所に到着しましたか？\nナビゲーションを終了し、生活支援モードに切り替えます。',
      'btn_yes_arrived': 'はい、到着しました',
      'btn_cancel': 'キャンセル',

      // Bot Messages
      'bot_analyzing': '分析中...',
      'bot_loc_error': '⚠️ 位置情報が取得できません。',
      'bot_found': '🔍 **施設が見つかりました**',
      'bot_found_desc': '現在地から **@dist** 先に「**@name**」があります。地図上のアイコンを目指してください。',
      'bot_prefix_normal': '落ち着いてください。私たちがついています。',
      'bot_prefix_name': '落ち着いてください、@nameさん。私たちがついています。',
      'bot_not_found': '⚠️ **近くに見つかりません**',
      'bot_not_found_desc': '半径3km以内に該当する施設データがありません。とりあえず「避難所」へ向かうことを推奨します。',
      'bot_go_to': '「@name」へ向かう',
      'bot_dest_set': '目的地を設定: @name',
      'bot_dest_changed': '目的地を変更: @old → @new',

      // Profile / Emergency Gear
      'header_emergency_gear': 'Emergency Gear / プロフィール',
      'label_name': 'Name / 氏名',
      'label_nation': 'Nationality / 国籍',
      'label_blood': 'Blood Type / 血液型',
      'label_allergies': 'Allergies / アレルギー',
      'label_needs': 'Special Needs / 配慮事項',
      'label_unknown': 'Unknown',
      'label_edit': 'Edit Profile / 編集',

      // Shelter Dashboard
      'header_safe_banner_title': '避難所に到着済み',
      'header_safe_banner_desc': '現在は安全な場所にいます',
      'header_survival_guide': '公式サバイバルガイド',
      'btn_show_staff': 'Emergency Gear (スタッフに見せる)',

      // Compass
      'waiting_destination': '目的地を設定してください...',
      'btn_arrived_label': '避難所に到着',

      // Settings
      'set_region': '地域設定',
      'set_lang': '言語',
      'set_demo': 'デモ設定',
      
      // Compass Messages
      'loc_permission_denied': '位置情報が許可されていません',
      'loc_open_settings': '設定を開く',
      'loc_acquiring': '位置情報を取得中...',
      'loc_no_destination': '目的地を設定してください',
      'loc_select_in_chat': '下のチャットで「避難所」を選んでください',
      
      'header_ai_guide': 'AI避難ガイド',
      'hint_name': '山田 太郎',
      
      // Chips - Allergies
      'allergy_eggs': '卵',
      'allergy_peanuts': 'ピーナッツ',
      'allergy_milk': '牛乳',
      'allergy_seafood': '魚介類',
      'allergy_wheat': '小麦',
      
      // Chips - Needs
      'need_wheelchair': '車椅子',
      'need_visual': '視覚障害',
      'need_hearing': '聴覚障害',
      'need_pregnancy': '妊娠中',
      'need_infant': '乳幼児',
      'need_halal': 'ハラル',

      // Chat Interface
      'chat_prompt_main': 'お困りのことは何ですか？\n以下から選択してください。',
      'chat_btn_more': 'その他の相談',
      'chat_btn_back': 'メニューに戻る',

      // Survival Guide Titles
      'guide_economy': 'エコノミークラス症候群',
      'guide_infection': '感染症対策',
      'guide_poisoning': '食中毒予防',
      'guide_insulation': '寒さ・暑さ対策',
      'guide_crime': '防犯対策',
      'guide_rhythm': '生活リズム',
      'guide_chronic': '持病・薬',
      'guide_religion': '宗教的配慮',
      'guide_pet': 'ペット同行避難',
      'guide_mental': '心のケア',
      'guide_care': '介護・介助',
      'guide_hygiene': 'トイレ・衛生',
      'guide_battery': 'スマホ・電源',
      'guide_female': '女性のケア',
      'guide_info': '情報の集め方',
      'guide_money': 'お金・貴重品',
      
      // Thailand Official
      'guide_electric': '感電注意',
      'guide_disease': '水害感染症',
      'guide_animals': '毒害生物',
      'guide_water_food': '水・食料衛生',
      'guide_heat': '熱中症',
      'guide_emergency': '緊急連絡先',

      // Thailand Support
      'guide_drowning': '水の事故',
      'guide_boat_safety': 'ボート移動',
      'guide_fungal': '足の真菌症',
      'guide_toilet_th': 'トイレ衛生',
      'guide_mental_th': '心のケア',
      'guide_documents': '重要書類',
      'guide_garbage': 'ゴミ処理',
      'guide_chronic_th': '持病管理',
      'guide_community': '助け合い',
      'guide_leech': 'ヒル・虫',

      // Chat Headers
      'header_category_guide': '公式サバイバルガイド (重要6項目)',
      'header_category_ai': 'AI生活サポート (その他の相談)',
      
      // Headers & Buttons
      'online_ai_btn': 'オンラインAI',
      'header_shelter_support': '避難生活サポート',
      'btn_talk_ai': 'サポートAIと話す',
      'btn_emergency_gear': 'Emergency Gear (必須アイテム)',
      
      // Dialogs & Misc
      'btn_clear': 'クリア',
      'msg_reset_desc': 'すべての設定をリセット',
      'msg_no_data': 'データが見つかりません',
      'label_gapless_project_main': 'GapLess プロジェクト',
      'label_gapless_project': 'GapLess プロジェクト',
      'label_developed_for': '未踏ジュニア開発',
      'msg_network_restored': '通信が復旧しました。マップに戻ります。',
      'msg_unknown_location': '詳細な場所が不明なため案内できません',
      'msg_no_facility_nearby': '近くに施設が見つかりませんでした',
      
      // Settings - GPS
      'lbl_gps_tracking': 'GPS追跡',
      'status_tracking_on': '現在位置を追跡中',
      'status_tracking_off': '位置の追跡を開始',
      'msg_tracking_start': 'GPS追跡を開始しました',
      'msg_tracking_stop': 'GPS追跡を停止しました',
      'lbl_current_location': '現在位置',
      'lbl_no_location': '位置情報なし',
      'msg_location_cleared': '位置情報をクリアしました',
      
      // Hazards
      'hazard_flood': '洪水警報 (FLOOD)',
      'hazard_earthquake': '地震警報 (EARTHQUAKE)',
      
      // Teleport
      'msg_teleport': 'テレポート: @name',
      
      // Marker Categories (New)
      'marker_shelter': '避難所',
      'marker_food_supply': '食料・物資',
      'marker_flood_shelter': '洪水対応避難所',
      'marker_official_shelter': '指定避難所',
      
      // Popup Details
      'type': 'タイプ',
      'status': 'ステータス',
      'verified': '公式データ',
      'unverified': '未確認データ',
      'official_data': '公式データ',
      'navigate_here': 'ここへ案内',
      'navigation_started': 'へのナビゲーションを開始',
      
      // New Features v2
      'survival_guide_tooltip': '応急処置・サバイバルガイド',
      'triage_tooltip': '怪我のチェック',
      'voice_guidance': '音声ガイダンス',
      'voice_on': '音声ON',
      'voice_off': '音声OFF',
      
      // Shelter Details
      'address': '住所',
      'capacity': '収容人数',
      'capacity_unit': '人',
      'flood_support': '洪水対応',
      'supported': '対応可能',
      'not_supported': '非対応',
      'shop_type': '店舗タイプ',
      'map_launch_failed': '地図アプリを起動できませんでした',
      
      // Safety Navigation
      'msg_safer_location': '⚠️ より安全な場所に変更: @name',
      'msg_route_calculated': '✅ 安全ルート計算完了',
      'msg_hazard_detected': '⚠️ ハザードゾーン検出',
      'msg_avoiding_hazard': 'ハザードを避けたルートで案内',
      
      // Splash Screen
      'splash_loading': '起動中...',
      'splash_loading_lang': '言語データを読み込み中...',
      'splash_loading_map': 'マップ・避難所データを展開中...',
      'splash_loading_hazard': 'ハザードマップを生成中(2000地点)...',
      'splash_ready': '準備完了',

      // Offline Banner
      'offline_banner': 'オフラインモード：保存済みデータを使用中',

      // Disaster Mode Confirmation
      'disaster_mode_confirm_title': '災害モードを起動しますか？',
      'disaster_mode_confirm_body': 'コンパスナビゲーションに切り替え、最寄り避難所への誘導を開始します。',
      'disaster_mode_confirm_ok': '起動する',

      // Map Data Download Screen
      'map_download_title': 'マップデータをダウンロード中',
      'map_download_note': '初回のみ必要です。Wi-Fi環境を推奨します。',
      'map_download_error': 'ダウンロードに失敗しました',
      'map_no_connection': 'インターネット接続がありません。\nWi-Fiまたはモバイルデータをオンにしてください。',
      'map_download_failed': '@filename の取得に失敗しました。\n再試行してください。',
      'map_download_retry': '再試行',
      'map_download_done': 'ダウンロード完了',
      'map_info_added': '情報を追加しました',
      'map_tap_hint': '地図をタップして危険情報を追加',
      'map_hazard_title': '危険情報を追加',
      'map_hazard_hint': 'この地点の危険情報を記録し、近くのiPhoneと自動共有します。個人情報は一切収集しません。',
      'map_submit': 'ここに情報を追加する',
      'map_submitting': '送信中...',
      'map_ble_syncing': '@count台と同期中',
      'map_ble_waiting': 'BLE待機中',

      'splash_subtitle': '災害時ナビゲーション',
      'splash_disclaimer_title': 'ご利用の前に',
      'splash_disclaimer_jp': 'このアプリは避難を補助するものであり、安全を完全に保証するものではありません。最終的な避難判断は、ご自身の責任で行ってください。',
      'splash_disclaimer_en': 'This app assists evacuation but does not guarantee safety. Final evacuation decisions must be made at your own risk and responsibility.',
      'splash_warning': '緊急時は公式の避難指示に従ってください',
      'splash_agree': '同意して開始',
      
      // Map Screen
      'map_title': 'マップ',
      'compass_mode_on': 'コンパスモード: ON',
      'compass_mode_off': 'コンパスモード: OFF',
      'shelter_count': '@count 避難所',
      'label_type': 'タイプ',
      'label_coordinates': '座標',
      'label_status': 'ステータス',
      'navigation_developing': 'ナビゲーション機能は開発中です',
      
      // Profile Edit Screen
      'profile_saved': '保存しました',
      'profile_settings': 'プロフィール設定',
      'profile_save': '保存する',
      
      // Triage Screen
      'triage_title': '怪我のチェック',
      'triage_back': '戻る',
      'triage_recommendation': '推奨される行動',
      'triage_go_hospital': '最寄りの病院へ案内',
      'triage_go_shelter': '避難所へ案内',
      'triage_restart': 'やり直す',
      'location_not_available': '位置情報が取得できません',
      
      // Directions
      'dir_north': '北',
      'dir_northeast': '北東',
      'dir_east': '東',
      'dir_southeast': '南東',
      'dir_south': '南',
      'dir_southwest': '南西',
      'dir_west': '西',
      'dir_northwest': '北西',
      
      // Risk Radar
      'risk_radar_title': 'リスクレーダー',
      'risk_loading': 'リスクデータを読み込み中...',
      'risk_high': '⚠️ 高リスク - 慎重に移動してください',
      'risk_medium': '注意 - 危険な方向があります',
      'risk_low': '周囲は比較的安全です',

      // Danger Zone Banner
      'danger_hazard_title': '危険エリア内にいます',
      'danger_hazard_sub': 'ハザードゾーン内です。すぐに移動してください。',
      'danger_flood_title': '洪水リスクエリアです',
      'danger_flood_sub': '浸水リスクが高い場所にいます。高台へ避難してください。',
      'danger_power_title': '感電リスクエリアです',
      'danger_power_sub': '電力設備の近くにいます。水溜りに注意してください。',
      'danger_dismiss': '閉じる',
      // Overlay Toggles
      'overlay_flood': '洪水',
      'overlay_power': '感電',

      // Turn-by-turn navigation
      'nav_straight': '直進',
      'nav_turn_right': '右折',
      'nav_turn_left': '左折',
      'nav_u_turn': 'Uターン',
      'nav_dist_ahead': '@dist先',
      'nav_to_dest': '目的地まで',
      'nav_arrived_panel': '目的地に到着しました',

      // Calibration overlay
      'cal_paused': '案内を一時停止中',
      'cal_sensor_warning': '磁気センサーに乱れを検知しました',
      'cal_instruction': '端末を八の字に振って\nコンパスを補正してください',
      'cal_skip': 'スキップして続ける',
      'cal_divergence': 'GPSとコンパスの方位が@deg°ずれています',

      // Return home compass
      'return_mode_label': '帰還支援モード',
      'return_dist_label': '最後に既知だった地点まで',
      'return_backtrack_btn': 'バックトラック（来た道を戻る）',

      // Quick report sheet
      'qr_title': 'この場所の状況を報告',
      'qr_no_photo': '（写真なし）',
      'qr_passable': '通れた',
      'qr_passable_sub': '道路は通行可能でした',
      'qr_blocked': '通れない',
      'qr_blocked_sub': '道路が塞がれています',
      'qr_danger': '危険な場所がある',
      'qr_danger_sub': '倒壊・火災・浸水など',
      'qr_reported': '「@label」を報告しました',

      // Dead reckoning badge
      'dr_badge': 'GPS消失 - 推定位置使用中 (@steps歩)',

      // Navigation screen
      'nav_screen_title': '安全ルート案内',
      'nav_arrive_title': '目的地に到着しました',
      'nav_arrive_body': '避難所に安全に到着しましたか？\n確認すると避難所ダッシュボードを表示します。',
      'nav_still_moving': 'まだ移動中',
      'nav_safe_confirm': '安全を確認',
      'nav_profile_title': '移動プロファイル',
      'nav_profile_standard': '標準',
      'nav_profile_standard_sub': '通常歩行 (1.2 m/s)',
      'nav_profile_elderly': '高齢者モード',
      'nav_profile_elderly_sub': 'ゆっくり歩行 (0.9 m/s)',
      'nav_profile_wheelchair': '車椅子モード',
      'nav_profile_wheelchair_sub': '平坦路優先 (0.8 m/s)',
      'nav_no_location': '現在地を取得できません',
      'nav_no_shelter': '近くに避難所が見つかりません',
      'nav_route_calculated': '@name へのルートを計算しました',
      'nav_calculating': 'ルートを計算中…',
      'nav_loading_map': '地図データを読み込み中…',
      'nav_reported_passable': '「通れる」を報告しました',
      'nav_reported_blocked': '「通れない」を報告しました',
      'nav_route_to': '@name へのルートを計算中…',
      'nav_tab_map': 'ナビ',
      'nav_tab_card': '緊急カード',
      'nav_tab_guide': '生存ガイド',
      'nav_tab_settings': '設定',
      'nav_tooltip_photo': '写真で即時報告',
      'nav_tooltip_report': '道路状況を報告',
      'nav_nearest_shelter': '最寄り避難所へ',
      'road_report_title': '現在地の道路状況を報告',
      'road_report_hint': 'この報告はBluetooth経由で近くのユーザーと共有されます。',
      'report_passable': '通れる',
      'report_blocked': '通れない',
      'gps_none': 'GPS未取得',
      'ble_off': 'BLE停止',
      'power_saving': '省電力',

      // Home screen
      'home_no_location': '現在地が取得できません',
      'home_danger_title': '危険を報告',
      'home_report_passable': 'この道は通れた',
      'home_report_blocked': 'この道は通れない',
      'home_report_danger': '危険な場所がある',
      'home_report_sent': '報告を送信しました',

      // Settings screen
      'settings_map_updated': '地図データを最新に更新しました',
      'settings_update_failed': '更新に失敗しました: @error',
      'status_safe': '✅ 安全',
      'settings_gps': 'GPS位置情報',
      'set_about': 'このアプリについて',
      'region_miyagi': '🇯🇵 宮城県（日本）',
      'region_satun': '🇹🇭 サトゥーン（タイ）',
      'demo_hazard': '🚨 災害モード',
      'demo_hazard_desc': 'デモ: 危険状態を表示',
      'clear_cache': 'キャッシュを削除',
      'app_version': 'バージョン',
      'app_credit': 'Mitouジュニアプロジェクト',

      // TTS voice announcements
      'tts_narrow_road': 'この先の道幅は@widthメートルです。注意してください',
      'tts_turn': '@dist先、@directionに曲がります',
      'tts_dir_right': '右',
      'tts_dir_left': '左',
      'tts_arrived': '目的地に到着しました',
      'tts_waypoint': 'チェックポイント通過。残り@distです',
      'tts_out_of_bounds': '地図データの範囲外です。帰還支援モードに切り替えます',
      'tts_backtrack': '記録済みルートを逆順で案内します',
      'tts_distance_m': '@distメートル',
      'tts_distance_km': '@distキロメートル',
      'tts_danger_ahead': 'この先に危険な場所があります。注意してください',
    },
    'en': {
      // Tabs
      'tab_map': 'Map',
      'tab_guide': 'AI Guide',
      'tab_settings': 'Config',
      
      // Map Status
      'status_safe': '✅ SAFE',
      'status_danger': '⚠️ HAZARD',
      'status_offline': 'OFFLINE',
      
      // Safety Check Dialog
      'dialog_safety_title': 'Safety Check',
      'dialog_safety_desc': 'Have you arrived safely?\nEnd navigation and switch to support mode.',
      'btn_yes_arrived': 'Yes, Arrived',
      'btn_cancel': 'Cancel',
      
      // Bot Messages
      'bot_analyzing': 'Analyzing...',
      'bot_loc_error': '⚠️ Location not available.',
      'bot_found': '🔍 **Facility Found**',
      'bot_found_desc': '"**@name**" is **@dist** away. Please head towards the icon on the map.',
      'bot_prefix_normal': 'Please stay calm. We are with you.',
      'bot_prefix_name': 'Stay calm, @name. We are with you.',
      'bot_not_found': '⚠️ **Not Found Nearby**',
      'bot_not_found_desc': 'No data within 3km. Recommended to head to a "Shelter".',
      'bot_go_to': 'Go to @name',
      'bot_dest_set': 'Destination set: @name',
      'bot_dest_changed': 'Changed: @old -> @new',

      // Profile
      'header_emergency_gear': 'Emergency Gear / Profile',
      'label_name': 'Name',
      'label_nation': 'Nationality',
      'label_blood': 'Blood Type',
      'label_allergies': 'Allergies',
      'label_needs': 'Special Needs',
      'label_unknown': 'Unknown',
      'label_edit': 'Edit Profile',

      // Shelter Dashboard
      'header_safe_banner_title': 'Safe in Shelter',
      'header_safe_banner_desc': 'You are in a safe location.',
      'header_survival_guide': 'Official Survival Guide',
      'btn_show_staff': 'Emergency Gear (Show to Staff)',

      // Compass
      'waiting_destination': 'Waiting for destination...',

      // Navigation
      'nav_dist': 'Dist', // e.g., Dist 300m
      'nav_calib': 'Calibrating...',
      'nav_heading': 'Heading',
      
      // Bot Responses
      'bot_hospital': '🏥 To Hospital',
      'bot_water': '💧 To Water Supply',
      'bot_safe_shelter': '🟢 To Shelter',
      'bot_reroute': '⚠️ Hazard Avoidance',
      'bot_sos': '⛑️ SOS Mode',
      
      // Settings
      'settings_title': 'Settings',
      'settings_language': 'Language',
      'settings_gps': 'GPS Location',
      'settings_demo': 'Demo Settings',
      'set_about': 'About',
      'region_miyagi': '🇯🇵 Miyagi, Japan',
      'region_satun': '🇹🇭 Satun, Thailand',
      'lang_japanese': '日本語',
      'lang_english': 'English',
      'lang_thai': 'ไทย (Thai)',
      'demo_hazard': '🚨 Disaster Mode',
      'demo_hazard_desc': 'Demo: Show danger state',
      'clear_cache': 'Clear Cache',
      'app_version': 'Version',
      'app_credit': 'Mitou Junior Project',
      
      // Compass Messages
      'loc_permission_denied': 'Location Access Denied',
      'loc_open_settings': 'Open Settings',
      'loc_acquiring': 'Acquiring location...',
      'loc_no_destination': 'Please set a destination',
      'loc_select_in_chat': 'Select "Shelter" in chat below',
      
      // Shelter Types
      'shelter_evacuation': 'Shelter',
      'shelter_school': 'School',
      'shelter_hospital': 'Hospital',
      'shelter_government': 'Govt',
      'shelter_temple': 'Temple',
      'shelter_other': 'Other',
      
      // Common
      'title': 'GapLess',
      'shelters': 'Shelters',
      'distance': 'Dist',
      'direction': 'Dir',
      'verified': 'Verified',
      'unverified': 'Unverified',
      'type': 'Type',
      'navigate': 'Navigate',
      'set_region': 'Region Settings',
      'set_lang': 'Language',
      'set_demo': 'Demo Mode',
      'btn_arrived_label': 'Arrived at Shelter',
      
      'header_ai_guide': 'AI Evacuation Guide',
      'hint_name': 'Taro Yamada',
      
      // Chips - Allergies
      'allergy_eggs': 'Eggs',
      'allergy_peanuts': 'Peanuts',
      'allergy_milk': 'Milk',
      'allergy_seafood': 'Seafood',
      'allergy_wheat': 'Wheat',
      
      // Chips - Needs
      'need_wheelchair': 'Wheelchair',
      'need_visual': 'Visual Impairment',
      'need_hearing': 'Hearing Impairment',
      'need_pregnancy': 'Pregnancy',
      'need_infant': 'Infant',
      'need_halal': 'Halal',

      // Chat Interface
      'chat_prompt_main': 'How can I help?\nPlease select a topic.',
      'chat_btn_more': 'Other Topics',
      'chat_btn_back': 'Back to Menu',

      // Survival Guide Titles
      'guide_economy': 'Economy Class Syn.',
      'guide_infection': 'Infection Control',
      'guide_poisoning': 'Food Safety',
      'guide_insulation': 'Insulation',
      'guide_crime': 'Crime Prevention',
      'guide_rhythm': 'Daily Rhythm',
      'guide_chronic': 'Chronic Illness',
      'guide_religion': 'Religious Needs',
      'guide_pet': 'Pet Care',
      'guide_mental': 'Mental Care',
      'guide_care': 'Nursing Care',
      'guide_hygiene': 'Toilet & Hygiene',
      'guide_battery': 'Battery Saving',
      'guide_female': 'Women\'s Care',
      'guide_info': 'Info Gathering',
      'guide_money': 'Cash & Valuables',

      // Thailand Official
      'guide_electric': 'Electrical Safety',
      'guide_disease': 'Flood Diseases',
      'guide_animals': 'Poisonous Animals',
      'guide_water_food': 'Clean Water/Food',
      'guide_heat': 'Heatstroke',
      'guide_emergency': 'Emergency #',

      // Thailand Support
      'guide_drowning': 'Drowning Prev.',
      'guide_boat_safety': 'Boat Safety',
      'guide_fungal': 'Fungal Infection',
      'guide_toilet_th': 'Sanitation',
      'guide_mental_th': 'Mental Health',
      'guide_documents': 'Important Docs',
      'guide_garbage': 'Garbage Disposal',
      'guide_chronic_th': 'Chronic Disease',
      'guide_community': 'Community Help',
      'guide_leech': 'Leeches/Insects',

      // Chat Headers
      'header_category_guide': 'Official Survival Guide',
      'header_category_ai': 'AI Life Support',
      
      // Headers & Buttons
      'online_ai_btn': 'Online AI',
      'header_shelter_support': 'Shelter Support',
      'btn_talk_ai': 'Talk to AI Support',
      'btn_emergency_gear': 'Emergency Gear',
      
      // Dialogs & Misc
      'btn_clear': 'Clear',
      'msg_reset_desc': 'Reset all settings',
      'msg_no_data': 'No data found',
      'label_gapless_project_main': 'GapLess Project',
      'label_gapless_project': 'GapLess Project',
      'label_developed_for': 'Developed for Mitou Junior',
      'msg_network_restored': 'Network Restored. Returning to Map...',
      'msg_unknown_location': 'Cannot guide to unknown location',
      'msg_no_facility_nearby': 'No facility found nearby',
      
      // Settings - GPS
      'lbl_gps_tracking': 'GPS Tracking',
      'status_tracking_on': 'Tracking in real-time',
      'status_tracking_off': 'Start location tracking',
      'msg_tracking_start': 'GPS tracking started',
      'msg_tracking_stop': 'GPS tracking stopped',
      'lbl_current_location': 'Current Location',
      'lbl_no_location': 'No location',
      'msg_location_cleared': 'Location cleared',
      
      // Hazards
      'hazard_flood': 'FLOOD ALERT',
      'hazard_earthquake': 'EARTHQUAKE ALERT',
      
      // Teleport
      'msg_teleport': 'Warped to @name',
      
      // Marker Categories (New)
      'marker_shelter': 'Shelter',
      'marker_food_supply': 'Food/Supply',
      'marker_flood_shelter': 'Flood Shelter',
      'marker_official_shelter': 'Official Shelter',
      
      // Popup Details
      'official_data': 'Official Data',
      'navigate_here': 'Navigate Here',
      'navigation_started': ' - Navigation started',
      
      // New Features v2
      'survival_guide_tooltip': 'First Aid & Survival Guide',
      'triage_tooltip': 'Injury Check',
      'voice_guidance': 'Voice Guidance',
      'voice_on': 'Voice ON',
      'voice_off': 'Voice OFF',
      
      // Shelter Details
      'address': 'Address',
      'capacity': 'Capacity',
      'capacity_unit': 'people',
      'flood_support': 'Flood Support',
      'supported': 'Available',
      'not_supported': 'Not Available',
      'shop_type': 'Shop Type',
      'map_launch_failed': 'Could not open map app',
      
      // Safety Navigation
      'msg_safer_location': '⚠️ Changed to safer location: @name',
      'msg_route_calculated': '✅ Safe route calculated',
      'msg_hazard_detected': '⚠️ Hazard zone detected',
      'msg_avoiding_hazard': 'Navigating around hazard',
      
      // Splash Screen
      'splash_loading': 'Starting...',
      'splash_loading_lang': 'Loading language data...',
      'splash_loading_map': 'Loading map & shelter data...',
      'splash_loading_hazard': 'Generating hazard map (2000 points)...',
      'splash_ready': 'Ready',

      // Offline Banner
      'offline_banner': 'Offline Mode: Using saved data',

      // Disaster Mode Confirmation
      'disaster_mode_confirm_title': 'Enable Disaster Mode?',
      'disaster_mode_confirm_body': 'Switch to compass navigation and start guidance to the nearest shelter.',
      'disaster_mode_confirm_ok': 'Enable',

      // Map Data Download Screen
      'map_download_title': 'Downloading map data',
      'map_download_note': 'Required only on first launch. Wi-Fi recommended.',
      'map_download_error': 'Download failed',
      'map_no_connection': 'No internet connection.\nPlease enable Wi-Fi or mobile data.',
      'map_download_failed': 'Failed to download @filename.\nPlease retry.',
      'map_download_retry': 'Retry',
      'map_download_done': 'Download complete',
      'map_info_added': 'Information added',
      'map_tap_hint': 'Tap map to add hazard info',
      'map_hazard_title': 'Add Hazard Info',
      'map_hazard_hint': 'This hazard info will be recorded and shared with nearby iPhones via BLE. No personal data is collected.',
      'map_submit': 'Add info here',
      'map_submitting': 'Submitting...',
      'map_ble_syncing': 'Syncing with @count devices',
      'map_ble_waiting': 'BLE standby',

      'splash_subtitle': 'Disaster Navigation',
      'splash_disclaimer_title': 'Disclaimer',
      'splash_disclaimer_jp': 'このアプリは避難を補助するものであり、安全を完全に保証するものではありません。最終的な避難判断は、ご自身の責任で行ってください。',
      'splash_disclaimer_en': 'This app assists evacuation but does not guarantee safety. Final evacuation decisions must be made at your own risk and responsibility.',
      'splash_warning': 'In emergencies, follow official evacuation instructions',
      'splash_agree': 'I Agree',
      
      // Map Screen
      'map_title': 'Map',
      'compass_mode_on': 'Compass Mode: ON',
      'compass_mode_off': 'Compass Mode: OFF',
      'shelter_count': '@count Shelters',
      'label_type': 'Type',
      'label_coordinates': 'Coordinates',
      'label_status': 'Status',
      'navigation_developing': 'Navigation feature is under development',
      
      // Profile Edit Screen
      'profile_saved': 'Saved',
      'profile_settings': 'Profile Settings',
      'profile_save': 'Save',
      
      // Triage Screen
      'triage_title': 'Injury Check',
      'triage_back': 'Back',
      'triage_recommendation': 'Recommended Action',
      'triage_go_hospital': 'Navigate to Nearest Hospital',
      'triage_go_shelter': 'Navigate to Shelter',
      'triage_restart': 'Start Over',
      'location_not_available': 'Location not available',
      
      // Directions
      'dir_north': 'N',
      'dir_northeast': 'NE',
      'dir_east': 'E',
      'dir_southeast': 'SE',
      'dir_south': 'S',
      'dir_southwest': 'SW',
      'dir_west': 'W',
      'dir_northwest': 'NW',
      
      // Risk Radar
      'risk_radar_title': 'Risk Radar',
      'risk_loading': 'Loading risk data...',
      'risk_high': '⚠️ HIGH RISK - Proceed with caution',
      'risk_medium': 'CAUTION - Dangerous directions detected',
      'risk_low': 'Area is relatively safe',

      // Danger Zone Banner
      'danger_hazard_title': 'You are in a danger zone',
      'danger_hazard_sub': 'You are inside a hazard zone. Move immediately.',
      'danger_flood_title': 'Flood risk area',
      'danger_flood_sub': 'High flood risk. Evacuate to higher ground.',
      'danger_power_title': 'Electrocution risk area',
      'danger_power_sub': 'Near electrical equipment. Beware of puddles.',
      'danger_dismiss': 'Dismiss',
      // Overlay Toggles
      'overlay_flood': 'Flood',
      'overlay_power': 'Electric',

      // Turn-by-turn navigation
      'nav_straight': 'Straight',
      'nav_turn_right': 'Turn Right',
      'nav_turn_left': 'Turn Left',
      'nav_u_turn': 'U-turn',
      'nav_dist_ahead': '@dist ahead',
      'nav_to_dest': 'To destination',
      'nav_arrived_panel': 'Arrived!',

      // Calibration overlay
      'cal_paused': 'Navigation paused',
      'cal_sensor_warning': 'Magnetic interference detected',
      'cal_instruction': 'Shake device in a figure-8\nto calibrate compass',
      'cal_skip': 'Skip and continue',
      'cal_divergence': 'GPS & compass differ by @deg°',

      // Return home compass
      'return_mode_label': 'Return Home Mode',
      'return_dist_label': 'To last known position',
      'return_backtrack_btn': 'Backtrack (retrace steps)',

      // Quick report sheet
      'qr_title': 'Report this location',
      'qr_no_photo': '(No photo)',
      'qr_passable': 'Passable',
      'qr_passable_sub': 'Road is clear',
      'qr_blocked': 'Blocked',
      'qr_blocked_sub': 'Road is blocked',
      'qr_danger': 'Danger here',
      'qr_danger_sub': 'Collapse / fire / flood',
      'qr_reported': '"@label" reported',

      // Dead reckoning badge
      'dr_badge': 'GPS lost — Est. position (@steps steps)',

      // Navigation screen
      'nav_screen_title': 'Safe Route',
      'nav_arrive_title': 'Arrived at destination',
      'nav_arrive_body': 'Did you arrive safely at the shelter?\nConfirm to open the shelter dashboard.',
      'nav_still_moving': 'Still moving',
      'nav_safe_confirm': 'Confirm safe',
      'nav_profile_title': 'Movement Profile',
      'nav_profile_standard': 'Standard',
      'nav_profile_standard_sub': 'Normal walking (1.2 m/s)',
      'nav_profile_elderly': 'Elderly mode',
      'nav_profile_elderly_sub': 'Slow walking (0.9 m/s)',
      'nav_profile_wheelchair': 'Wheelchair mode',
      'nav_profile_wheelchair_sub': 'Flat road priority (0.8 m/s)',
      'nav_no_location': 'Location unavailable',
      'nav_no_shelter': 'No shelter found nearby',
      'nav_route_calculated': 'Route to @name calculated',
      'nav_calculating': 'Calculating route...',
      'nav_loading_map': 'Loading map data...',
      'nav_reported_passable': '"Passable" reported',
      'nav_reported_blocked': '"Blocked" reported',
      'nav_route_to': 'Calculating route to @name...',
      'nav_tab_map': 'Nav',
      'nav_tab_card': 'Emergency',
      'nav_tab_guide': 'Guide',
      'nav_tab_settings': 'Settings',
      'nav_tooltip_photo': 'Quick photo report',
      'nav_tooltip_report': 'Report road status',
      'nav_nearest_shelter': 'Nearest shelter',
      'road_report_title': 'Report road status at your location',
      'road_report_hint': 'This report will be shared with nearby users via Bluetooth.',
      'report_passable': 'Passable',
      'report_blocked': 'Blocked',
      'gps_none': 'No GPS',
      'ble_off': 'BLE off',
      'power_saving': 'Power save',

      // Home screen
      'home_no_location': 'Location unavailable',
      'home_danger_title': 'Report Danger',
      'home_report_passable': 'Road is passable',
      'home_report_blocked': 'Road is blocked',
      'home_report_danger': 'Dangerous area',
      'home_report_sent': 'Report sent',

      // Settings screen
      'settings_map_updated': 'Map data updated',
      'settings_update_failed': 'Update failed: @error',

      // TTS voice announcements
      'tts_narrow_road': 'Narrow road ahead: @width meters. Proceed with caution.',
      'tts_turn': 'Turn @direction in @dist',
      'tts_dir_right': 'right',
      'tts_dir_left': 'left',
      'tts_arrived': 'You have arrived at your destination.',
      'tts_waypoint': 'Checkpoint passed. @dist remaining.',
      'tts_out_of_bounds': 'Outside map range. Switching to return home mode.',
      'tts_backtrack': 'Guiding you back along your recorded route.',
      'tts_distance_m': '@dist meters',
      'tts_distance_km': '@dist kilometers',
      'tts_danger_ahead': 'Danger ahead. Please proceed with caution.',
    },
    'th': {
      // Tabs
      'tab_map': 'แผนที่',
      'tab_guide': 'AI',
      'tab_settings': 'ตั้งค่า',
      
      // Map Status
      'status_safe': '✅ ปลอดภัย',
      'status_danger': '⚠️ น้ำท่วม',
      'status_offline': 'ออฟไลน์',
      
      // Safety Check Dialog
      'dialog_safety_title': 'ตรวจสอบความปลอดภัย',
      'dialog_safety_desc': 'คุณถึงที่พักพิงหรือยัง?\nสิ้นสุดการนำทางและเปลี่ยนเป็นโหมดสนับสนุน',
      'btn_yes_arrived': 'ถึงแล้ว',
      'btn_cancel': 'ยกเลิก',
      
      // Bot Messages
      'bot_analyzing': 'กำลังวิเคราะห์...',
      'bot_loc_error': '⚠️ ไม่สามารถระบุตำแหน่งได้',
      'bot_found': '🔍 **พบสถานที่**',
      'bot_found_desc': '「**@name**」อยู่ห่างออกไป **@dist** โปรดมุ่งหน้าไปยังไอคอน',
      'bot_prefix_normal': 'โปรดใจเย็นๆ เราอยู่เคียงข้างคุณ',
      'bot_prefix_name': 'ใจเย็นๆ คุณ @name เราอยู่เคียงข้างคุณ',
      'bot_not_found': '⚠️ **ไม่พบสถานที่ใกล้เคียง**',
      'bot_not_found_desc': 'ไม่มีข้อมูลในระยะ 3 กม. แนะนำให้ไปที่ "ที่พักพิง"',
      'bot_go_to': 'ไปที่ @name',
      'bot_dest_set': 'ตั้งจุดหมาย: @name',
      'bot_dest_changed': 'เปลี่ยน: @old -> @new',

      // Profile
      'header_emergency_gear': 'อุปกรณ์ฉุกเฉิน / โปรไฟล์',
      'label_name': 'ชื่อ',
      'label_nation': 'สัญชาติ',
      'label_blood': 'กรุ๊ปเลือด',
      'label_allergies': 'ภูมิแพ้',
      'label_needs': 'ความช่วยเหลือพิเศษ',
      'label_unknown': 'ไม่ระบุ',
      'label_edit': 'แก้ไขโปรไฟล์',

      // Shelter Dashboard
      'header_safe_banner_title': 'ปลอดภัยในที่พักพิง',
      'header_safe_banner_desc': 'คุณอยู่ในพื้นที่ปลอดภัยแล้ว',
      'header_survival_guide': 'คู่มือเอาตัวรอด',
      'btn_show_staff': 'Emergency Gear (แสดงให้เจ้าหน้าที่)',

      // Compass
      'waiting_destination': 'รอการตั้งจุดหมาย...',

      // Navigation
      'nav_dist': 'ระยะ',
      'nav_calib': 'ปรับเทียบ...',
      'nav_heading': 'ทิศ',
      
      // Bot Responses
      'bot_hospital': '🏥 ไปโรงพยาบาล',
      'bot_water': '💧 ไปน้ำดื่ม',
      'bot_safe_shelter': '🟢 ไปที่พักพิง',
      'bot_reroute': '⚠️ หลีกเลี่ยงอันตราย',
      'bot_sos': '⛑️ โหมด SOS',
      
      // Settings
      'settings_title': 'การตั้งค่า',
      'settings_language': 'ภาษา',
      'settings_gps': 'ตำแหน่ง GPS',
      'settings_demo': 'การตั้งค่าสาธิต',
      'set_about': 'เกี่ยวกับ',
      'region_miyagi': '🇯🇵 มิยากิ, ญี่ปุ่น',
      'region_satun': '🇹🇭 สตูล, ประเทศไทย',
      'lang_japanese': '日本語',
      'lang_english': 'English',
      'lang_thai': 'ไทย (Thai)',
      'demo_hazard': '🚨 โหมดภัยพิบัติ',
      'demo_hazard_desc': 'สาธิต: แสดงสถานะอันตราย',
      'clear_cache': 'ล้างแคช',
      'app_version': 'เวอร์ชัน',
      'app_credit': 'โครงการ Mitou Junior',
      
      // Compass Messages
      'loc_permission_denied': 'ไม่ได้รับอนุญาตให้ใช้ตำแหน่ง',
      'loc_open_settings': 'เปิดการตั้งค่า',
      'loc_acquiring': 'กำลังระบุตำแหน่ง...',
      'loc_no_destination': 'กรุณาตั้งจุดหมายปลายทาง',
      'loc_select_in_chat': 'เลือก "ที่พักพิง" ในแชทด้านล่าง',
      
      // Shelter Types
      'shelter_evacuation': 'ที่พักพิง',
      'shelter_school': 'โรงเรียน',
      'shelter_hospital': 'โรงพยาบาล',
      'shelter_government': 'รัฐบาล',
      'shelter_temple': 'วัด',
      'shelter_other': 'อื่นๆ',
      
      // Common
      'title': 'GapLess',
      'shelters': 'ที่พักพิง',
      'distance': 'ระยะทาง',
      'direction': 'ทิศทาง',
      'verified': 'ยืนยัน',
      'unverified': 'ไม่ยืนยัน',
      'type': 'ประเภท',
      'navigate': 'นำทาง',
      'set_region': 'การตั้งค่าภูมิภาค',
      'set_lang': 'ภาษา',
      'set_demo': 'โหมดสาธิต',
      'btn_arrived_label': 'ถึงที่พักพิงแล้ว',
      
      'header_ai_guide': 'AI แนะนำการอพยพ',
      'hint_name': 'สมชาย ใจดี',
      
      // Chips - Allergies
      'allergy_eggs': 'ไข่',
      'allergy_peanuts': 'ถั่วลิสง',
      'allergy_milk': 'นม',
      'allergy_seafood': 'อาหารทะเล',
      'allergy_wheat': 'แป้งสาลี',
      
      // Chips - Needs
      'need_wheelchair': 'วีลแชร์',
      'need_visual': 'ผู้พิการทางสายตา',
      'need_hearing': 'ผู้พิการทางการได้ยิน',
      'need_pregnancy': 'ตั้งครรภ์',
      'need_infant': 'ทารก',
      'need_halal': 'ฮาลาล',

      // Chat Interface
      'chat_prompt_main': 'มีอะไรให้ช่วยไหมครับ?\nกรุณาเลือกหัวข้อ',
      'chat_btn_more': 'หัวข้ออื่นๆ',
      'chat_btn_back': 'กลับเมนูหลัก',

      // Survival Guide Titles
      'guide_economy': 'โรคชั้นประหยัด',
      'guide_infection': 'การป้องกันการติดเชื้อ',
      'guide_poisoning': 'ความปลอดภัยทางอาหาร',
      'guide_insulation': 'การป้องกันความร้อน/หนาว',
      'guide_crime': 'การป้องกันอาชญากรรม',
      'guide_rhythm': 'จังหวะชีวิต',
      'guide_chronic': 'โรคเรื้อรัง/ยา',
      'guide_religion': 'ความต้องการทางศาสนา',
      'guide_pet': 'สัตว์เลี้ยง',
      'guide_mental': 'สุขภาพจิต',
      'guide_care': 'การดูแลผู้ป่วย',
      'guide_hygiene': 'ห้องน้ำ/สุขอนามัย',
      'guide_battery': 'ประหยัดแบตเตอรี่',
      'guide_female': 'สำหรับผู้หญิง',
      'guide_info': 'การหาข้อมูล',
      'guide_money': 'เงินและของมีค่า',

      // Thailand Official
      'guide_electric': 'ระวังไฟดูด',
      'guide_disease': 'โรคระบาด',
      'guide_animals': 'สัตว์มีพิษ',
      'guide_water_food': 'อาหาร/น้ำ',
      'guide_heat': 'โรคลมแดด',
      'guide_emergency': 'เบอร์ฉุกเฉิน',

      // Thailand Support
      'guide_drowning': 'ป้องกันจมน้ำ',
      'guide_boat_safety': 'ความปลอดภัยทางเรือ',
      'guide_fungal': 'โรคน้ำกัดเท้า',
      'guide_toilet_th': 'สุขา/ขับถ่าย',
      'guide_mental_th': 'สุขภาพจิต',
      'guide_documents': 'เอกสารสำคัญ',
      'guide_garbage': 'การจัดการขยะ',
      'guide_chronic_th': 'โรคประจำตัว',
      'guide_community': 'น้ำใจ',
      'guide_leech': 'ปลิงและแมลง',

      // Chat Headers
      'header_category_guide': 'คู่มือเอาตัวรอด (6 ข้อ)',
      'header_category_ai': 'AI สนับสนุนการใช้ชีวิต',
      // Headers & Buttons
      'online_ai_btn': 'AI ออนไลน์',
      'header_shelter_support': 'สนับสนุนที่พักพิง',
      'btn_talk_ai': 'คุยกับ AI',
      'btn_emergency_gear': 'อุปกรณ์ฉุกเฉิน',
      
      // Dialogs & Misc
      'btn_clear': 'ล้าง',
      'msg_reset_desc': 'รีเซ็ตการตั้งค่าทั้งหมด',
      'msg_no_data': 'ไม่พบจ้อมูล',
      'label_gapless_project_main': 'โครงการ GapLess',
      'label_gapless_project': 'โครงการ GapLess',
      'label_developed_for': 'พัฒนาเพื่อ Mitou Junior',
      'msg_network_restored': 'เชื่อมต่อเครือข่ายแล้ว กำลังกลับไปที่แผนที่...',
      'msg_unknown_location': 'ไม่สามารถนำทางไปยังตำแหน่งที่ไม่รู้จัก',
      'msg_no_facility_nearby': 'ไม่พบสถานที่ใกล้เคียง',
      
      // Settings - GPS
      'lbl_gps_tracking': 'การติดตาม GPS',
      'status_tracking_on': 'กำลังติดตามตำแหน่งแบบเรียลไทม์',
      'status_tracking_off': 'เริ่มติดตามตำแหน่ง',
      'msg_tracking_start': 'เริ่มติดตาม GPS แล้ว',
      'msg_tracking_stop': 'หยุดติดตาม GPS แล้ว',
      'lbl_current_location': 'ตำแหน่งปัจจุบัน',
      'lbl_no_location': 'ไม่มีตำแหน่ง',
      'msg_location_cleared': 'ล้างตำแหน่งแล้ว',
      
      // Hazards
      'hazard_flood': 'แจ้งเตือนน้ำท่วม (FLOOD)',
      'hazard_earthquake': 'แจ้งเตือนแผ่นดินไหว (EARTHQUAKE)',
      
      // Teleport
      'msg_teleport': 'วาร์ปไปที่ @name',
      
      // Marker Categories (New)
      'marker_shelter': 'จุดอพยพ',
      'marker_food_supply': 'จุดเสบียง',
      'marker_flood_shelter': 'ที่หลบน้ำท่วม',
      'marker_official_shelter': 'ที่พักพิงราชการ',
      
      // Popup Details
      'official_data': 'ข้อมูลราชการ',
      'navigate_here': 'นำทางไปที่นี่',
      'navigation_started': ' - เริ่มนำทาง',
      
      // New Features v2
      'survival_guide_tooltip': 'ปฐมพยาบาลและคู่มือเอาตัวรอด',
      'triage_tooltip': 'ตรวจสอบการบาดเจ็บ',
      'voice_guidance': 'คำแนะนำด้วยเสียง',
      'voice_on': 'เสียงเปิด',
      'voice_off': 'เสียงปิด',
      
      // Shelter Details
      'address': 'ที่อยู่',
      'capacity': 'ความจุ',
      'capacity_unit': 'คน',
      'flood_support': 'รองรับน้ำท่วม',
      'supported': 'รองรับ',
      'not_supported': 'ไม่รองรับ',
      'shop_type': 'ประเภทร้าน',
      'map_launch_failed': 'ไม่สามารถเปิดแอปแผนที่',
      
      // Safety Navigation
      'msg_safer_location': '⚠️ เปลี่ยนไปที่ปลอดภัยกว่า: @name',
      'msg_route_calculated': '✅ คำนวณเส้นทางปลอดภัยแล้ว',
      'msg_hazard_detected': '⚠️ พบเขตอันตราย',
      'msg_avoiding_hazard': 'นำทางหลีกเลี่ยงอันตราย',
      
      // Splash Screen
      'splash_loading': 'กำลังเริ่มต้น...',
      'splash_loading_lang': 'กำลังโหลดข้อมูลภาษา...',
      'splash_loading_map': 'กำลังโหลดข้อมูลแผนที่และที่พักพิง...',
      'splash_loading_hazard': 'กำลังสร้างแผนที่อันตราย (2000 จุด)...',
      'splash_ready': 'พร้อมแล้ว',

      // Offline Banner
      'offline_banner': 'ออฟไลน์ | ใช้ข้อมูลท้องถิ่น',

      // Disaster Mode Confirmation
      'disaster_mode_confirm_title': 'เปิดโหมดภัยพิบัติ?',
      'disaster_mode_confirm_body': 'เปลี่ยนไปใช้การนำทางเข็มทิศและเริ่มนำทางไปยังที่พักพิงที่ใกล้ที่สุด',
      'disaster_mode_confirm_ok': 'เปิดใช้งาน',

      // Map Data Download Screen
      'map_download_title': 'กำลังดาวน์โหลดข้อมูลแผนที่',
      'map_download_note': 'ต้องการเฉพาะครั้งแรก แนะนำให้ใช้ Wi-Fi',
      'map_download_error': 'ดาวน์โหลดล้มเหลว',
      'map_no_connection': 'ไม่มีการเชื่อมต่ออินเทอร์เน็ต\nกรุณาเปิด Wi-Fi หรือโมบายดาต้า',
      'map_download_failed': 'ดาวน์โหลด @filename ล้มเหลว\nกรุณาลองใหม่',
      'map_download_retry': 'ลองอีกครั้ง',
      'map_download_done': 'ดาวน์โหลดเสร็จสิ้น',
      'map_info_added': 'เพิ่มข้อมูลแล้ว',
      'map_tap_hint': 'แตะแผนที่เพื่อเพิ่มข้อมูลอันตราย',
      'map_hazard_title': 'เพิ่มข้อมูลอันตราย',
      'map_hazard_hint': 'ข้อมูลนี้จะบันทึกและแชร์กับ iPhone ใกล้เคียงผ่าน BLE โดยไม่เก็บข้อมูลส่วนตัว',
      'map_submit': 'เพิ่มข้อมูลที่นี่',
      'map_submitting': 'กำลังส่ง...',
      'map_ble_syncing': 'กำลังซิงค์กับ @count เครื่อง',
      'map_ble_waiting': 'รอ BLE',

      'splash_subtitle': 'ระบบนำทางภัยพิบัติ',
      'splash_disclaimer_title': 'ข้อตกลง',
      'splash_disclaimer_jp': 'このアプリは避難を補助するものであり、安全を完全に保証するものではありません。最終的な避難判断は、ご自身の責任で行ってください。',
      'splash_disclaimer_en': 'This app assists evacuation but does not guarantee safety. Final evacuation decisions must be made at your own risk and responsibility.',
      'splash_warning': 'ในกรณีฉุกเฉิน ให้ปฏิบัติตามคำสั่งอพยพอย่างเป็นทางการ',
      'splash_agree': 'ยอมรับ',
      
      // Map Screen
      'map_title': 'แผนที่',
      'compass_mode_on': 'โหมดเข็มทิศ: เปิด',
      'compass_mode_off': 'โหมดเข็มทิศ: ปิด',
      'shelter_count': '@count ที่พักพิง',
      'label_type': 'ประเภท',
      'label_coordinates': 'พิกัด',
      'label_status': 'สถานะ',
      'navigation_developing': 'ฟีเจอร์นำทางกำลังพัฒนา',
      
      // Profile Edit Screen
      'profile_saved': 'บันทึกแล้ว',
      'profile_settings': 'ตั้งค่าโปรไฟล์',
      'profile_save': 'บันทึก',
      
      // Triage Screen
      'triage_title': 'ตรวจสอบการบาดเจ็บ',
      'triage_back': 'กลับ',
      'triage_recommendation': 'การดำเนินการที่แนะนำ',
      'triage_go_hospital': 'นำทางไปโรงพยาบาลใกล้สุด',
      'triage_go_shelter': 'นำทางไปที่พักพิง',
      'triage_restart': 'เริ่มใหม่',
      'location_not_available': 'ไม่สามารถระบุตำแหน่งได้',
      
      // Directions
      'dir_north': 'เหนือ',
      'dir_northeast': 'ตะวันออกเฉียงเหนือ',
      'dir_east': 'ตะวันออก',
      'dir_southeast': 'ตะวันออกเฉียงใต้',
      'dir_south': 'ใต้',
      'dir_southwest': 'ตะวันตกเฉียงใต้',
      'dir_west': 'ตะวันตก',
      'dir_northwest': 'ตะวันตกเฉียงเหนือ',
      
      // Risk Radar
      'risk_radar_title': 'เรดาร์ความเสี่ยง',
      'risk_loading': 'กำลังโหลดข้อมูลความเสี่ยง...',
      'risk_high': '⚠️ ความเสี่ยงสูง - โปรดระวัง',
      'risk_medium': 'ระวัง - มีทิศทางอันตราย',
      'risk_low': 'รอบข้างค่อนข้างปลอดภัย',

      // Danger Zone Banner
      'danger_hazard_title': 'คุณอยู่ในพื้นที่อันตราย',
      'danger_hazard_sub': 'อยู่ในเขตอันตราย กรุณาเคลื่อนย้ายทันที',
      'danger_flood_title': 'พื้นที่เสี่ยงน้ำท่วม',
      'danger_flood_sub': 'ความเสี่ยงน้ำท่วมสูง กรุณาอพยพไปที่สูง',
      'danger_power_title': 'พื้นที่เสี่ยงไฟฟ้าดูด',
      'danger_power_sub': 'ใกล้อุปกรณ์ไฟฟ้า ระวังแอ่งน้ำ',
      'danger_dismiss': 'ปิด',
      // Overlay Toggles
      'overlay_flood': 'น้ำท่วม',
      'overlay_power': 'ไฟฟ้า',

      // Turn-by-turn navigation
      'nav_straight': 'ตรงไป',
      'nav_turn_right': 'เลี้ยวขวา',
      'nav_turn_left': 'เลี้ยวซ้าย',
      'nav_u_turn': 'กลับรถ',
      'nav_dist_ahead': 'อีก @dist',
      'nav_to_dest': 'ถึงจุดหมาย',
      'nav_arrived_panel': 'ถึงที่หมายแล้ว!',

      // Calibration overlay
      'cal_paused': 'หยุดนำทางชั่วคราว',
      'cal_sensor_warning': 'ตรวจพบสัญญาณรบกวนแม่เหล็ก',
      'cal_instruction': 'เขย่าอุปกรณ์เป็นรูปเลข 8\nเพื่อปรับเข็มทิศ',
      'cal_skip': 'ข้ามแล้วดำเนินต่อ',
      'cal_divergence': 'GPS และเข็มทิศต่างกัน @deg°',

      // Return home compass
      'return_mode_label': 'โหมดนำทางกลับ',
      'return_dist_label': 'ถึงตำแหน่งสุดท้ายที่ทราบ',
      'return_backtrack_btn': 'ย้อนเส้นทาง (กลับทางเดิม)',

      // Quick report sheet
      'qr_title': 'รายงานสถานที่นี้',
      'qr_no_photo': '(ไม่มีรูปภาพ)',
      'qr_passable': 'ผ่านได้',
      'qr_passable_sub': 'ถนนสามารถผ่านได้',
      'qr_blocked': 'ผ่านไม่ได้',
      'qr_blocked_sub': 'ถนนถูกปิดกั้น',
      'qr_danger': 'มีอันตราย',
      'qr_danger_sub': 'พังถล่ม / ไฟไหม้ / น้ำท่วม',
      'qr_reported': 'รายงาน "@label" แล้ว',

      // Dead reckoning badge
      'dr_badge': 'GPS หาย — ตำแหน่งโดยประมาณ (@steps ก้าว)',

      // Navigation screen
      'nav_screen_title': 'นำทางปลอดภัย',
      'nav_arrive_title': 'ถึงจุดหมายแล้ว',
      'nav_arrive_body': 'คุณมาถึงที่พักพิงอย่างปลอดภัยหรือไม่?\nยืนยันเพื่อเปิดแดชบอร์ดที่พักพิง',
      'nav_still_moving': 'ยังเดินทางอยู่',
      'nav_safe_confirm': 'ยืนยันความปลอดภัย',
      'nav_profile_title': 'โปรไฟล์การเคลื่อนที่',
      'nav_profile_standard': 'มาตรฐาน',
      'nav_profile_standard_sub': 'เดินปกติ (1.2 ม./วินาที)',
      'nav_profile_elderly': 'โหมดผู้สูงอายุ',
      'nav_profile_elderly_sub': 'เดินช้า (0.9 ม./วินาที)',
      'nav_profile_wheelchair': 'โหมดวีลแชร์',
      'nav_profile_wheelchair_sub': 'เส้นทางราบ (0.8 ม./วินาที)',
      'nav_no_location': 'ไม่สามารถรับตำแหน่งได้',
      'nav_no_shelter': 'ไม่พบที่พักพิงใกล้เคียง',
      'nav_route_calculated': 'คำนวณเส้นทางไป @name แล้ว',
      'nav_calculating': 'กำลังคำนวณเส้นทาง...',
      'nav_loading_map': 'กำลังโหลดข้อมูลแผนที่...',
      'nav_reported_passable': 'รายงาน "ผ่านได้" แล้ว',
      'nav_reported_blocked': 'รายงาน "ผ่านไม่ได้" แล้ว',
      'nav_route_to': 'กำลังคำนวณเส้นทางไป @name...',
      'nav_tab_map': 'นำทาง',
      'nav_tab_card': 'การ์ดฉุกเฉิน',
      'nav_tab_guide': 'คู่มือ',
      'nav_tab_settings': 'ตั้งค่า',
      'nav_tooltip_photo': 'รายงานด้วยรูปภาพ',
      'nav_tooltip_report': 'รายงานสภาพถนน',
      'nav_nearest_shelter': 'ที่พักพิงใกล้สุด',
      'road_report_title': 'รายงานสภาพถนนตำแหน่งปัจจุบัน',
      'road_report_hint': 'รายงานนี้จะแชร์กับผู้ใช้ใกล้เคียงผ่าน Bluetooth',
      'report_passable': 'ผ่านได้',
      'report_blocked': 'ผ่านไม่ได้',
      'gps_none': 'ไม่มี GPS',
      'ble_off': 'BLE ปิด',
      'power_saving': 'ประหยัดพลังงาน',

      // Home screen
      'home_no_location': 'ไม่สามารถรับตำแหน่งได้',
      'home_danger_title': 'รายงานอันตราย',
      'home_report_passable': 'ถนนนี้ผ่านได้',
      'home_report_blocked': 'ถนนนี้ผ่านไม่ได้',
      'home_report_danger': 'มีพื้นที่อันตราย',
      'home_report_sent': 'ส่งรายงานแล้ว',

      // Settings screen
      'settings_map_updated': 'อัปเดตข้อมูลแผนที่แล้ว',
      'settings_update_failed': 'อัปเดตล้มเหลว: @error',

      // TTS voice announcements
      'tts_narrow_road': 'ข้างหน้าถนนแคบ @width เมตร โปรดระวัง',
      'tts_turn': 'เลี้ยว @direction อีก @dist',
      'tts_dir_right': 'ขวา',
      'tts_dir_left': 'ซ้าย',
      'tts_arrived': 'คุณถึงจุดหมายแล้ว',
      'tts_waypoint': 'ผ่านจุดตรวจแล้ว เหลืออีก @dist',
      'tts_out_of_bounds': 'อยู่นอกขอบเขตแผนที่ กำลังเปลี่ยนเป็นโหมดนำทางกลับ',
      'tts_backtrack': 'กำลังนำทางย้อนเส้นทางที่บันทึกไว้',
      'tts_distance_m': '@dist เมตร',
      'tts_distance_km': '@dist กิโลเมตร',
      'tts_danger_ahead': 'มีอันตรายข้างหน้า โปรดระวัง',
    },
  };

  /// 翻訳を取得
  static String t(String key) {
    return _values[lang]?[key] ?? key;
  }

  // ── フォント設定 ────────────────────────────────────────────────────────────
  // NotoSansJP  : 日本語・英語・ラテン文字
  // NotoSansThai: タイ語（特殊な文字結合ルールが必要）
  // 両フォントを常に fallback に含めることで豆腐・文字化けを防ぐ

  /// 現在の言語に合ったプライマリフォントファミリ
  static String get currentFont {
    switch (lang) {
      case 'th': return 'NotoSansThai';
      case 'my': return 'NotoSansMyanmar';
      case 'si': return 'NotoSansSinhala';
      case 'hi': case 'ne': return 'NotoSansDevanagari';
      case 'bn': return 'NotoSansBengali';
      case 'zh': return 'NotoSansSC';
      case 'zh_TW': return 'NotoSansTC';
      case 'ko': return 'NotoSansKR';
      case 'ja': return 'NotoSansJP';
      default: return 'NotoSans';
    }
  }

  /// 全フォントを含むフォールバックリスト
  static List<String> get fallbackFonts => const [
    'NotoSansJP', 'NotoSansSC', 'NotoSansTC', 'NotoSansKR',
    'NotoSansThai', 'NotoSansMyanmar', 'NotoSansSinhala',
    'NotoSansDevanagari', 'NotoSansBengali', 'NotoSans', 'sans-serif',
  ];

  /// 任意の [TextStyle] にフォント設定を付与して返す
  /// すべてのカスタム TextStyle はこのメソッドを通すことで
  /// 豆腐・文字化けを防止できる
  static TextStyle safeStyle(TextStyle base) {
    return base.copyWith(
      fontFamily: currentFont,
      fontFamilyFallback: fallbackFonts,
    );
  }



  /// 言語を切り替えて保存
  static Future<void> setLanguage(String newLang) async {
    if (_values.containsKey(newLang)) {
      lang = newLang;
      
      // SharedPreferencesに保存
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_langKey, newLang);
    }
  }

  /// SharedPreferencesから言語設定を復元
  static Future<void> loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLang = prefs.getString(_langKey);
      
      if (savedLang != null && _values.containsKey(savedLang)) {
        lang = savedLang;
      }
    } catch (e) {
      // エラー時はデフォルト言語を使用
      lang = 'ja';
    }
  }

  /// 利用可能な言語リスト
  static List<String> get availableLanguages => _values.keys.toList();

  /// 現在の言語の表示名
  static String get currentLanguageName {
    switch (lang) {
      case 'ja':
        return '日本語';
      case 'en':
        return 'English';
      case 'th':
        return 'ไทย';
      default:
        return lang;
    }
  }
  
  /// 言語の絵文字フラグ
  static String get currentLanguageFlag {
    switch (lang) {
      case 'ja':
        return '🇯🇵';
      case 'en':
        return '🇬🇧';
      case 'th':
        return '🇹🇭';
      default:
        return '🌐';
    }
  }

  /// 避難所タイプを翻訳
  static String translateShelterType(String type) {
    bool isJa = lang == 'ja';
    bool isTh = lang == 'th';
    
    switch (type) {
      case 'school':
        return isJa ? '学校' : (isTh ? 'โรงเรียน' : 'School');
      case 'hospital':
        return isJa ? '病院' : (isTh ? 'โรงพยาบาล' : 'Hospital');
      case 'gov':
      case 'government':
      case 'townhall':
        return isJa ? '役所' : (isTh ? 'สำนักงานราชการ' : 'Government Office');
      case 'shelter':
        return isJa ? '避難所' : (isTh ? 'ที่พักพิง' : 'Shelter');
      case 'water':
        return isJa ? '給水所' : (isTh ? 'น้ำดื่ม' : 'Water');
      case 'fuel':
        return isJa ? 'ガソリン' : (isTh ? 'ปั๊มน้ำมัน' : 'Fuel');
      case 'convenience':
        return isJa ? 'コンビニ' : (isTh ? 'ร้านสะดวกซื้อ' : 'Convenience Store');
      case 'supermarket':
        return isJa ? 'スーパー' : (isTh ? 'ซูเปอร์มาร์เก็ต' : 'Supermarket');
      case 'place_of_worship':
      case 'temple':
        return isJa ? '寺院' : (isTh ? 'วัด' : 'Temple');
      case 'community_centre':
        return isJa ? '公民館' : (isTh ? 'ศูนย์ชุมชน' : 'Community Center');
      default:
        return isJa ? 'その他' : (isTh ? 'อื่นๆ' : 'Other');
    }
  }
}
