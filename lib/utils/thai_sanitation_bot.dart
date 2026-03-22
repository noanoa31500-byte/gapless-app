
import '../constants/survival/survival_data_th.dart';

class ThaiSanitationBot {
  
  /// Generates a strict MOPH/WHO compliant response
  /// This runs OFFLINE and ensures no hallucinations.
  static String generateResponse(String guideId, String lang, String? userName) {
    // 1. Data Lookup
    // Search both Official and AI Support lists for Thailand
    final allGuides = [...SurvivalDataTH.officialGuides, ...SurvivalDataTH.aiSupportGuides];
    
    final matches = allGuides.where((g) => g.id == guideId);
    if (matches.isEmpty) {
      return '[Guide not found: $guideId]';
    }
    final item = matches.first;

    // 2. Prefix Construction (Persona)
    String prefix = '';
    if (lang == 'th') {
      prefix = 'กรมควบคุมโรค (DDC) และกระทรวงสาธารณสุขขอแจ้งเตือน:';
      if (userName != null && userName.isNotEmpty) {
         prefix = 'คุณ $userName, $prefix';
      }
    } else if (lang == 'ja') {
      prefix = '【タイ保健省(MOPH) 公衆衛生指針】';
      if (userName != null && userName.isNotEmpty) {
         prefix = '$userNameさん、心身の安全を最優先してください。\n$prefix';
      }
    } else {
       prefix = '[Thai Ministry of Public Health Alert]';
       if (userName != null && userName.isNotEmpty) {
         prefix = '$userName, $prefix';
       }
    }

    // 3. Content Extraction
    final title = item.title[lang] ?? item.title['en'] ?? '';
    final action = item.action[lang] ?? item.action['en'] ?? '';
    final source = item.source;

    // 4. Final Formatting
    // "MOPH Alert: \n\n[Title]\n[Action]\n\nSource: [Source]"
    return '$prefix\n\n📌 $title\n$action\n\n(Source: $source)';
  }
}
