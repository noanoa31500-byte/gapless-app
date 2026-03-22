


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
    final isThai = region.startsWith('th'); // JP is default if not TH
    
    // 0. Minimal Prefix (Removed long empathy names)
    // User wants "Simple". Just plain advice.
    
    // 1. Emergency Gear Info - Simplified
    // Only append if absolutely relevant context, or keep it very short.
    // Actually, user said "Simple". Let's removing the constant nagging about gear in every message.
    // It will be shown only if they ask for "Gear" or specific context.

    
    // 2. Region Specific Advice Logic
    String advice = '';
    
    // JP Logic (Cold/Earthquake)
    // Keywords: 寒い (Cold), 水 (Water), 避難 (Shelter), 眠れない (Sleep)
    if (!isThai) {
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
    }

    // TH Logic (Tropical/Flood Risk - MOPH/DDPM based)
    // Keywords: Water/Flood, Electric, Pests/Animals, Dengue, Heat
    if (isThai) {
       // 1. Water & Flood Hygiene (Leptospirosis/Cholera) - Source: MOPH
       if (text.contains('น้ำ') || text.contains('water') || text.contains('flood') || text.contains('ท่วม')) {
          advice = '【ระวังโรคฉี่หนู】\n・ห้ามเดินลุยน้ำเปล่า (สวมรองเท้าบูท)\n・ดื่มน้ำต้มสุก/น้ำขวดปิดสนิทเท่านั้น';
          return BotResponse(advice, guideId: 'water', guideLabel: 'สุขอนามัยน้ำท่วม');
       }
       // 2. Electric Shock (Flood risk #1) - Source: DDPM
       if (text.contains('ไฟ') || text.contains('electric') || text.contains('shock') || text.contains('ดูด')) {
          advice = '【อันตรายจากไฟฟ้า】\n・สับคัทเอาท์ทันทีหากน้ำท่วมถึงปลั๊ก\n・ห้ามแตะสวิตช์ไฟขณะตัวเปียก';
          return BotResponse(advice);
       }
       // 3. Venomous Animals (Flood escapees)
       if (text.contains('งู') || text.contains('snake') || text.contains('แมลง') || text.contains('bug') || text.contains('สัตว์')) {
          advice = '【สัตว์มีพิษหนีน้ำ】\n・ระวังงู/ตะขาบในรองเท้า\n・ใช้ไม้ยาวเขี่ยนำทางก่อนเดิน';
          return BotResponse(advice, guideId: 'pests', guideLabel: 'ปฐมพยาบาลสัตว์กัด');
       }
       // 4. Dengue Fever (Mosquitoes) - "3 Keb" Measure
       if (text.contains('ยุง') || text.contains('mosquito') || text.contains('ไข้') || text.contains('fever')) {
          advice = '【ระวังโรคไข้เลือดออก】\n・มาตรการ "3 เก็บ" (เก็บบ้าน/ขยะ/น้ำ)\n・นอนกางมุ้ง/ทายากันยุง';
          return BotResponse(advice);
       }
       // 5. Heatstroke (General Tropical Risk)
       if (text.contains('ร้อน') || text.contains('heat') || text.contains('hot') || text.contains('แดด')) {
          advice = '【ระวังโรคลมแดด】\n・ดื่มน้ำบ่อยๆ แม้ไม่กระหาย\n・หลีกเลี่ยงแดดจัด';
           return BotResponse(advice, guideId: 'heatstroke', guideLabel: 'ปฐมพยาบาลลมแดด');
       }
    }

    // 3. User Profile Alerts (Allergies/Wheelchair) - Common
    if (profile.allergies.isNotEmpty && (text.contains('食') || text.contains('food') || text.contains('กิน'))) {
      final allergyList = profile.allergies.join(', ');
      return BotResponse(
        isThai ? 'ข้อมูลการแพ้: $allergyList \nโปรดแจ้งเจ้าหน้าที่เมื่อรับอาหาร' : 'アレルギー: $allergyList \n配給時はスタッフに申告してください。',
        guideId: null,
      );
    }
    
    // 4. Default Fallback
    if (isSafeInShelter) {
       return BotResponse(isThai 
           ? 'มีอะไรให้ช่วยไหมครับ (น้ำ / ยา / อาหาร)'
           : 'お困りのことはありますか？ (水 / 寒さ / 怪我)'
       );
    } else {
       if (text.contains('避難所') || text.contains('shelter') || text.contains('ที่พักพิง')) {
          return BotResponse(isThai
             ? 'ดูจุดอพยพใกล้เคียงบนแผนที่'
             : '最寄りの避難所は地図で確認できます。'
          );
       }
       return BotResponse(isThai
           ? 'กรุณาอพยพไปที่ปลอดภัย\nพิมพ์: "น้ำ" "เจ็บป่วย"'
           : '現在は災害モードです。\n「水」「寒さ」などで検索してください。'
       );
    }
  }


}
