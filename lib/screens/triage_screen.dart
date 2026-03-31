import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/shelter_provider.dart';
import '../providers/location_provider.dart';
import '../providers/language_provider.dart';
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
    context.watch<LanguageProvider>(); // 言語変更時に再描画
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

  /// 質問リストを取得（全18言語対応: GapLessL10n.t() 経由）
  List<TriageQuestion> _getQuestions(String lang) {
    return [
      // 1. 呼吸
      TriageQuestion(
        id: 'breathing',
        icon: Icons.air,
        color: Colors.blue,
        text: GapLessL10n.t('triage_q_breathing'),
        options: [
          TriageOption(
            text: GapLessL10n.t('triage_breathing_normal'),
            value: 'normal',
            icon: Icons.check_circle,
          ),
          TriageOption(
            text: GapLessL10n.t('triage_breathing_difficult'),
            value: 'difficult',
            icon: Icons.warning,
            isUrgent: true,
          ),
          TriageOption(
            text: GapLessL10n.t('triage_breathing_stopped'),
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
        text: GapLessL10n.t('triage_q_bleeding'),
        options: [
          TriageOption(
            text: GapLessL10n.t('triage_bleeding_none'),
            value: 'none',
            icon: Icons.check_circle,
          ),
          TriageOption(
            text: GapLessL10n.t('triage_bleeding_moderate'),
            value: 'moderate',
            icon: Icons.warning,
          ),
          TriageOption(
            text: GapLessL10n.t('triage_bleeding_heavy'),
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
        text: GapLessL10n.t('triage_q_consciousness'),
        subtext: GapLessL10n.t('triage_q_consciousness_sub'),
        options: [
          TriageOption(
            text: GapLessL10n.t('triage_consciousness_clear'),
            value: 'clear',
            icon: Icons.check_circle,
          ),
          TriageOption(
            text: GapLessL10n.t('triage_consciousness_confused'),
            value: 'confused',
            icon: Icons.warning,
            isUrgent: true,
          ),
          TriageOption(
            text: GapLessL10n.t('triage_consciousness_unconscious'),
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
        text: GapLessL10n.t('triage_q_mobility'),
        options: [
          TriageOption(
            text: GapLessL10n.t('triage_mobility_normal'),
            value: 'normal',
            icon: Icons.check_circle,
          ),
          TriageOption(
            text: GapLessL10n.t('triage_mobility_difficult'),
            value: 'difficulty',
            icon: Icons.warning,
          ),
          TriageOption(
            text: GapLessL10n.t('triage_mobility_cannot'),
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
        text: GapLessL10n.t('triage_q_pain'),
        options: [
          TriageOption(
            text: GapLessL10n.t('triage_pain_mild'),
            value: 'mild',
            icon: Icons.check_circle,
          ),
          TriageOption(
            text: GapLessL10n.t('triage_pain_moderate'),
            value: 'moderate',
            icon: Icons.warning,
          ),
          TriageOption(
            text: GapLessL10n.t('triage_pain_severe'),
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
        return GapLessL10n.t('triage_critical_title');
      case TriageSeverity.urgent:
        return GapLessL10n.t('triage_urgent_title');
      case TriageSeverity.moderate:
        return GapLessL10n.t('triage_moderate_title');
      case TriageSeverity.minor:
        return GapLessL10n.t('triage_minor_title');
    }
  }

  String getDescription(String lang) {
    switch (this) {
      case TriageSeverity.critical:
        return GapLessL10n.t('triage_critical_desc');
      case TriageSeverity.urgent:
        return GapLessL10n.t('triage_urgent_desc');
      case TriageSeverity.moderate:
        return GapLessL10n.t('triage_moderate_desc');
      case TriageSeverity.minor:
        return GapLessL10n.t('triage_minor_desc');
    }
  }

  String getRecommendation(String lang) {
    switch (this) {
      case TriageSeverity.critical:
        return GapLessL10n.t('triage_critical_rec');
      case TriageSeverity.urgent:
        return GapLessL10n.t('triage_urgent_rec');
      case TriageSeverity.moderate:
        return GapLessL10n.t('triage_moderate_rec');
      case TriageSeverity.minor:
        return GapLessL10n.t('triage_minor_rec');
    }
  }
}
