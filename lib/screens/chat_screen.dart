import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/shelter_provider.dart';
import '../providers/user_profile_provider.dart';
import '../widgets/survival_guide_modal.dart';
import '../widgets/safe_text.dart';
import '../constants/survival_data.dart';
import '../providers/language_provider.dart';
import '../utils/localization.dart';
import '../utils/styles.dart';
import '../utils/thai_sanitation_bot.dart'; // Import Thai Bot

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController(); // Auto-scroll
  bool _isTyping = false;
  String _menuState = 'main'; // 'main' or 'more'

  @override
  void initState() {
    super.initState();
    // Initial greeting
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addBotMessage(GapLessL10n.t('chat_prompt_main'));
    });
  }

  void _addBotMessage(String text, {String? guideId, String? guideLabel}) {
    setState(() {
      _messages.add({
        'type': 'bot', 
        'text': text,
        'guideId': guideId,
        'guideLabel': guideLabel,
      });
      _isTyping = false;
    });
    _scrollToBottom();
  }

  void _addUserMessage(String text) {
    setState(() {
      _messages.add({'type': 'user', 'text': text});
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent, 
          duration: const Duration(milliseconds: 300), 
          curve: Curves.easeOut
        );
      }
    });
  }

  void _handleOptionSelected(String id) {
    // 0. Update UI
    final label = GapLessL10n.t('guide_$id');
    _addUserMessage(label);

    setState(() {
      _isTyping = true;
    });

    // 1. Simulate Delay
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      
      // 2. Find Content
      try {
        final shelterProvider = context.read<ShelterProvider>();
        final region = shelterProvider.currentRegion;
        final allItems = [...SurvivalData.getOfficialGuides(region), ...SurvivalData.getAiSupportGuides(region)];
        final item = allItems.firstWhere((g) => g.id == id);
        
        // 3. Construct Response
        // Use current language
        final lang = GapLessL10n.lang;
        final countryCode = region.startsWith('th') ? 'TH' : 'JP';
        String systemPrompt = _buildFinalPrompt(countryCode, shelterProvider.isSafeInShelter);
        if (kDebugMode) debugPrint('--- [DEBUG] AI System Prompt: \n$systemPrompt ---');
        // Personalization
        final profile = context.read<UserProfileProvider>().profile;
        String prefix = GapLessL10n.t('bot_prefix_normal');
        if (profile.name.isNotEmpty) {
           prefix = GapLessL10n.t('bot_prefix_name').replaceAll('@name', profile.name);
        }

        final title = item.title[lang] ?? item.title['en'] ?? '';
        final action = item.action[lang] ?? item.action['en'] ?? '';
        
        // Combine: "Stay calm, Taro. We are with you.\n\n[Title]\n[Action]"
        String responseText = '';

        if (region.startsWith('th') && shelterProvider.isSafeInShelter) {
           // Use Strict Thai Bot Logic ONLY when arrived
           responseText = ThaiSanitationBot.generateResponse(item.id, lang, profile.name);
        } else {
           // Navigation Phase or Japan: Use Default Logic
           responseText = '$prefix\n\n$title\n\n$action';
        }
        
        _addBotMessage(
          responseText,
          guideId: item.id,
          guideLabel: GapLessL10n.t('chat_btn_back'), 
        );
        
      } catch (e) {
        _addBotMessage("Sorry, I couldn't find info for $id.");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SafeText(
          GapLessL10n.t('header_ai_guide'),
          style: emergencyTextStyle(size: 18, isBold: true),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [

        ],
      ),
      body: Column(
        children: [
          // Message List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isTyping) {
                   return _buildTypingIndicator();
                }

                final message = _messages[index];
                final isBot = message['type'] == 'bot';
                
                return Align(
                  alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: isBot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.8,
                        ),
                        decoration: BoxDecoration(
                          color: isBot
                              ? const Color(0xFFE3F2FD) // Gentle Blue
                              : const Color(0xFFE53935), // User Red
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: isBot ? Radius.zero : const Radius.circular(16),
                            bottomRight: isBot ? const Radius.circular(16) : Radius.zero,
                          ),
                        ),
                        child: _buildSafeText(
                          message['text']!,
                          fontSize: 16,
                          color: isBot ? Colors.black87 : Colors.white,
                        ),
                      ),
                      
                      // View Guide Button (Deep Link)
                      if (isBot && message['guideId'] != null)
                         Container(
                          margin: const EdgeInsets.only(bottom: 12, left: 4),
                          child: ElevatedButton.icon(
                            onPressed: () {
                               // Open Modal
                               final guideId = message['guideId'];
                               if (guideId != null) {
                                 try {
                                   final region = context.read<ShelterProvider>().currentRegion;
                                   final allItems = [...SurvivalData.getOfficialGuides(region), ...SurvivalData.getAiSupportGuides(region)];
                                   final item = allItems.firstWhere((g) => g.id == guideId);
                                   final lang = context.read<LanguageProvider>().currentLanguage;
                                   SurvivalGuideModal.show(context, item, lang);
                                 } catch (e) {
                                   // ignore
                                 }
                               }
                            },
                            icon: const Icon(Icons.menu_book, size: 16),
                            label: SafeText(
                                // Use dynamic label or default
                                GapLessL10n.t('header_survival_guide'),
                                style: emergencyTextStyle(isBold: true),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.blue[800],
                              elevation: 1,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          // Selection Area (Chips)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: _buildOptionChips(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildOptionChips() {
    // Determine which options to show based on _menuState
    List<String> options = [];
    String headerText = '';
    
    final region = context.read<ShelterProvider>().currentRegion;

    if (_menuState == 'main') {
      headerText = GapLessL10n.t('header_category_guide'); // Official 6
      options = SurvivalData.getOfficialGuides(region).map((e) => e.id).toList();
    } else {
      // 'more' -> AI Support (Expanded 10 items)
      headerText = GapLessL10n.t('header_category_ai');
      options = SurvivalData.getAiSupportGuides(region).map((e) => e.id).toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: SafeText(
                 headerText,
                 style: emergencyTextStyle(size: 14, color: Colors.grey[800]!, isBold: true),
              ),
            ),
             // Toggle Button (Moved up for visibility or kept in wrap? Kept in wrap for flow)
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ...options.map((id) => ActionChip(
              label: SafeText(
                GapLessL10n.t('guide_$id'),
                style: emergencyTextStyle(size: 15, isBold: true),
              ),
              backgroundColor: const Color(0xFFF5F5F5),
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              onPressed: () => _handleOptionSelected(id),
            )),
            
            // Toggle Button
            ActionChip(
              avatar: Icon(
                _menuState == 'main' ? Icons.smart_toy : Icons.arrow_back,
                size: 16, 
                color: Colors.white
              ),
              label: SafeText(
                _menuState == 'main' 
                    ? GapLessL10n.t('chat_btn_more') // "Other Topics" -> "AI Support"
                    : GapLessL10n.t('chat_btn_back'),
                style: emergencyTextStyle(size: 15, isBold: true, color: Colors.white),
              ),
              backgroundColor: _menuState == 'main' 
                  ? Colors.blue[600] // Blue for AI Support
                  : Colors.grey[600], // Grey for Back
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              onPressed: () {
                setState(() {
                  _menuState = _menuState == 'main' ? 'more' : 'main';
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 8), // Bottom padding
      ],
    );
  }

  Widget _buildTypingIndicator() {
     return Align(
       alignment: Alignment.centerLeft,
       child: Container(
         margin: const EdgeInsets.only(bottom: 12),
         padding: const EdgeInsets.all(12),
         decoration: const BoxDecoration(
           color: Color(0xFFE3F2FD),
           borderRadius: BorderRadius.all(Radius.circular(16)),
         ),
         child: SizedBox(
           width: 40,
           height: 20,
           child: Row(
             mainAxisAlignment: MainAxisAlignment.spaceEvenly,
             children: List.generate(3, (index) => 
               const CircleAvatar(
                 radius: 4,
                 backgroundColor: Colors.black26, 
               )
             ),
           ),
         ),
       ),
     );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // どんな言語がプロンプトから返ってきても、トーフにさせない箱
  Widget translationDisplay(Map<String, String> translatedData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSafeText(translatedData['jp'] ?? '', fontSize: 18),
        _buildSafeText(translatedData['en'] ?? '', fontSize: 16),
        _buildSafeText(translatedData['th'] ?? '', fontSize: 20), // タイ語は少し大きく
      ],
    );
  }

  String _buildFinalPrompt(String countryCode, bool isArrived) {
    // localization.dart から現在の言語設定を取得
    String currentLang = GapLessL10n.lang; 
    
    if (countryCode == 'JP') {
      // --- 日本用プロンプト ---
      return """
あなたは災害支援アプリ「GapLess」の専用AIです。
以下の【地域設定】と【ユーザー言語】を厳守し、ユーザーへ簡潔で即時性の高いアドバイスを提供してください。

### 1. 現在のコンテキスト
- 地域: 日本・宮城県大崎市周辺 (Winter/Earthquake)
- 状態: ${isArrived ? "避難所に到着済み (生活支援フェーズ)" : "移動中 (避難・道案内フェーズ)"}
- ユーザー言語: {{language}}

### 2. アドバイス・ロジック (JP Standards)
- **最優先リスク**: 低体温症 (Hypothermia)、凍死、エコノミークラス症候群
- **推奨行動**: 段ボール断熱、重ね着、水分補給、足の運動。
- **データソース**: 日本内閣府・厚労省ガイドライン

### 3. 制約事項
- 回答は {{language}} で行う。
- 200文字以内、体言止め推奨。
"""
      .replaceAll('{{language}}', currentLang);
    } else {
      // --- タイ用プロンプト ---
      if (!isArrived) {
        // 【フェーズ1: 道案内・避難フェーズ】
        return """
あなたは災害支援アプリ「GapLess」の専用AIです。
現在、ユーザーはタイのサトゥン県におり、避難所へ移動中です。

### 1. 現在のコンテキスト
- 地域: タイ・サトゥン (Flood Risk)
- 状態: 移動中・避難中 (Navigation Phase)
- ユーザー言語: {{language}}

### 2. アドバイス方針
- 避難所への安全な到達を最優先にしてください。
- **リスク**: 増水した道路、感電、有毒生物、ひったくり。
- **推奨**: 高い場所への移動、足元の安全確認。

### 3. 制約
- 回答は {{language}} で行う。
- 200文字以内で簡潔に。
"""
        .replaceAll('{{language}}', currentLang);
      } else {
        // 【フェーズ2: 避難所生活支援フェーズ (Strict MoPH Mode)】
        return """
あなたはタイ保健省 (MOPH) および WHO のガイドラインに基づく、公衆衛生の専門AIです。
ユーザーはタイ・サトゥンの避難所に無事到着しました。これより生活支援を開始します。

### 1. 絶対厳守ルール
- 回答は必ず **タイ保健省 (MOPH)** または **WHO** の公式見解に基づいて作成してください。
- 日本の災害知識は使用せず、熱帯・洪水・避難所生活に特化してください。

### 2. 重要リスク管理 (MOPH)
- **レプトスピラ症**: 汚水歩行厳禁。
- **デング熱**: 蚊よけの徹底。
- **水・食料**: 煮沸・加熱の徹底。
- **感電**: 冠水時の電気製品の取り扱い。

### 3. スタイル
- 言語: {{language}}
- 200文字以内で、専門家として確実なアドバイスを。
"""
        .replaceAll('{{language}}', currentLang);
      }
    }
  }

  Widget _buildSafeText(String text, {double fontSize = 16, Color color = Colors.black}) {
    return SafeText(
      text,
      style: safeStyle(size: fontSize, color: color),
    );
  }
}
