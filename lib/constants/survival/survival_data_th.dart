import 'package:flutter/material.dart';
import '../survival_data.dart'; // Import the base classes

class SurvivalDataTH {
  // --- Official Survival Guide (Strict 6 Items - THAILAND) ---
  // Fully localized for Tropical Flood context (No Economy Class Syndrome)
  static const List<SurvivalGuideItem> officialGuides = [
    SurvivalGuideItem(
      id: 'electric',
      icon: Icons.electrical_services, // Critical Hazard
      title: {
        'en': 'Electrical Safety',
        'ja': '電気・感電への注意',
        'th': 'ระวังไฟดูด (Electrocution)'
      },
      action: {
        'en': 'Cut power if flooded. Stay away from wet poles.',
        'ja': '浸水時はブレーカーを切って電気を遮断し、濡れた電柱や電線には絶対に近づかないでください。',
        'th':
            'ตัดคัทเอาท์ทันทีหากน้ำท่วมบ้าน อย่าเข้าใกล้เสาไฟที่แช่น้ำ อันตรายถึงชีวิต',
      },
      source: 'MEA / PEA (Electricity Authority)',
    ),
    SurvivalGuideItem(
      id: 'disease',
      icon: Icons.coronavirus, // Leptospirosis / Dengue
      title: {
        'en': 'Flood Diseases',
        'ja': '水害時の感染症対策',
        'th': 'โรคระบาด (ฉี่หนู/ไข้เลือดออก)'
      },
      action: {
        'en': 'Do not wade in water (Leptospirosis). Use net (Dengue).',
        'ja': '汚水の中を素足で歩かない（レプトスピラ症対策）。蚊に刺されないよう蚊帳などを使う（デング熱対策）。',
        'th':
            'ห้ามลุยน้ำเปล่าเท้า (โรคฉี่หนู) นอนกางมุ้งระวังยุงลาย (ไข้เลือดออก)',
      },
      source: 'Thai MoPH (Department of Disease Control)',
    ),
    SurvivalGuideItem(
      id: 'animals',
      icon: Icons.pest_control, // Snakes
      title: {
        'en': 'Poisonous Animals',
        'ja': '毒を持つ生物への注意',
        'th': 'สัตว์มีพิษ (งู/ตะขาบ)'
      },
      action: {
        'en': 'Check shoes/corners. Snakes seek dry places.',
        'ja': '靴を履く前に中を確認し、部屋の隅などにも注意してください。ヘビやサソリも乾いた場所を求めて避難してきます。',
        'th': 'ตรวจสอบรองเท้าและมุมอับ งูและแมลงมีพิษหนีน้ำมาซ่อนตัว',
      },
      source: 'DDPM / Thai Red Cross Snake Farm',
    ),
    SurvivalGuideItem(
      id: 'water_food',
      icon: Icons.water_drop,
      title: {
        'en': 'Clean Water/Food',
        'ja': '水・食料衛生',
        'th': 'กินร้อน ช้อนกลาง (Food Safety)'
      },
      action: {
        'en': 'Drink bottled water ONLY. Eat cooked food.',
        'ja': 'ボトル水のみ飲む。加熱した食事のみ摂る。',
        'th':
            'ดื่มน้ำบรรจุขวดเท่านั้น กินอาหารปรุงสุกใหม่ๆ ระวังโรคท้องร่วงรุนแรง',
      },
      source: 'Thai FDA / MoPH',
    ),
    SurvivalGuideItem(
      id: 'heat',
      icon: Icons.wb_sunny,
      title: {'en': 'Heatstroke', 'ja': '熱中症', 'th': 'โรคลมแดด (Heatstroke)'},
      action: {
        'en': 'Stay in shade. Drink water even if not thirsty.',
        'ja': '日陰に避難。喉が渇く前に水を飲む。',
        'th': 'อยู่ในที่ร่มระบายอากาศ ดื่มน้ำบ่อยๆ อย่ารอให้กระหาย',
      },
      source: 'Thai Meteorological Dept',
    ),
    SurvivalGuideItem(
      id: 'emergency',
      icon: Icons.phone_in_talk,
      title: {
        'en': 'Emergency #',
        'ja': '緊急連絡先',
        'th': 'เบอร์ฉุกเฉิน (1669/191)'
      },
      action: {
        'en': 'Medical: 1669, Police: 191, Disaster: 1784.',
        'ja': '救急: 1669, 警察: 191, 災害: 1784',
        'th': 'เจ็บป่วยฉุกเฉิน 1669, เหตุด่วน 191, ภัยพิบัติ 1784 (จำให้แม่น)',
      },
      source: 'National Emergency Institute',
    ),
  ];

  // --- AI Support Items (TH) - 10 Items ---
  static const List<SurvivalGuideItem> aiSupportGuides = [
    SurvivalGuideItem(
      id: 'drowning',
      icon: Icons.pool,
      title: {
        'en': 'Drowning Prevention',
        'ja': '水の事故防止',
        'th': 'ป้องกันจมน้ำ'
      },
      action: {
        'en':
            'Do not let children play in flood water. It is deeper and faster than it looks.',
        'ja': '子供を水辺で遊ばせないでください。見た目より深く、流れが速いです。',
        'th':
            'ห้ามเด็กเล่นน้ำท่วมเด็ดขาด น้ำอาจลึกและไหลเชี่ยวกว่าที่คิด (สาเหตุการตายอันดับ 1)',
      },
      source: 'MoPH (DDC)',
    ),
    SurvivalGuideItem(
      id: 'boat_safety',
      icon: Icons.sailing, // Closest to boat
      title: {'en': 'Boat Safety', 'ja': 'ボート移動', 'th': 'ความปลอดภัยทางเรือ'},
      action: {
        'en': 'Wear life jackets. Do not overload boats.',
        'ja': '救命胴衣を着用。定員オーバーのボートには乗らない。',
        'th': 'สวมเสื้อชูชีพทุกครั้ง ห้ามลงเรือเกินจำนวนที่กำหนด',
      },
      source: 'Marine Dept',
    ),
    SurvivalGuideItem(
      id: 'fungal',
      icon: Icons.clean_hands,
      title: {
        'en': 'Fungal Infection (Feet)',
        'ja': '足の皮膚病（水虫など）',
        'th': 'โรคน้ำกัดเท้า'
      },
      action: {
        'en':
            'Keep feet dry. Apply fungicide cream if available. Do not stay in wet socks.',
        'ja': '足を清潔に保ち、よく乾燥させてください。濡れた靴下は放置せず、必要に応じて抗真菌薬を使用してください。',
        'th': 'เช็ดเท้าให้แห้ง ทายารักษาเชื้อราหากมี อย่าแช่เท้านาน',
      },
      source: 'MoPH',
    ),
    SurvivalGuideItem(
      id: 'toilet_th',
      icon: Icons.wc,
      title: {
        'en': 'Sanitation / Toilet',
        'ja': 'トイレと衛生管理',
        'th': 'สุขา / การขับถ่าย'
      },
      action: {
        'en':
            'Use floating toilets or "black bags". Add lime/ash to reduce smell.',
        'ja': '浮きトイレや指定のゴミ袋を使用してください。臭い対策には石灰や灰が有効です。',
        'th':
            'ใช้ส้วมลอยน้ำหรือถ่ายใส่ถุงดำ (ถุงยังชีพ) โรยปูนขาว/ขี้เたとぶんมัดปากถุงให้แน่น',
      },
      source: 'Dept of Health',
    ),
    SurvivalGuideItem(
      id: 'mental_th',
      icon: Icons.self_improvement,
      title: {'en': 'Mental Health', 'ja': '心のケア', 'th': 'สุขภาพจิต (1323)'},
      action: {
        'en': 'Call 1323 if stressed. Practice mindfulness (Sati).',
        'ja': 'ストレスを感じたら1323へ。マインドフルネス（サティ）を実践。',
        'th': 'โทร 1323 หากเครียด ฝึกสติ (Sati) อย่าเก็บความเครียดไว้คนเดียว',
      },
      source: 'Dept of Mental Health',
    ),
    SurvivalGuideItem(
      id: 'documents',
      icon: Icons.folder,
      title: {'en': 'Important Docs', 'ja': '重要書類', 'th': 'เอกสารสำคัญ'},
      action: {
        'en':
            'Seal ID, Blue Book (Tabien Baan), and land deeds in plastic bags.',
        'ja': 'IDカード、タビアンバーン（青い本）をビニール袋で密封。',
        'th':
            'เก็บถุงพลาสติกใส่บัตรประชาชน ทะเบียนบ้าน และโฉนดที่ดิน กันน้ำให้ดีที่สุด',
      },
      source: 'DPM',
    ),
    SurvivalGuideItem(
      id: 'garbage',
      icon: Icons.delete,
      title: {'en': 'Garbage Disposal', 'ja': 'ゴミ処理', 'th': 'การจัดการขยะ'},
      action: {
        'en':
            'Separate hazardous waste (lamps, spray cans). Do not throw trash in water.',
        'ja': '危険物（蛍光灯、スプレー）は分ける。水にゴミを捨てない。',
        'th':
            'แยกขยะอันตราย (หลอดไฟ, กระป๋องสเปรย์) ห้ามทิ้งขยะลงน้ำ ป้องกันโรค',
      },
      source: 'Pollution Control Dept',
    ),
    SurvivalGuideItem(
      id: 'chronic_th',
      icon: Icons.medical_services,
      title: {'en': 'Chronic Disease', 'ja': '持病管理', 'th': 'โรคประจำตัว'},
      action: {
        'en':
            'Keep medicines high and dry. Continue taking meds as prescribed.',
        'ja': '薬を濡れない高い場所に保管。処方通りに服用を続ける。',
        'th': 'เก็บยารักษาโรคในที่สูงและแห้ง กินยาต่อเนื่องตามแพทย์สั่ง',
      },
      source: 'MoPH',
    ),
    SurvivalGuideItem(
      id: 'community',
      icon: Icons.people,
      title: {'en': 'Community Help', 'ja': '助け合い', 'th': 'น้ำใจ (Nam Jai)'},
      action: {
        'en': 'Help vulnerable neighbors. Share food and water.',
        'ja': '高齢者や弱者を助ける。水や食料を分け合う。',
        'th':
            'ช่วยเหลือเพื่อนบ้าน ผู้สูงอายุ แบ่งปันอาหารและน้ำดื่ม (คนไทยไม่ทิ้งกัน)',
      },
      source: 'Community Liason',
    ),
    SurvivalGuideItem(
      id: 'leech',
      icon: Icons.bug_report, // Closest
      title: {'en': 'Leeches/Insects', 'ja': 'ヒル・虫対策', 'th': 'ปลิงและแมลง'},
      action: {
        'en': 'Wear long socks/pants. Use salt or vinegar for leeches.',
        'ja': '長ズボン着用。ヒルには塩か酢を使う。',
        'th': 'สวมกางเกงขายาว หากโดนปลิงเกาะให้ใช้น้ำส้มสายชูหรือเกลือ',
      },
      source: 'Local Wisdom',
    ),
  ];
}
