
import '../constants/survival/survival_data_th.dart';
import '../constants/survival/survival_data_jp.dart';

/// 全18言語対応の公衆衛生・防災ガイドBot
/// 旧称: ThaiSanitationBot（後方互換のためクラス名は維持）
class ThaiSanitationBot {

  /// 指定ガイドIDの内容を、現在の言語に合わせてフォーマットして返す
  static String generateResponse(String guideId, String lang, String? userName) {
    // 1. データ検索（TH・JP両方から、重複はTH優先）
    final seen = <String>{};
    final allGuides = [
      ...SurvivalDataTH.officialGuides,
      ...SurvivalDataTH.aiSupportGuides,
      ...SurvivalDataJP.officialGuides,
    ].where((g) => seen.add(g.id)).toList();

    final matches = allGuides.where((g) => g.id == guideId);
    if (matches.isEmpty) return '[Guide not found: $guideId]';
    final item = matches.first;

    // 2. プレフィックス生成（18言語対応）
    final prefix = _buildPrefix(lang, userName);

    // 3. コンテンツ取得（言語→英語フォールバック）
    final title  = item.title[lang]  ?? item.title['en']  ?? '';
    final action = item.action[lang] ?? item.action['en'] ?? '';
    final source = item.source;

    // 4. 整形して返す
    return '$prefix\n\n📌 $title\n$action\n\n(Source: $source)';
  }

  // ──────────────────────────────────────────────────────
  // 機関名プレフィックス（18言語）
  // ──────────────────────────────────────────────────────
  static const Map<String, String> _orgLabel = {
    'ja':    '【防災・公衆衛生 指針】',
    'en':    '[Public Health Emergency Alert]',
    'th':    'กรมควบคุมโรค (DDC) แจ้งเตือน:',
    'zh':    '【公共卫生防灾指南】',
    'zh_TW': '【公共衛生防災指南】',
    'ko':    '【재난안전 공중보건 지침】',
    'vi':    '【Hướng dẫn Y tế Công cộng Khẩn cấp】',
    'tl':    '【Gabay sa Kalusugang Pampubliko】',
    'fil':   '【Gabay sa Kalusugang Pampubliko】',
    'ne':    '【सार्वजनिक स्वास्थ्य आपतकालीन मार्गदर्शन】',
    'pt':    '【Orientação de Saúde Pública em Emergência】',
    'id':    '【Panduan Kesehatan Masyarakat Darurat】',
    'my':    '【အရေးပေါ်ကျန်းမာရေးလမ်းညွှန်】',
    'si':    '【හදිසි රෝග නාශ මාර්ගෝපදේශ】',
    'hi':    '【आपातकालीन सार्वजनिक स्वास्थ्य मार्गदर्शन】',
    'es':    '【Guía de Salud Pública en Emergencias】',
    'mn':    '【Яаралтай нийтийн эрүүл мэндийн удирдамж】',
    'uz':    "【Favqulodda Jamoat Sog'liqni Saqlash】",
    'bn':    '【জরুরি জনস্বাস্থ্য নির্দেশিকা】',
  };

  // ──────────────────────────────────────────────────────
  // 氏名付きプレフィックスフォーマット（@name プレースホルダー）
  // ──────────────────────────────────────────────────────
  static const Map<String, String> _nameFormat = {
    'ja':    '@nameさん、身の安全を最優先してください。\n',
    'en':    '@name, please prioritize your safety.\n',
    'th':    'คุณ @name, ',
    'zh':    '@name，请确保人身安全。\n',
    'zh_TW': '@name，請確保人身安全。\n',
    'ko':    '@name님, 안전을 최우선으로 하세요.\n',
    'vi':    '@name, hãy ưu tiên sự an toàn của bạn.\n',
    'tl':    '@name, unahin ang iyong kaligtasan.\n',
    'fil':   '@name, unahin ang iyong kaligtasan.\n',
    'ne':    '@name, आफ्नो सुरक्षालाई प्राथमिकता दिनुहोस्।\n',
    'pt':    '@name, priorize sua segurança.\n',
    'id':    '@name, utamakan keselamatanmu.\n',
    'my':    '@name, သင့်ဘေးကင်းရေးကို ဦးစားပေးပါ။\n',
    'si':    '@name, ඔබේ ආරක්ෂාව පළමු කරන්න.\n',
    'hi':    '@name, अपनी सुरक्षा को प्राथमिकता दें।\n',
    'es':    '@name, prioriza tu seguridad.\n',
    'mn':    '@name, аюулгүй байдлаа нэн тэргүүнд тавь.\n',
    'uz':    "@name, xavfsizligingizni birinchi o'ringa qo'ying.\n",
    'bn':    '@name, আপনার নিরাপত্তাকে সর্বোচ্চ অগ্রাধিকার দিন।\n',
  };

  static String _buildPrefix(String lang, String? name) {
    final org = _orgLabel[lang] ?? _orgLabel['en']!;
    if (name != null && name.isNotEmpty) {
      final fmt = _nameFormat[lang] ?? _nameFormat['en']!;
      return '${fmt.replaceAll('@name', name)}$org';
    }
    return org;
  }
}
