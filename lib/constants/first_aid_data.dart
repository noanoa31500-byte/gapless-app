import 'package:flutter/material.dart';

/// 応急処置データ
/// オフラインで完全動作する命を救う情報
class FirstAidItem {
  final String id;
  final IconData icon;
  final Map<String, String> title;
  final Map<String, String> summary;
  final List<FirstAidStep> steps;
  final Color color;
  final bool isLifeThreatening; // 命に関わる緊急度

  const FirstAidItem({
    required this.id,
    required this.icon,
    required this.title,
    required this.summary,
    required this.steps,
    this.color = Colors.red,
    this.isLifeThreatening = false,
  });
}

class FirstAidStep {
  final Map<String, String> instruction;
  final IconData? icon;
  final int? durationSeconds;
  final bool isWarning; // 警告ステップ

  const FirstAidStep({
    required this.instruction,
    this.icon,
    this.durationSeconds,
    this.isWarning = false,
  });
}

class FirstAidData {
  /// 応急処置ガイド（生命に関わる重要6項目）
  static const List<FirstAidItem> items = [
    // 1. 止血
    FirstAidItem(
      id: 'bleeding',
      icon: Icons.water_drop,
      color: Color(0xFFD32F2F),
      isLifeThreatening: true,
      title: {
        'ja': '止血',
        'en': 'Stop Bleeding',
        'th': 'หยุดเลือด',
      },
      summary: {
        'ja': '出血を止める基本手順',
        'en': 'Basic steps to stop bleeding',
        'th': 'ขั้นตอนพื้นฐานในการหยุดเลือด',
      },
      steps: [
        FirstAidStep(
          icon: Icons.pan_tool,
          instruction: {
            'ja': '清潔な布で傷口を強く押さえる',
            'en': 'Press wound firmly with clean cloth',
            'th': 'กดแผลด้วยผ้าสะอาดอย่างแน่น',
          },
        ),
        FirstAidStep(
          icon: Icons.timer,
          instruction: {
            'ja': '最低10分間、圧迫を続ける',
            'en': 'Keep pressure for at least 10 minutes',
            'th': 'กดต่อเนื่องอย่างน้อย 10 นาที',
          },
          durationSeconds: 600,
        ),
        FirstAidStep(
          icon: Icons.arrow_upward,
          instruction: {
            'ja': '傷口を心臓より高く上げる',
            'en': 'Raise wound above heart level',
            'th': 'ยกแผลให้สูงกว่าหัวใจ',
          },
        ),
        FirstAidStep(
          icon: Icons.do_not_touch,
          isWarning: true,
          instruction: {
            'ja': '⚠️ 布を外さない（血が固まるのを妨げる）',
            'en': '⚠️ Do NOT remove cloth (prevents clotting)',
            'th': '⚠️ อย่าเอาผ้าออก (ขัดขวางการแข็งตัว)',
          },
        ),
        FirstAidStep(
          icon: Icons.local_hospital,
          instruction: {
            'ja': '出血が止まらない場合は医療機関へ',
            'en': 'Seek medical help if bleeding continues',
            'th': 'หากเลือดไม่หยุดให้ไปพบแพทย์',
          },
        ),
      ],
    ),

    // 2. 心肺蘇生法（CPR）
    FirstAidItem(
      id: 'cpr',
      icon: Icons.favorite,
      color: Color(0xFFC62828),
      isLifeThreatening: true,
      title: {
        'ja': '心肺蘇生法（CPR）',
        'en': 'CPR',
        'th': 'การปั๊มหัวใจ (CPR)',
      },
      summary: {
        'ja': '意識がない人への救命処置',
        'en': 'Life-saving for unconscious person',
        'th': 'การช่วยชีวิตคนหมดสติ',
      },
      steps: [
        FirstAidStep(
          icon: Icons.record_voice_over,
          instruction: {
            'ja': '反応を確認：肩を叩き、大声で呼びかける',
            'en': 'Check response: Tap shoulder, call loudly',
            'th': 'ตรวจสอบการตอบสนอง: ตบไหล่ เรียกดังๆ',
          },
        ),
        FirstAidStep(
          icon: Icons.phone,
          instruction: {
            'ja': '119番通報（誰かに頼む）',
            'en': 'Call emergency (ask someone)',
            'th': 'โทร 1669 (ให้คนอื่นโทร)',
          },
        ),
        FirstAidStep(
          icon: Icons.air,
          instruction: {
            'ja': '呼吸を確認：胸の動きを10秒見る',
            'en': 'Check breathing: Watch chest for 10 sec',
            'th': 'ตรวจการหายใจ: ดูหน้าอก 10 วินาที',
          },
          durationSeconds: 10,
        ),
        FirstAidStep(
          icon: Icons.compress,
          instruction: {
            'ja': '胸骨圧迫：両手を胸の中央に置き、5cm沈むまで強く押す',
            'en':
                'Chest compressions: Both hands on chest center, push 5cm deep',
            'th': 'กดหน้าอก: วางมือทั้งสองตรงกลางอก กด 5 ซม.',
          },
        ),
        FirstAidStep(
          icon: Icons.speed,
          instruction: {
            'ja': '1分間に100〜120回のペースで30回圧迫',
            'en': '30 compressions at 100-120 per minute',
            'th': 'กด 30 ครั้ง ที่ 100-120 ครั้ง/นาที',
          },
        ),
        FirstAidStep(
          icon: Icons.repeat,
          instruction: {
            'ja': '救急隊が来るまで続ける',
            'en': 'Continue until help arrives',
            'th': 'ทำต่อจนกว่าจะมีคนมาช่วย',
          },
        ),
      ],
    ),

    // 3. 窒息対応
    FirstAidItem(
      id: 'choking',
      icon: Icons.air,
      color: Color(0xFFE65100),
      isLifeThreatening: true,
      title: {
        'ja': '窒息対応',
        'en': 'Choking Response',
        'th': 'การช่วยคนสำลัก',
      },
      summary: {
        'ja': '喉に詰まった時の対処',
        'en': 'When something is stuck in throat',
        'th': 'เมื่อมีสิ่งติดคอ',
      },
      steps: [
        FirstAidStep(
          icon: Icons.help_outline,
          instruction: {
            'ja': '「喉に詰まった？」と確認',
            'en': 'Ask "Are you choking?"',
            'th': 'ถามว่า "สำลักหรือเปล่า?"',
          },
        ),
        FirstAidStep(
          icon: Icons.back_hand,
          instruction: {
            'ja': '背部叩打法：前かがみにさせ、背中を5回叩く',
            'en': 'Back blows: Lean forward, 5 back blows',
            'th': 'ตบหลัง: ให้ก้มตัว ตบหลัง 5 ครั้ง',
          },
        ),
        FirstAidStep(
          icon: Icons.sports_mma,
          instruction: {
            'ja': '腹部突き上げ法：後ろから抱え、みぞおちを5回突き上げる',
            'en': 'Abdominal thrusts: From behind, 5 upward thrusts',
            'th': 'กดท้อง: อ้อมหลัง กดขึ้น 5 ครั้ง',
          },
        ),
        FirstAidStep(
          icon: Icons.repeat,
          instruction: {
            'ja': '異物が出るまで繰り返す',
            'en': 'Repeat until object comes out',
            'th': 'ทำซ้ำจนกว่าสิ่งแปลกปลอมจะออก',
          },
        ),
        FirstAidStep(
          icon: Icons.warning,
          isWarning: true,
          instruction: {
            'ja': '⚠️ 意識を失ったらCPRを開始',
            'en': '⚠️ Start CPR if unconscious',
            'th': '⚠️ ถ้าหมดสติให้ทำ CPR',
          },
        ),
      ],
    ),

    // 4. 骨折対応
    FirstAidItem(
      id: 'fracture',
      icon: Icons.accessibility_new,
      color: Color(0xFF1565C0),
      title: {
        'ja': '骨折対応',
        'en': 'Fracture Care',
        'th': 'การดูแลกระดูกหัก',
      },
      summary: {
        'ja': '骨折が疑われる時の対処',
        'en': 'When fracture is suspected',
        'th': 'เมื่อสงสัยกระดูกหัก',
      },
      steps: [
        FirstAidStep(
          icon: Icons.do_not_touch,
          instruction: {
            'ja': '動かさない：患部を無理に動かさない',
            'en': 'Do not move: Keep injured area still',
            'th': 'อย่าขยับ: อย่าขยับบริเวณที่บาดเจ็บ',
          },
        ),
        FirstAidStep(
          icon: Icons.support,
          instruction: {
            'ja': '固定する：板や雑誌で添え木を作り固定',
            'en': 'Immobilize: Use board or magazine as splint',
            'th': 'ตรึง: ใช้ไม้หรือนิตยสารเป็นเฝือก',
          },
        ),
        FirstAidStep(
          icon: Icons.ac_unit,
          instruction: {
            'ja': '冷やす：氷や冷たいものを当てる（直接は×）',
            'en': 'Ice: Apply cold (not directly on skin)',
            'th': 'ประคบเย็น: (ไม่สัมผัสผิวโดยตรง)',
          },
        ),
        FirstAidStep(
          icon: Icons.arrow_upward,
          instruction: {
            'ja': '挙上する：可能なら心臓より高く',
            'en': 'Elevate: Raise above heart if possible',
            'th': 'ยกสูง: ยกให้สูงกว่าหัวใจถ้าเป็นไปได้',
          },
        ),
        FirstAidStep(
          icon: Icons.local_hospital,
          instruction: {
            'ja': '医療機関へ：必ず病院で診察を受ける',
            'en': 'Seek medical care: Always see a doctor',
            'th': 'ไปพบแพทย์: ต้องไปโรงพยาบาล',
          },
        ),
      ],
    ),

    // 5. やけど対応
    FirstAidItem(
      id: 'burn',
      icon: Icons.local_fire_department,
      color: Color(0xFFFF6F00),
      title: {
        'ja': 'やけど対応',
        'en': 'Burn Treatment',
        'th': 'การรักษาแผลไฟไหม้',
      },
      summary: {
        'ja': 'やけどの応急処置',
        'en': 'First aid for burns',
        'th': 'การปฐมพยาบาลแผลไฟไหม้',
      },
      steps: [
        FirstAidStep(
          icon: Icons.water,
          instruction: {
            'ja': '冷水で20分以上冷やす',
            'en': 'Cool with running water for 20+ minutes',
            'th': 'ใช้น้ำเย็นล้างนาน 20+ นาที',
          },
          durationSeconds: 1200,
        ),
        FirstAidStep(
          icon: Icons.do_not_touch,
          isWarning: true,
          instruction: {
            'ja': '⚠️ 氷は使わない（凍傷の危険）',
            'en': '⚠️ Do NOT use ice (frostbite risk)',
            'th': '⚠️ อย่าใช้น้ำแข็ง (เสี่ยงบาดแผลจากความเย็น)',
          },
        ),
        FirstAidStep(
          icon: Icons.healing,
          instruction: {
            'ja': '清潔なガーゼでやさしく覆う',
            'en': 'Cover gently with clean gauze',
            'th': 'ปิดด้วยผ้าก๊อซสะอาดเบาๆ',
          },
        ),
        FirstAidStep(
          icon: Icons.do_not_touch,
          isWarning: true,
          instruction: {
            'ja': '⚠️ 水ぶくれを破らない',
            'en': '⚠️ Do NOT pop blisters',
            'th': '⚠️ อย่าเจาะตุ่มน้ำ',
          },
        ),
        FirstAidStep(
          icon: Icons.local_hospital,
          instruction: {
            'ja': '広範囲・顔・手は必ず病院へ',
            'en': 'Large burns, face, hands: See doctor',
            'th': 'บาดแผลกว้าง หน้า มือ: ไปพบแพทย์',
          },
        ),
      ],
    ),

    // 6. 熱中症対応
    FirstAidItem(
      id: 'heatstroke',
      icon: Icons.wb_sunny,
      color: Color(0xFFF57C00),
      title: {
        'ja': '熱中症対応',
        'en': 'Heatstroke',
        'th': 'โรคลมแดด',
      },
      summary: {
        'ja': '熱中症の応急処置',
        'en': 'First aid for heatstroke',
        'th': 'การปฐมพยาบาลโรคลมแดด',
      },
      steps: [
        FirstAidStep(
          icon: Icons.home,
          instruction: {
            'ja': '涼しい場所に移動させる',
            'en': 'Move to cool place',
            'th': 'ย้ายไปที่เย็น',
          },
        ),
        FirstAidStep(
          icon: Icons.checkroom,
          instruction: {
            'ja': '衣服を緩め、体を冷やす',
            'en': 'Loosen clothes, cool the body',
            'th': 'คลายเสื้อผ้า ทำให้ร่างกายเย็น',
          },
        ),
        FirstAidStep(
          icon: Icons.water_drop,
          instruction: {
            'ja': '首・脇・太ももの付け根を冷やす',
            'en': 'Cool neck, armpits, and groin',
            'th': 'ประคบเย็นที่คอ รักแร้ ขาหนีบ',
          },
        ),
        FirstAidStep(
          icon: Icons.local_drink,
          instruction: {
            'ja': '意識があれば水分・塩分を補給',
            'en': 'If conscious, give water and salt',
            'th': 'ถ้ารู้สึกตัว ให้น้ำและเกลือ',
          },
        ),
        FirstAidStep(
          icon: Icons.warning,
          isWarning: true,
          instruction: {
            'ja': '⚠️ 意識がない場合は水を飲ませない',
            'en': '⚠️ Do NOT give water if unconscious',
            'th': '⚠️ อย่าให้น้ำถ้าหมดสติ',
          },
        ),
        FirstAidStep(
          icon: Icons.local_hospital,
          instruction: {
            'ja': '症状が重い場合は救急車を呼ぶ',
            'en': 'Call ambulance if severe',
            'th': 'โทรรถพยาบาลถ้าอาการหนัก',
          },
        ),
      ],
    ),
  ];
}

/// 災害別行動指針
class DisasterActionItem {
  final String id;
  final IconData icon;
  final Map<String, String> title;
  final List<DisasterActionStep> steps;
  final Color color;

  const DisasterActionItem({
    required this.id,
    required this.icon,
    required this.title,
    required this.steps,
    this.color = Colors.orange,
  });
}

class DisasterActionStep {
  final Map<String, String> action;
  final IconData? icon;
  final bool isDont; // やってはいけないこと

  const DisasterActionStep({
    required this.action,
    this.icon,
    this.isDont = false,
  });
}

class DisasterActionData {
  /// 災害別行動指針
  static const List<DisasterActionItem> items = [
    // 地震
    DisasterActionItem(
      id: 'earthquake',
      icon: Icons.warning_amber,
      color: Color(0xFFD32F2F),
      title: {
        'ja': '地震発生時',
        'en': 'During Earthquake',
        'th': 'เมื่อเกิดแผ่นดินไหว',
      },
      steps: [
        DisasterActionStep(
          icon: Icons.table_bar,
          action: {
            'ja': '机の下に隠れ、頭を守る',
            'en': 'Hide under desk, protect head',
            'th': 'หลบใต้โต๊ะ ป้องกันหัว',
          },
        ),
        DisasterActionStep(
          icon: Icons.door_front_door,
          action: {
            'ja': '揺れが収まったら出口を確保',
            'en': 'After shaking, secure exit',
            'th': 'หลังไหวหยุด หาทางออก',
          },
        ),
        DisasterActionStep(
          icon: Icons.local_fire_department,
          action: {
            'ja': '火の元を確認、消火',
            'en': 'Check fire sources, extinguish',
            'th': 'ตรวจแหล่งไฟ ดับไฟ',
          },
        ),
        DisasterActionStep(
          icon: Icons.elevator,
          isDont: true,
          action: {
            'ja': '❌ エレベーターは使わない',
            'en': '❌ Do NOT use elevator',
            'th': '❌ อย่าใช้ลิฟต์',
          },
        ),
        DisasterActionStep(
          icon: Icons.directions_run,
          action: {
            'ja': '余震に注意しながら避難',
            'en': 'Evacuate, beware of aftershocks',
            'th': 'อพยพ ระวังอาฟเตอร์ช็อก',
          },
        ),
      ],
    ),

    // 洪水
    DisasterActionItem(
      id: 'flood',
      icon: Icons.water,
      color: Color(0xFF1565C0),
      title: {
        'ja': '洪水発生時',
        'en': 'During Flood',
        'th': 'เมื่อเกิดน้ำท่วม',
      },
      steps: [
        DisasterActionStep(
          icon: Icons.arrow_upward,
          action: {
            'ja': '高い場所へ移動',
            'en': 'Move to higher ground',
            'th': 'ย้ายไปที่สูง',
          },
        ),
        DisasterActionStep(
          icon: Icons.bolt,
          isDont: true,
          action: {
            'ja': '❌ 電柱・電線に近づかない（感電死）',
            'en': '❌ Stay away from power lines (electrocution)',
            'th': '❌ อย่าเข้าใกล้เสาไฟ (ไฟดูด)',
          },
        ),
        DisasterActionStep(
          icon: Icons.water,
          isDont: true,
          action: {
            'ja': '❌ 濁った水に入らない',
            'en': '❌ Do NOT enter murky water',
            'th': '❌ อย่าลงน้ำขุ่น',
          },
        ),
        DisasterActionStep(
          icon: Icons.car_crash,
          isDont: true,
          action: {
            'ja': '❌ 車で水没エリアを走らない',
            'en': '❌ Do NOT drive through flooded area',
            'th': '❌ อย่าขับรถผ่านน้ำท่วม',
          },
        ),
        DisasterActionStep(
          icon: Icons.radio,
          action: {
            'ja': '最新情報を確認',
            'en': 'Check latest updates',
            'th': 'ตรวจสอบข้อมูลล่าสุด',
          },
        ),
      ],
    ),

    // 火災
    DisasterActionItem(
      id: 'fire',
      icon: Icons.local_fire_department,
      color: Color(0xFFE65100),
      title: {
        'ja': '火災発生時',
        'en': 'During Fire',
        'th': 'เมื่อเกิดไฟไหม้',
      },
      steps: [
        DisasterActionStep(
          icon: Icons.campaign,
          action: {
            'ja': '「火事だ！」と大声で知らせる',
            'en': 'Shout "FIRE!" loudly',
            'th': 'ตะโกนว่า "ไฟไหม้!"',
          },
        ),
        DisasterActionStep(
          icon: Icons.phone,
          action: {
            'ja': '119番通報',
            'en': 'Call emergency',
            'th': 'โทร 199',
          },
        ),
        DisasterActionStep(
          icon: Icons.low_priority,
          action: {
            'ja': '姿勢を低くして煙を避ける',
            'en': 'Stay low to avoid smoke',
            'th': 'ก้มต่ำเพื่อหนีควัน',
          },
        ),
        DisasterActionStep(
          icon: Icons.door_front_door,
          action: {
            'ja': 'ドアを閉めて延焼を防ぐ',
            'en': 'Close doors to prevent spread',
            'th': 'ปิดประตูป้องกันไฟลาม',
          },
        ),
        DisasterActionStep(
          icon: Icons.elevator,
          isDont: true,
          action: {
            'ja': '❌ エレベーターは使わない',
            'en': '❌ Do NOT use elevator',
            'th': '❌ อย่าใช้ลิฟต์',
          },
        ),
      ],
    ),

    // 津波
    DisasterActionItem(
      id: 'tsunami',
      icon: Icons.waves,
      color: Color(0xFF0277BD),
      title: {
        'ja': '津波発生時',
        'en': 'During Tsunami',
        'th': 'เมื่อเกิดสึนามิ',
      },
      steps: [
        DisasterActionStep(
          icon: Icons.directions_run,
          action: {
            'ja': 'すぐに高台へ逃げる',
            'en': 'Run to high ground immediately',
            'th': 'วิ่งไปที่สูงทันที',
          },
        ),
        DisasterActionStep(
          icon: Icons.arrow_upward,
          action: {
            'ja': '海から離れる方向へ',
            'en': 'Move away from the sea',
            'th': 'ออกจากทะเล',
          },
        ),
        DisasterActionStep(
          icon: Icons.apartment,
          action: {
            'ja': '高台がなければ頑丈な建物の3階以上へ',
            'en': 'If no high ground, go to 3rd floor or higher',
            'th': 'ถ้าไม่มีที่สูง ไปชั้น 3 ขึ้นไป',
          },
        ),
        DisasterActionStep(
          icon: Icons.beach_access,
          isDont: true,
          action: {
            'ja': '❌ 海岸に戻らない',
            'en': '❌ Do NOT return to beach',
            'th': '❌ อย่ากลับไปชายหาด',
          },
        ),
        DisasterActionStep(
          icon: Icons.timer,
          action: {
            'ja': '警報解除まで高台にいる',
            'en': 'Stay until warning is cleared',
            'th': 'อยู่จนกว่าจะยกเลิกเตือน',
          },
        ),
      ],
    ),
  ];
}
