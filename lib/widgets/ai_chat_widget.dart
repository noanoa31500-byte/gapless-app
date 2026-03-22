import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import '../providers/shelter_provider.dart';
import '../providers/location_provider.dart';
import '../providers/user_profile_provider.dart';
import '../models/shelter.dart';

import '../utils/styles.dart';
import '../utils/localization.dart';
import '../services/chat_service.dart';

class AIChatWidget extends StatefulWidget {
  const AIChatWidget({super.key});

  @override
  State<AIChatWidget> createState() => _AIChatWidgetState();
}

class _AIChatWidgetState extends State<AIChatWidget> {
  String _aiMessage = '';
  bool _isAnalyzing = false;
  Shelter? _foundShelter;
  
  @override
  void initState() {
    super.initState();
    _aiMessage = GapLessL10n.lang == 'ja'
        ? '何かお困りですか？下のボタンから選んでください。'
        : GapLessL10n.lang == 'th'
            ? 'มีอะไรให้ฉันช่วยไหม? กรุณาเลือกจากปุ่มด้านล่าง'
            : 'How can I help you? Select from the buttons below.';
    // Note: Ideally this init message should also be in GapLessL10n, 
    // but for now focusing on the dynamic responses which were broken.
  }

  Future<void> _handleUserSelection(String type, String label) async {
    final locationProvider = context.read<LocationProvider>();
    final shelterProvider = context.read<ShelterProvider>();
    // For ChatService
    final userProfile = context.read<UserProfileProvider>().profile;
    
    // 分析中の演出
    setState(() {
      _isAnalyzing = true;
      _aiMessage = GapLessL10n.t('bot_analyzing');
    });

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    // 1. Get Region & Advice
    final region = shelterProvider.currentRegion;
    final countryCode = region.startsWith('th') ? 'TH' : 'JP';
    
    // Map type/label to input text for ChatService
    String inputKey = type; 
    if (type == 'hospital') inputKey = '怪我 blood'; // Trigger injury/blood advice
    if (type == 'water') inputKey = 'water';
    if (type == 'convenience') inputKey = 'food'; // Trigger food/allergy advice
    if (type == 'shelter') inputKey = 'shelter';

    // Import ChatService at top of file first! 
    // Assuming I will add import in next step or this tool call handles file content updates implicitly if I replace whole file? 
    // No, I am replacing a block. I need to ensure import exists. 
    // I will add import in a separate block or assume it's added. 
    // Wait, I can't add import here easily without file context.
    // I'll assume ChatService method is available via import (will fix import in separate call if needed, or if I can replace top too).
    // Actually, I should use `ChatService.generateResponse` here.
    
    // 2. Generate Advice
    // isOffline = true (simulated), isSafeInShelter = shelterProvider.isSafeInShelter
    final botResponse = ChatService.generateResponse(
       inputKey, 
       true, 
       shelterProvider.isSafeInShelter, 
       userProfile,
       region
    );

    final userLoc = locationProvider.currentLocation;
    
    // 3. Find Nearest Logic
    if (userLoc == null) {
      setState(() {
        _isAnalyzing = false;
        _aiMessage = '${botResponse.text}\n\n(位置情報が取得できませんでした)';
      });
      return;
    }

    // 検索タイプのマッピング
    List<String> targetTypes = [type];
    
    // JP/TH Adaptation Logic
    if (type == 'shelter') {
      targetTypes = ['shelter', 'school', 'gov', 'community_centre', 'temple'];
    
    } else if (type == 'hospital') {
      // TH: Include 'doctors' which is mapped to 'hospital' in provider, so 'hospital' type is enough
      targetTypes = ['hospital'];
    
    } else if (type == 'convenience') {
        targetTypes = ['convenience', 'store'];
    
    } else if (type == 'water') {
      // TH Adaptation: Water points are rare, use Convenience Stores (Water bottles)
      if (countryCode == 'TH') {
        targetTypes = ['water', 'convenience', 'store'];
      } else {
        targetTypes = ['water'];
      }
    }

    // 検索実行
    final nearest = shelterProvider.getNearestShelter(
      LatLng(userLoc.latitude, userLoc.longitude),
      includeTypes: targetTypes, 
    );

    setState(() {
      _isAnalyzing = false;
      
      // Combine Advice + Found Info
      String finalMsg = botResponse.text;
      
      if (nearest != null) {
        _foundShelter = nearest;
        final distance = const Distance().as(
          LengthUnit.Meter, 
          LatLng(userLoc.latitude, userLoc.longitude), 
          LatLng(nearest.lat, nearest.lng)
        );
        
        // Add "Found X at Ym" info
        // Simplified to just show name and distance
        final foundText = '「${nearest.name}」 (${distance}m)';
            
        finalMsg += '\n\n----------------\n📍 見つかりました: $foundText\n(地図上の矢印に従ってください)';

      } else {
         _foundShelter = null;
         finalMsg += '\n\n(近くに施設が見つかりませんでした)';
      }
      
      _aiMessage = finalMsg;
    });
  }



  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // AI Message Area
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFE53935).withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFE53935),
                child: Text('AI', style: emergencyTextStyle(color: Colors.white, isBold: true)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _isAnalyzing
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSafeText(
                          _aiMessage,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                        if (_foundShelter != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  // 1. キーボードを閉じる
                                  FocusScope.of(context).unfocus();

                                  final provider = context.read<ShelterProvider>();
                                  final newTarget = _foundShelter!;

                                  // 2. ナビ開始 (Providerを更新するだけで、親のCompassScreenが矢印を更新する)
                                  provider.startNavigation(newTarget);

                                  // 3. フィードバック (SnackBar)
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        GapLessL10n.t('bot_dest_set').replaceAll('@name', newTarget.name),
                                      ),
                                      backgroundColor: Colors.green,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                  
                                  // 画面遷移はしない (コンパス画面のまま、矢印が変わる体験がベスト)
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.navigation, size: 18),
                                label: Text(
                                  GapLessL10n.t('bot_go_to').replaceAll('@name', _foundShelter?.name ?? ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: emergencyTextStyle(isBold: true, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
              ),
            ],
          ),
        ),

        // Action Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildChatChip(
                icon: '💧',
                label: '給水所',
                enLabel: 'Water',
                thLabel: 'น้ำดื่ม',
                onTap: () => _handleUserSelection('water', '給水所'),
              ),
              const SizedBox(width: 8),
              _buildChatChip(
                icon: '🏥',
                label: '病院',
                enLabel: 'Hospital',
                thLabel: 'โรงพยาบาล',
                onTap: () => _handleUserSelection('hospital', '病院'),
              ),
               const SizedBox(width: 8),
              _buildChatChip(
                icon: '🏪',
                label: 'コンビニ',
                enLabel: 'Store',
                thLabel: 'ร้านค้า',
                onTap: () => _handleUserSelection('convenience', 'コンビニ'),
              ),
              const SizedBox(width: 8),
              _buildChatChip(
                icon: '🟢',
                label: '避難所',
                enLabel: 'Shelter',
                thLabel: 'ที่พักพิง',
                onTap: () => _handleUserSelection('shelter', '避難所'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatChip({
    required String icon,
    required String label,
    required String enLabel,
    required String thLabel,
    required VoidCallback onTap,
  }) {
    final text = GapLessL10n.lang == 'ja'
        ? '$icon $label'
        : GapLessL10n.lang == 'th'
            ? '$icon $thLabel'
            : '$icon $enLabel';
            
    return ActionChip(
      label: _buildSafeText(text),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 2,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: onTap,
    );
  }



  // どんな言語がプロンプトから返ってきても、トーフにさせない箱
  Widget translationDisplay(Map<String, String> translatedData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSafeText(translatedData['jp'] ?? '', fontSize: 18),
        _buildSafeText(translatedData['en'] ?? '', fontSize: 16),
        _buildSafeText(translatedData['th'] ?? '', fontSize: 20),
      ],
    );
  }

  Widget _buildSafeText(String text, {double fontSize = 16, Color color = Colors.black}) {
    // ユーザー要望の "NotoApp" 的な堅牢なフォント指定
    // 言語設定やテキスト内容に関わらず豆腐化を防ぐため、Fallbackを指定
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'NotoSansJP', 
        fontFamilyFallback: const ['NotoSansThai', 'sans-serif'], 
        fontSize: fontSize,
        height: 1.5,
        color: color,
      ),
    );
  }
}
