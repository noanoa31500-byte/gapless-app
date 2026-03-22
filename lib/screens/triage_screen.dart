import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/shelter_provider.dart';
import '../providers/location_provider.dart';
import '../utils/localization.dart';
import '../utils/styles.dart';
import '../widgets/safe_text.dart';
import 'package:latlong2/latlong.dart';

/// トリアージ画面
/// 質問形式で怪我の重症度を判断し、適切な避難所を提案
class TriageScreen extends StatefulWidget {
  const TriageScreen({super.key});

  @override
  State<TriageScreen> createState() => _TriageScreenState();
}

class _TriageScreenState extends State<TriageScreen> {
  int _currentStep = 0;
  final Map<String, dynamic> _answers = {};
  TriageResult? _result;

  @override
  Widget build(BuildContext context) {
    final lang = GapLessL10n.lang;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: SafeText(
          _getTitle(lang),
          style: emergencyTextStyle(size: 20, isBold: true),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _result != null ? _buildResultView(lang) : _buildQuestionView(lang),
    );
  }

  String _getTitle(String lang) {
    return GapLessL10n.t('triage_title');
  }

  /// 質問ビュー
  Widget _buildQuestionView(String lang) {
    final questions = _getQuestions(lang);

    if (_currentStep >= questions.length) {
      // 全問回答完了 -> 結果を計算
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _calculateResult();
      });
      return const Center(child: CircularProgressIndicator());
    }

    final question = questions[_currentStep];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress
            LinearProgressIndicator(
              value: (_currentStep + 1) / questions.length,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation(Color(0xFFE53935)),
            ),
            const SizedBox(height: 8),
            SafeText(
              '${_currentStep + 1} / ${questions.length}',
              style: emergencyTextStyle(size: 12, color: Colors.grey),
            ),
            const SizedBox(height: 32),

            // Question Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: question.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(question.icon, size: 48, color: question.color),
            ),
            const SizedBox(height: 24),

            // Question Text
            SafeText(
              question.text,
              style: emergencyTextStyle(size: 24, isBold: true),
            ),
            const SizedBox(height: 8),
            if (question.subtext != null)
              SafeText(
                question.subtext!,
                style: emergencyTextStyle(size: 14, color: Colors.grey),
              ),
            const SizedBox(height: 32),

            // Answer Options
            Expanded(
              child: ListView.builder(
                itemCount: question.options.length,
                itemBuilder: (context, index) {
                  final option = question.options[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildOptionButton(option, question),
                  );
                },
              ),
            ),

            // Back Button
            if (_currentStep > 0)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _currentStep--;
                  });
                },
                icon: const Icon(Icons.arrow_back),
                label: SafeText(_getBackLabel(lang)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionButton(TriageOption option, TriageQuestion question) {
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _answers[question.id] = option.value;
          _currentStep++;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: option.isUrgent ? Colors.red[50] : Colors.grey[100],
        foregroundColor: option.isUrgent ? Colors.red[900] : Colors.black87,
        elevation: 0,
        padding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: option.isUrgent
              ? const BorderSide(color: Colors.red, width: 2)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          if (option.icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(option.icon, size: 24),
            ),
          Expanded(
            child: SafeText(
              option.text,
              style: emergencyTextStyle(
                size: 16,
                isBold: true,
                color: option.isUrgent ? Colors.red[900]! : Colors.black87,
              ),
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }

  String _getBackLabel(String lang) {
    return GapLessL10n.t('triage_back');
  }

  /// 結果を計算
  void _calculateResult() {
    int severityScore = 0;
    bool needsMedical = false;
    bool isLifeThreatening = false;

    // スコア計算
    if (_answers['breathing'] == 'difficult' ||
        _answers['breathing'] == 'stopped') {
      severityScore += 50;
      isLifeThreatening = true;
      needsMedical = true;
    }

    if (_answers['bleeding'] == 'heavy') {
      severityScore += 40;
      isLifeThreatening = true;
      needsMedical = true;
    } else if (_answers['bleeding'] == 'moderate') {
      severityScore += 20;
      needsMedical = true;
    }

    if (_answers['consciousness'] == 'confused' ||
        _answers['consciousness'] == 'unconscious') {
      severityScore += 50;
      isLifeThreatening = true;
      needsMedical = true;
    }

    if (_answers['mobility'] == 'cannot_walk') {
      severityScore += 30;
      needsMedical = true;
    } else if (_answers['mobility'] == 'difficulty') {
      severityScore += 15;
    }

    if (_answers['pain'] == 'severe') {
      severityScore += 20;
      needsMedical = true;
    } else if (_answers['pain'] == 'moderate') {
      severityScore += 10;
    }

    // 結果を設定
    TriageSeverity severity;
    if (isLifeThreatening || severityScore >= 50) {
      severity = TriageSeverity.critical;
    } else if (needsMedical || severityScore >= 30) {
      severity = TriageSeverity.urgent;
    } else if (severityScore >= 15) {
      severity = TriageSeverity.moderate;
    } else {
      severity = TriageSeverity.minor;
    }

    setState(() {
      _result = TriageResult(
        severity: severity,
        needsMedical: needsMedical,
        score: severityScore,
      );
    });
  }

  /// 結果ビュー
  Widget _buildResultView(String lang) {
    final result = _result!;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Result Icon
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: result.severity.color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                result.severity.icon,
                size: 64,
                color: result.severity.color,
              ),
            ),
            const SizedBox(height: 24),

            // Result Title
            SafeText(
              result.severity.getTitle(lang),
              style: emergencyTextStyle(size: 28, isBold: true),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            SafeText(
              result.severity.getDescription(lang),
              style: emergencyTextStyle(size: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Recommendation Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: result.severity.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: result.severity.color),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SafeText(
                    _getRecommendationTitle(lang),
                    style: emergencyTextStyle(size: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  SafeText(
                    result.severity.getRecommendation(lang),
                    style: emergencyTextStyle(size: 18, isBold: true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            if (result.needsMedical)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _navigateToHospital(),
                  icon: const Icon(Icons.local_hospital),
                  label: SafeText(
                    _getGoToHospitalLabel(lang),
                    style: emergencyTextStyle(color: Colors.white, isBold: true),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _navigateToShelter(),
                icon: const Icon(Icons.night_shelter),
                label: SafeText(
                  _getGoToShelterLabel(lang),
                  style: emergencyTextStyle(
                      color: result.needsMedical ? Colors.black87 : Colors.white,
                      isBold: true),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      result.needsMedical ? Colors.grey[200] : Colors.green,
                  foregroundColor:
                      result.needsMedical ? Colors.black87 : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Restart
            TextButton(
              onPressed: () {
                setState(() {
                  _currentStep = 0;
                  _answers.clear();
                  _result = null;
                });
              },
              child: SafeText(
                _getRestartLabel(lang),
                style: emergencyTextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getRecommendationTitle(String lang) {
    return GapLessL10n.t('triage_recommendation');
  }

  String _getGoToHospitalLabel(String lang) {
    return GapLessL10n.t('triage_go_hospital');
  }

  String _getGoToShelterLabel(String lang) {
    return GapLessL10n.t('triage_go_shelter');
  }

  String _getRestartLabel(String lang) {
    return GapLessL10n.t('triage_restart');
  }

  Future<void> _navigateToHospital() async {
    final shelterProvider = context.read<ShelterProvider>();
    final locationProvider = context.read<LocationProvider>();
    final userLoc = locationProvider.currentLocation;

    if (userLoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(GapLessL10n.t('location_not_available'))),
      );
      return;
    }

    final nearest = shelterProvider.getNearestShelter(
      LatLng(userLoc.latitude, userLoc.longitude),
      includeTypes: ['hospital'],
    );

    if (nearest != null) {
      await shelterProvider.startNavigation(nearest);
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.pushNamed(context, '/compass');
    }
  }

  Future<void> _navigateToShelter() async {
    final shelterProvider = context.read<ShelterProvider>();
    final locationProvider = context.read<LocationProvider>();
    final userLoc = locationProvider.currentLocation;

    if (userLoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(GapLessL10n.t('location_not_available'))),
      );
      return;
    }

    final nearest = shelterProvider.getNearestShelter(
      LatLng(userLoc.latitude, userLoc.longitude),
      includeTypes: ['shelter', 'school', 'gov'],
    );

    if (nearest != null) {
      await shelterProvider.startNavigation(nearest);
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.pushNamed(context, '/compass');
    }
  }

  /// 質問リストを取得
  List<TriageQuestion> _getQuestions(String lang) {
    return [
      // 1. 呼吸
      TriageQuestion(
        id: 'breathing',
        icon: Icons.air,
        color: Colors.blue,
        text: lang == 'ja'
            ? '呼吸の状態は？'
            : (lang == 'th' ? 'สถานะการหายใจ?' : 'Breathing status?'),
        options: [
          TriageOption(
            text: lang == 'ja'
                ? '正常に呼吸できている'
                : (lang == 'th' ? 'หายใจได้ปกติ' : 'Breathing normally'),
            value: 'normal',
            icon: Icons.check_circle,
          ),
          TriageOption(
            text: lang == 'ja'
                ? '息苦しい・浅い'
                : (lang == 'th' ? 'หายใจลำบาก/ตื้น' : 'Difficult/shallow'),
            value: 'difficult',
            icon: Icons.warning,
            isUrgent: true,
          ),
          TriageOption(
            text: lang == 'ja'
                ? '呼吸していない'
                : (lang == 'th' ? 'ไม่หายใจ' : 'Not breathing'),
            value: 'stopped',
            icon: Icons.emergency,
            isUrgent: true,
          ),
        ],
      ),

      // 2. 出血
      TriageQuestion(
        id: 'bleeding',
        icon: Icons.water_drop,
        color: Colors.red,
        text: lang == 'ja'
            ? '出血の状態は？'
            : (lang == 'th' ? 'สถานะการเลือดออก?' : 'Bleeding status?'),
        options: [
          TriageOption(
            text: lang == 'ja'
                ? '出血なし / 軽い傷'
                : (lang == 'th' ? 'ไม่มี/บาดแผลเล็กน้อย' : 'None/minor'),
            value: 'none',
            icon: Icons.check_circle,
          ),
          TriageOption(
            text: lang == 'ja'
                ? '中程度の出血'
                : (lang == 'th' ? 'เลือดออกปานกลาง' : 'Moderate bleeding'),
            value: 'moderate',
            icon: Icons.warning,
          ),
          TriageOption(
            text: lang == 'ja'
                ? '大量出血 / 止まらない'
                : (lang == 'th' ? 'เลือดออกมาก/ไม่หยุด' : 'Heavy/won\'t stop'),
            value: 'heavy',
            icon: Icons.emergency,
            isUrgent: true,
          ),
        ],
      ),

      // 3. 意識
      TriageQuestion(
        id: 'consciousness',
        icon: Icons.psychology,
        color: Colors.purple,
        text: lang == 'ja'
            ? '意識の状態は？'
            : (lang == 'th' ? 'ระดับสติ?' : 'Consciousness level?'),
        subtext: lang == 'ja'
            ? '（自分自身または負傷者）'
            : (lang == 'th' ? '(ตัวเองหรือผู้บาดเจ็บ)' : '(yourself or injured person)'),
        options: [
          TriageOption(
            text: lang == 'ja'
                ? 'はっきりしている'
                : (lang == 'th' ? 'รู้สึกตัวดี' : 'Alert and clear'),
            value: 'clear',
            icon: Icons.check_circle,
          ),
          TriageOption(
            text: lang == 'ja'
                ? '混乱している / ぼんやり'
                : (lang == 'th' ? 'สับสน/มึนงง' : 'Confused/drowsy'),
            value: 'confused',
            icon: Icons.warning,
            isUrgent: true,
          ),
          TriageOption(
            text: lang == 'ja'
                ? '意識がない'
                : (lang == 'th' ? 'หมดสติ' : 'Unconscious'),
            value: 'unconscious',
            icon: Icons.emergency,
            isUrgent: true,
          ),
        ],
      ),

      // 4. 歩行
      TriageQuestion(
        id: 'mobility',
        icon: Icons.directions_walk,
        color: Colors.orange,
        text: lang == 'ja'
            ? '歩行の状態は？'
            : (lang == 'th' ? 'สามารถเดินได้ไหม?' : 'Can you walk?'),
        options: [
          TriageOption(
            text: lang == 'ja'
                ? '普通に歩ける'
                : (lang == 'th' ? 'เดินได้ปกติ' : 'Walk normally'),
            value: 'normal',
            icon: Icons.check_circle,
          ),
          TriageOption(
            text: lang == 'ja'
                ? '歩きにくい / 痛い'
                : (lang == 'th' ? 'เดินลำบาก/เจ็บ' : 'Difficult/painful'),
            value: 'difficulty',
            icon: Icons.warning,
          ),
          TriageOption(
            text: lang == 'ja'
                ? '歩けない'
                : (lang == 'th' ? 'เดินไม่ได้' : 'Cannot walk'),
            value: 'cannot_walk',
            icon: Icons.accessible,
            isUrgent: true,
          ),
        ],
      ),

      // 5. 痛み
      TriageQuestion(
        id: 'pain',
        icon: Icons.healing,
        color: Colors.amber,
        text: lang == 'ja'
            ? '痛みの程度は？'
            : (lang == 'th' ? 'ระดับความเจ็บปวด?' : 'Pain level?'),
        options: [
          TriageOption(
            text: lang == 'ja'
                ? '痛みなし / 軽い'
                : (lang == 'th' ? 'ไม่เจ็บ/เจ็บเล็กน้อย' : 'None/mild'),
            value: 'mild',
            icon: Icons.check_circle,
          ),
          TriageOption(
            text: lang == 'ja'
                ? '中程度の痛み'
                : (lang == 'th' ? 'ปานกลาง' : 'Moderate'),
            value: 'moderate',
            icon: Icons.warning,
          ),
          TriageOption(
            text: lang == 'ja'
                ? '激しい痛み'
                : (lang == 'th' ? 'เจ็บมาก' : 'Severe pain'),
            value: 'severe',
            icon: Icons.emergency,
            isUrgent: true,
          ),
        ],
      ),
    ];
  }
}

/// 質問モデル
class TriageQuestion {
  final String id;
  final IconData icon;
  final Color color;
  final String text;
  final String? subtext;
  final List<TriageOption> options;

  const TriageQuestion({
    required this.id,
    required this.icon,
    required this.color,
    required this.text,
    this.subtext,
    required this.options,
  });
}

class TriageOption {
  final String text;
  final String value;
  final IconData? icon;
  final bool isUrgent;

  const TriageOption({
    required this.text,
    required this.value,
    this.icon,
    this.isUrgent = false,
  });
}

/// 結果モデル
class TriageResult {
  final TriageSeverity severity;
  final bool needsMedical;
  final int score;

  const TriageResult({
    required this.severity,
    required this.needsMedical,
    required this.score,
  });
}

enum TriageSeverity {
  critical,
  urgent,
  moderate,
  minor;

  Color get color {
    switch (this) {
      case TriageSeverity.critical:
        return Colors.red;
      case TriageSeverity.urgent:
        return Colors.orange;
      case TriageSeverity.moderate:
        return Colors.amber;
      case TriageSeverity.minor:
        return Colors.green;
    }
  }

  IconData get icon {
    switch (this) {
      case TriageSeverity.critical:
        return Icons.emergency;
      case TriageSeverity.urgent:
        return Icons.warning_amber;
      case TriageSeverity.moderate:
        return Icons.info;
      case TriageSeverity.minor:
        return Icons.check_circle;
    }
  }

  String getTitle(String lang) {
    switch (this) {
      case TriageSeverity.critical:
        return lang == 'ja'
            ? '緊急：今すぐ医療が必要'
            : (lang == 'th' ? 'วิกฤต: ต้องการแพทย์ทันที' : 'CRITICAL: Need immediate medical care');
      case TriageSeverity.urgent:
        return lang == 'ja'
            ? '要注意：医療機関への受診を推奨'
            : (lang == 'th' ? 'ด่วน: แนะนำให้ไปพบแพทย์' : 'URGENT: Medical attention recommended');
      case TriageSeverity.moderate:
        return lang == 'ja'
            ? '中程度：様子を見ながら避難'
            : (lang == 'th' ? 'ปานกลาง: อพยพและสังเกตอาการ' : 'MODERATE: Evacuate and monitor');
      case TriageSeverity.minor:
        return lang == 'ja'
            ? '軽症：避難所で対応可能'
            : (lang == 'th' ? 'เล็กน้อย: สามารถรักษาที่พักพิงได้' : 'MINOR: Can be handled at shelter');
    }
  }

  String getDescription(String lang) {
    switch (this) {
      case TriageSeverity.critical:
        return lang == 'ja'
            ? '生命に関わる可能性があります。直ちに医療機関へ向かってください。'
            : (lang == 'th'
                ? 'อาจเป็นอันตรายถึงชีวิต ไปโรงพยาบาลทันที'
                : 'May be life-threatening. Go to hospital immediately.');
      case TriageSeverity.urgent:
        return lang == 'ja'
            ? '医療専門家による処置が必要です。できるだけ早く受診してください。'
            : (lang == 'th'
                ? 'ต้องการการรักษาจากผู้เชี่ยวชาญ ไปพบแพทย์โดยเร็ว'
                : 'Professional treatment needed. See a doctor as soon as possible.');
      case TriageSeverity.moderate:
        return lang == 'ja'
            ? '避難所で応急処置を受けながら様子を見てください。'
            : (lang == 'th'
                ? 'รับการปฐมพยาบาลที่พักพิงและสังเกตอาการ'
                : 'Get first aid at shelter and monitor your condition.');
      case TriageSeverity.minor:
        return lang == 'ja'
            ? '軽い怪我です。避難所のスタッフに相談してください。'
            : (lang == 'th'
                ? 'บาดเจ็บเล็กน้อย ปรึกษาเจ้าหน้าที่ที่พักพิง'
                : 'Minor injury. Consult shelter staff if needed.');
    }
  }

  String getRecommendation(String lang) {
    switch (this) {
      case TriageSeverity.critical:
        return lang == 'ja'
            ? '🚨 最寄りの病院へ直行してください'
            : (lang == 'th' ? '🚨 ไปโรงพยาบาลใกล้สุดทันที' : '🚨 Go to nearest hospital immediately');
      case TriageSeverity.urgent:
        return lang == 'ja'
            ? '🏥 医療設備のある避難所を優先'
            : (lang == 'th' ? '🏥 เลือกที่พักพิงที่มีสถานพยาบาล' : '🏥 Prioritize shelter with medical facility');
      case TriageSeverity.moderate:
        return lang == 'ja'
            ? '⚠️ 避難所へ向かい、応急処置を受ける'
            : (lang == 'th' ? '⚠️ ไปที่พักพิงและรับการปฐมพยาบาล' : '⚠️ Go to shelter and get first aid');
      case TriageSeverity.minor:
        return lang == 'ja'
            ? '✅ 最寄りの避難所へ向かう'
            : (lang == 'th' ? '✅ ไปที่พักพิงใกล้สุด' : '✅ Go to nearest shelter');
    }
  }
}
