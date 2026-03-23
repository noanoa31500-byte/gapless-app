

import '../providers/user_profile_provider.dart';

class BotResponse {
  final String text;
  final String? guideId;
  final String? guideLabel;

  BotResponse(this.text, {this.guideId, this.guideLabel});
}

class ChatService {
  static BotResponse generateResponse(String input, bool isOffline, bool isSafeInShelter, UserProfile profile, String region) {
    final text = input.trim().toLowerCase();

    // 2. Region Specific Advice Logic
    String advice = '';

    // JP Logic (Cold/Earthquake)
    // Keywords: 寒い (Cold), 水 (Water), 避難 (Shelter), 眠れない (Sleep)
    if (text.contains('寒') || text.contains('cold') || text.contains('凍')) {
      advice = '【低体温症対策】\n・段ボールを床に敷く\n・「重ね着」で空気の層を作る\n・首・手首・足首を温める';
      return BotResponse(advice, guideId: 'cold', guideLabel: '防寒ガイド');
    }
    if (text.contains('血') || text.contains('blood')) {
      advice = '【エコノミー症候群予防】\n・足をこまめに動かす\n・水分を摂る（トイレを我慢しない）';
      return BotResponse(advice, guideId: 'economy', guideLabel: '予防体操');
    }
    if (text.contains('火') || text.contains('fire')) {
      advice = '【二次被害防止】\n・冬場の火災に注意\n・倒壊家屋には近づかない';
      return BotResponse(advice);
    }

    // 3. User Profile Alerts (Allergies/Wheelchair) - Common
    if (profile.allergies.isNotEmpty && (text.contains('食') || text.contains('food'))) {
      final allergyList = profile.allergies.join(', ');
      return BotResponse(
        'アレルギー: $allergyList \n配給時はスタッフに申告してください。',
        guideId: null,
      );
    }

    // 4. Default Fallback
    if (isSafeInShelter) {
      return BotResponse('お困りのことはありますか？ (水 / 寒さ / 怪我)');
    } else {
      if (text.contains('避難所') || text.contains('shelter')) {
        return BotResponse('最寄りの避難所は地図で確認できます。');
      }
      return BotResponse('現在は災害モードです。\n「水」「寒さ」などで検索してください。');
    }
  }
}
