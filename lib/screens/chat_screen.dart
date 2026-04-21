import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/shelter_provider.dart';
import '../providers/user_profile_provider.dart';
import '../providers/language_provider.dart';
import '../widgets/survival_guide_modal.dart';
import '../widgets/safe_text.dart';
import '../constants/survival_data.dart';
import '../services/chat_service.dart';
import '../utils/localization.dart';
import '../utils/styles.dart';

// ============================================================
// ChatScreen — 全18言語対応・豆腐/文字化けゼロ実装
//
// ・すべてのテキスト表示に SafeText + safeStyle() を使用
// ・すべてのラベルは GapLessL10n.t() 経由（ハードコードなし）
// ・フォントフォールバック: GapLessL10n.fallbackFonts（11フォント）
// ============================================================
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  String _menuState = 'main'; // 'main' or 'more'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addBotMessage(GapLessL10n.t('chat_prompt_main'));
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────
  // メッセージ追加
  // ──────────────────────────────────────────
  void _addBotMessage(String text, {String? guideId}) {
    setState(() {
      _messages.add({'type': 'bot', 'text': text, 'guideId': guideId});
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
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ──────────────────────────────────────────
  // 選択肢タップ時の処理
  // ──────────────────────────────────────────
  void _handleOptionSelected(String id) {
    final lang = GapLessL10n.lang;

    // ユーザーメッセージとして選択ラベルを表示
    final allItems = [
      ...SurvivalData.getOfficialGuides(
          context.read<ShelterProvider>().currentRegion),
      ...SurvivalData.getAiSupportGuides(
          context.read<ShelterProvider>().currentRegion),
    ];
    final matchedTitle = allItems
            .where((g) => g.id == id)
            .map((g) =>
                g.title[lang] ?? g.title['en'] ?? GapLessL10n.t('guide_$id'))
            .firstOrNull ??
        GapLessL10n.t('guide_$id');

    _addUserMessage(matchedTitle);
    setState(() => _isTyping = true);

    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final profile = context.read<UserProfileProvider>().profile;
      final isSafe = context.read<ShelterProvider>().isSafeInShelter;
      final region = context.read<ShelterProvider>().currentRegion;

      final response = ChatService.generateResponse(
        guideId: id,
        isSafeInShelter: isSafe,
        profile: profile,
        region: region,
      );
      _addBotMessage(response.text, guideId: response.guideId);
    });
  }

  // ──────────────────────────────────────────
  // build
  // ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // 言語変更時に再描画
    return Scaffold(
      appBar: AppBar(
        title: SafeText(
          GapLessL10n.t('header_ai_guide'),
          style:
              emergencyTextStyle(size: 18, isBold: true, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildInputArea(),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────
  // メッセージリスト
  // ──────────────────────────────────────────
  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isTyping) {
          return _buildTypingIndicator();
        }
        final msg = _messages[index];
        final isBot = msg['type'] == 'bot';
        return _buildBubble(msg, isBot);
      },
    );
  }

  Widget _buildBubble(Map<String, dynamic> msg, bool isBot) {
    final text = msg['text'] as String;
    final guideId = msg['guideId'] as String?;

    return Align(
      alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Column(
        crossAxisAlignment:
            isBot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            decoration: BoxDecoration(
              color: isBot ? const Color(0xFFE3F2FD) : const Color(0xFFE53935),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: isBot ? Radius.zero : const Radius.circular(16),
                bottomRight: isBot ? const Radius.circular(16) : Radius.zero,
              ),
            ),
            // SafeText でフォント自動選択 + 11フォントフォールバック
            child: SafeText(
              text,
              style: safeStyle(
                size: 15,
                color: isBot ? Colors.black87 : Colors.white,
              ),
            ),
          ),

          // ガイド詳細ボタン
          if (isBot && guideId != null) _buildGuideButton(guideId),
        ],
      ),
    );
  }

  Widget _buildGuideButton(String guideId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 4),
      child: ElevatedButton.icon(
        onPressed: () => _openGuideModal(guideId),
        icon: const Icon(Icons.menu_book, size: 16),
        label: SafeText(
          GapLessL10n.t('header_survival_guide'),
          style: emergencyTextStyle(size: 14, isBold: true),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.blue[800],
          elevation: 1,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  void _openGuideModal(String guideId) {
    final region = context.read<ShelterProvider>().currentRegion;
    final lang = context.read<LanguageProvider>().currentLanguage;
    final allItems = [
      ...SurvivalData.getOfficialGuides(region),
      ...SurvivalData.getAiSupportGuides(region),
    ];
    try {
      final item = allItems.firstWhere((g) => g.id == guideId);
      SurvivalGuideModal.show(context, item, lang);
    } catch (_) {}
  }

  // ──────────────────────────────────────────
  // 入力エリア（選択肢チップ）
  // ──────────────────────────────────────────
  Widget _buildInputArea() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: _buildOptionChips(),
    );
  }

  Widget _buildOptionChips() {
    final region = context.read<ShelterProvider>().currentRegion;
    final lang = GapLessL10n.lang;

    final isMain = _menuState == 'main';
    final items = isMain
        ? SurvivalData.getOfficialGuides(region)
        : SurvivalData.getAiSupportGuides(region);
    final header =
        GapLessL10n.t(isMain ? 'header_category_guide' : 'header_category_ai');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeText(
          header,
          style: emergencyTextStyle(
              size: 13, isBold: true, color: Colors.grey[700]!),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            // ガイド選択肢チップ
            ...items.map((item) {
              // ガイドタイトルを現在言語で取得（英語フォールバック付き）
              final label = item.title[lang] ??
                  item.title['en'] ??
                  GapLessL10n.t('guide_${item.id}');
              return ActionChip(
                label: SafeText(
                  label,
                  style: emergencyTextStyle(size: 14, isBold: true),
                ),
                backgroundColor: const Color(0xFFF0F4F8),
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                onPressed: () => _handleOptionSelected(item.id),
              );
            }),

            // メニュー切替チップ
            ActionChip(
              avatar: Icon(
                isMain ? Icons.smart_toy : Icons.arrow_back,
                size: 16,
                color: Colors.white,
              ),
              label: SafeText(
                GapLessL10n.t(isMain ? 'chat_btn_more' : 'chat_btn_back'),
                style: emergencyTextStyle(
                    size: 14, isBold: true, color: Colors.white),
              ),
              backgroundColor: isMain ? Colors.blue[600]! : Colors.grey[600]!,
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              onPressed: () =>
                  setState(() => _menuState = isMain ? 'more' : 'main'),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  // ──────────────────────────────────────────
  // タイピングインジケーター
  // ──────────────────────────────────────────
  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(
          color: Color(0xFFE3F2FD),
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            3,
            (i) => Padding(
              padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
              child: const CircleAvatar(
                radius: 4,
                backgroundColor: Colors.black38,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
