
import 'package:flutter/material.dart';
import '../survival_data.dart'; // Import the base classes

class SurvivalDataJP {
  // --- Official Survival Guide (Strict 6 Items - JAPAN) ---
  static const List<SurvivalGuideItem> officialGuides = [
    SurvivalGuideItem(
      id: 'economy',
      icon: Icons.airline_seat_legroom_extra,
      title: {'en': 'Economy Class Syn.', 'ja': 'エコノミークラス症候群', 'th': 'โรคชั้นประหยัด'},
      action: {
        'en': 'Do ankle exercises. Drink water frequently.',
        'ja': '足首を回す運動をしましょう。水分をこまめに摂り、同じ姿勢で寝ないよう注意してください。',
        'th': 'ขยับข้อเท้าบ่อยๆ ดื่มน้ำสะอาดให้เพียงพอ',
      },
      source: 'MHLW / JSIM',
      steps: [
        SurvivalStep(instruction: {'en': 'Rotate ankles.', 'ja': '足首を回す', 'th': 'หมุนข้อเท้าซ้ายขวา'}, icon: Icons.refresh),
        SurvivalStep(instruction: {'en': 'Drink water.', 'ja': '水を飲む', 'th': 'ดื่มน้ำสะอาด'}, icon: Icons.local_drink),
        SurvivalStep(instruction: {'en': 'Walk around.', 'ja': '歩く', 'th': 'ลุกเดินยืดเส้นสาย'}, icon: Icons.directions_walk),
      ],
    ),
    SurvivalGuideItem(
      id: 'infection',
      icon: Icons.sanitizer,
      title: {'en': 'Infection Control', 'ja': '感染症対策', 'th': 'การป้องกันการติดเชื้อ'},
      action: {
        'en': 'Wash hands thoroughly. Wear masks. Ventilate.',
        'ja': '手洗い・うがいを徹底してください。マスクを着用し、定期的に換気を行いましょう。',
        'th': 'ล้างมือให้สะอาด สวมหน้ากากอนามัย และระบายอากาศอย่างสม่ำเสมอ',
      },
      source: 'MHLW / CDC',
    ),
    SurvivalGuideItem(
      id: 'poisoning',
      icon: Icons.food_bank,
      title: {'en': 'Food Poisoning', 'ja': '食中毒予防', 'th': 'ความปลอดภัยทางอาหาร'},
      action: {
        'en': 'Eat distributed food immediately. No leftovers.',
        'ja': '配給された食事はすぐに食べてください。室温で放置しないでください。',
        'th': 'รับประทานอาหารที่แจกจ่ายทันที อย่าทิ้งอาหารไว้ที่อุณหภูมิห้อง',
      },
      source: 'MHLW',
    ),
    SurvivalGuideItem(
      id: 'insulation',
      icon: Icons.thermostat,
      title: {'en': 'Cold Protection', 'ja': '寒さ対策', 'th': 'การป้องกันความหนาว'},
      action: {
        'en': 'Layer clothes. Use cardboard for insulation.',
        'ja': '寒さには重ね着や段ボールを活用。',
        'th': 'สวมเสื้อผ้าหลายชั้นเมื่อหนาว ใช้กล่องกระดาษรองนอน',
      },
      source: 'FDMA',
    ),
    SurvivalGuideItem(
      id: 'crime',
      icon: Icons.security,
      title: {'en': 'Crime Prevention', 'ja': '防犯対策', 'th': 'การป้องกันอาชญากรรม'},
      action: {
        'en': 'Move in groups. Use buzzers.',
        'ja': '単独行動を避け、防犯ブザーを携帯。',
        'th': 'ไปเป็นกลุ่ม พกนกหวีด และดูแลของมีค่าตลอดเวลา',
      },
      source: 'NPA',
    ),
    SurvivalGuideItem(
      id: 'rhythm',
      icon: Icons.nightlight_round,
      title: {'en': 'Daily Rhythm', 'ja': '生活リズム', 'th': 'จังหวะชีวิต'},
      action: {
        'en': 'Separate sleep/wake areas. Keep regular hours.',
        'ja': '寝る場所と活動場所を分け、規則正しい生活を。',
        'th': 'แยกพื้นที่นอนและกิจกรรม พยายามรักษากิจวัตรประจำวัน',
      },
      source: 'Cabinet Office',
    ),
  ];

  // --- AI Support Items (Rest of the items) ---
  static const List<SurvivalGuideItem> aiSupportGuides = [
    SurvivalGuideItem(
      id: 'chronic',
      icon: Icons.medication,
      title: {'en': 'Chronic Illness / Medicine', 'ja': '持病・薬について', 'th': 'โรคเรื้อรัง/ยา'},
      action: {
        'en': 'Notify staff of your medicine tag (Okusuri Techo). Consult medical teams.',
        'ja': 'お薬手帳をスタッフに提示してください。巡回医師に持病を相談しましょう。',
        'th': 'แจ้งเจ้าหน้าที่เกี่ยวกับยาประจำตัว ปรึกษาทีมแพทย์',
      },
      source: 'JMA (Japan Medical Association)',
    ),
    SurvivalGuideItem(
      id: 'religion',
      icon: Icons.menu_book, 
      title: {'en': 'Religious Needs', 'ja': '宗教的配慮', 'th': 'ความต้องการทางศาสนา'},
      action: {
        'en': 'Use "Help Card" for Halal/Prayer needs. Create a private space with partitions.',
        'ja': '「Help Card」でハラルや礼拝の必要性を伝えてください。パーティションで空間を確保します。',
        'th': 'ใช้ "Help Card" เพื่อแจ้งเรื่องอาหารฮาลาลหรือการละหมาด สร้างพื้นที่ส่วนตัวด้วยฉากกั้น',
      },
      source: 'Multicultural Coexistence Guidelines',
    ),
    SurvivalGuideItem(
      id: 'pet',
      icon: Icons.pets,
      title: {'en': 'Pet Evacuation', 'ja': 'ペット同行避難', 'th': 'สัตว์เลี้ยง'},
      action: {
        'en': 'Keep pets in cages. designate a pet area. Manage waste properly.',
        'ja': 'ケージに入れ、専用エリアを利用してください。排泄物の処理を徹底しましょう。',
        'th': 'ขังสัตว์เลี้ยงในกรง ใช้พื้นที่สำหรับสัตว์เลี้ยง จัดการสิ่งขับถ่ายให้เรียบร้อย',
      },
      source: 'Ministry of the Environment',
    ),
    SurvivalGuideItem(
      id: 'mental',
      icon: Icons.psychology,
      title: {'en': 'Mental Care', 'ja': '心のケア', 'th': 'สุขภาพจิต'},
      action: {
        'en': 'Practice "Grounding" or Deep Breathing. It is okay to cry or be scared.',
        'ja': '深呼吸や「グラウンディング」を試して。泣いたり怖がるのは自然な反応です。',
        'th': 'ฝึกหายใจลึกๆ หรือ Grounding การร้องไห้หรือกลัวเป็นเรื่องปกติ',
      },
      source: 'WHO / MHLW',
      steps: [
        SurvivalStep(instruction: {'en': 'Breathe deeply.', 'ja': '深呼吸する', 'th': 'หายใจเข้าลึกๆ'}, icon: Icons.air),
        SurvivalStep(instruction: {'en': 'Talk to someone.', 'ja': '誰かと話す', 'th': 'คุยกับใครสักคน'}, icon: Icons.record_voice_over),
      ],
    ),
    SurvivalGuideItem(
      id: 'care',
      icon: Icons.accessible,
      title: {'en': 'Nursing Care', 'ja': '介護・介助', 'th': 'การดูแลผู้ป่วย'},
      action: {
        'en': 'Ask for accessible toilets and support. Look for "Welfare Shelter" info.',
        'ja': '多目的トイレや介助を依頼してください。「福祉避難所」への移動も検討されます。',
        'th': 'ขอความช่วยเหลือเรื่องห้องน้ำและการดูแล มองหาข้อมูล "ศูนย์พักพิงสำหรับผู้ต้องการการดูแลพิเศษ"',
      },
      source: 'MHLW',
    ),
    SurvivalGuideItem(
      id: 'hygiene',
      icon: Icons.wash,
      title: {'en': 'Toilet & Hygiene', 'ja': 'トイレ・衛生', 'th': 'ห้องน้ำ/สุขอนามัย'},
      action: {
        'en': 'Use portable toilets if available. Keep hands clean. Segregate waste.',
        'ja': '簡易トイレを利用し、手指消毒を徹底。ゴミは分別して密封してください。',
        'th': 'ใช้ห้องน้ำแบบพกพาหากมี ล้างมือให้สะอาด แยกขยะ',
      },
      source: 'MHLW',
    ),
    SurvivalGuideItem(
      id: 'battery',
      icon: Icons.battery_saver,
      title: {'en': 'Battery Saving', 'ja': 'スマホ・電源', 'th': 'ประหยัดแบตเตอรี่'},
      action: {
        'en': 'Turn on Low Power Mode. Lower brightness. Turn off Wi-Fi/Bluetooth if not used.',
        'ja': '低電力モードをオン、画面を暗く、Wi-Fi/Bluetoothはオフに。',
        'th': 'เปิดโหมดประหยัดพลังงาน ลดความสว่างหน้าจอ ปิด Wi-Fi/Bluetooth หากไม่ได้ใช้',
      },
      source: 'Internal Affairs & Communications',
    ),
    SurvivalGuideItem(
      id: 'female',
      icon: Icons.spa,
      title: {'en': 'Women\'s Care', 'ja': '女性のケア', 'th': 'สำหรับผู้หญิง'},
      action: {
        'en': 'Ask female staff for sanitary products. Ensure privacy in changing areas.',
        'ja': '生理用品は女性スタッフに相談を。着替えや授乳スペースのプライバシー確保を。',
        'th': 'ขอผ้าอนามัยจากเจ้าหน้าที่หญิง ตรวจสอบความเป็นส่วนตัวในพื้นที่เปลี่ยนเสื้อผ้า',
      },
      source: 'Gender Equality Bureau',
    ),
    SurvivalGuideItem(
      id: 'info',
      icon: Icons.radio,
      title: {'en': 'Information Gathering', 'ja': '情報の集め方', 'th': 'การหาข้อมูล'},
      action: {
        'en': 'Trust official sources (Radio/Govt Apps). Avoid rumors.',
        'ja': 'ラジオや自治体アプリなど、公式情報を信頼してください。デマに注意。',
        'th': 'เชื่อถือแหล่งข้อมูลที่เป็นทางการ (วิทยุ/แอปของรัฐบาล) ระวังข่าวลือ',
      },
      source: 'Fire and Disaster Management Agency',
    ),
    SurvivalGuideItem(
      id: 'money',
      icon: Icons.attach_money,
      title: {'en': 'Cash & Valuables', 'ja': 'お金・貴重品', 'th': 'お金・貴重品'},
      action: {
        'en': 'Keep cash and ID on you. Do not leave them in shared spaces.',
        'ja': '現金と身分証は肌身離さず携帯。共有スペースに放置しないでください。',
        'th': 'พกเงินสดและบัตรประจำตัวติดตัว อย่าทิ้งไว้ในพื้นที่ส่วนกลาง',
      },
      source: 'National Police Agency',
    ),
  ];
}
