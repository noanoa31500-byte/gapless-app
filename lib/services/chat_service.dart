import '../utils/localization.dart';
import '../providers/user_profile_provider.dart';
import '../constants/survival_data.dart';
import '../utils/thai_sanitation_bot.dart';

class BotResponse {
  final String text;
  final String? guideId;

  BotResponse(this.text, {this.guideId});
}

/// 全18言語対応チャットサービス
/// テキストはすべて GapLessL10n.t() / ThaiSanitationBot 経由で取得し
/// ハードコード文字列ゼロ・豆腐なし を保証する
class ChatService {
  static BotResponse generateResponse({
    required String guideId,
    required bool isSafeInShelter,
    required UserProfile profile,
    required String region,
  }) {
    final lang = GapLessL10n.lang;

    // ガイドデータを検索（全言語フォールバック付き）
    final allItems = [
      ...SurvivalData.getOfficialGuides(region),
      ...SurvivalData.getAiSupportGuides(region),
    ];

    final matches = allItems.where((g) => g.id == guideId);
    if (matches.isEmpty) {
      return BotResponse(GapLessL10n.t('chat_error_not_found'));
    }
    final item = matches.first;

    // 避難所到着フェーズ: ThaiSanitationBot（18言語対応済み）
    if (isSafeInShelter) {
      final text = ThaiSanitationBot.generateResponse(
        item.id, lang, profile.name.isNotEmpty ? profile.name : null,
      );
      return BotResponse(text, guideId: guideId);
    }

    // ナビゲーションフェーズ: プレフィックス + ガイド内容
    final prefix = profile.name.isNotEmpty
        ? GapLessL10n.t('bot_prefix_name').replaceAll('@name', profile.name)
        : GapLessL10n.t('bot_prefix_normal');

    final title  = item.title[lang]  ?? item.title['en']  ?? '';
    final action = item.action[lang] ?? item.action['en'] ?? '';

    return BotResponse(
      '$prefix\n\n$title\n\n$action',
      guideId: guideId,
    );
  }
}
