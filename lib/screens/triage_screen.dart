import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/shelter_provider.dart';
import '../providers/location_provider.dart';
import '../providers/language_provider.dart';
import '../theme/app_colors.dart';
import '../utils/localization.dart';
import '../widgets/safe_text.dart';
import 'package:latlong2/latlong.dart';

// Design system constants
const _kEmerald     = Color(0xFF00C896);
const _kEmeraldDark = Color(0xFF00A87E);
const _kDark        = Color(0xFF1A1A2E);
const _kDarkGreen   = Color(0xFF0D3B2E);
const _kSurface     = Color(0xFFF8F9FE);
const _kCritical    = Color(0xFFE53935);
const _kUrgent      = Color(0xFFFF6B35);
const _kModerate    = Color(0xFFFFB300);

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
  // isUrgent (呼吸停止 / 大出血) を選択した瞬間に true。
  // 戻るボタンを封じ、判定リセットによる二度押し事故を防ぐ。
  bool _criticalLocked = false;

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // 言語変更時に再描画
    final lang = GapLessL10n.lang;

    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _kDark,
        foregroundColor: Colors.white,
        title: SafeText(
          _getTitle(lang),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                onPressed: () => Navigator.maybePop(context),
              )
            : null,
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
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(_kEmerald),
          strokeWidth: 3,
        ),
      );
    }

    final question = questions[_currentStep];

    return SafeArea(
      child: Column(
        children: [
          // Dark header band with question icon + progress
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_kDark, _kDarkGreen],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Progress pill bar
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (_currentStep + 1) / questions.length,
                          backgroundColor: Colors.white.withOpacity(0.15),
                          valueColor: const AlwaysStoppedAnimation<Color>(_kEmerald),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_currentStep + 1} / ${questions.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Question icon badge
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: question.color.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: question.color.withOpacity(0.35),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(question.icon, size: 36, color: question.color),
                ),
                const SizedBox(height: 16),

                // Question Text
                SafeText(
                  question.text,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
                    height: 1.3,
                  ),
                ),
                if (question.subtext != null) ...[
                  const SizedBox(height: 6),
                  SafeText(
                    question.subtext!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.6),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Answer Options
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
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

          // Back Button — Critical 判定後は戻れない (誤操作リセット防止)
          if (_currentStep > 0 && !_criticalLocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: TextButton.icon(
                onPressed: () => setState(() => _currentStep--),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: _kEmerald),
                label: SafeText(
                  _getBackLabel(lang),
                  style: const TextStyle(
                    color: _kEmerald,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOptionButton(TriageOption option, TriageQuestion question) {
    // Determine styling by urgency
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final Color iconColor;

    if (option.isUrgent) {
      bgColor = _kCritical.withOpacity(0.06);
      borderColor = _kCritical.withOpacity(0.5);
      textColor = _kCritical;
      iconColor = _kCritical;
    } else {
      bgColor = Colors.white;
      borderColor = _kDark.withOpacity(0.1);
      textColor = _kDark;
      iconColor = _kEmerald;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          setState(() {
            _answers[question.id] = option.value;
            _currentStep++;
            if (option.isUrgent) _criticalLocked = true;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(option.isUrgent ? 0.06 : 0.04),
                blurRadius: option.isUrgent ? 16 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              if (option.icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(option.icon, size: 22, color: iconColor),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: SafeText(
                  option.text,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: option.isUrgent ? _kCritical.withOpacity(0.5) : _kDark.withOpacity(0.25),
              ),
            ],
          ),
        ),
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
    final sev = result.severity;

    // Severity gradient colors
    final List<Color> sevGradient;
    switch (sev) {
      case TriageSeverity.critical:
        sevGradient = [_kCritical, const Color(0xFFB71C1C)];
        break;
      case TriageSeverity.urgent:
        sevGradient = [_kUrgent, const Color(0xFFE64A19)];
        break;
      case TriageSeverity.moderate:
        sevGradient = [_kModerate, const Color(0xFFF57F17)];
        break;
      case TriageSeverity.minor:
        sevGradient = [_kEmerald, _kEmeraldDark];
        break;
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Hero result band
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: sevGradient,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 36),
              child: Column(
                children: [
                  // Severity icon with glow
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(sev.icon, size: 52, color: Colors.white),
                  ),
                  const SizedBox(height: 20),

                  // Severity pill badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      sev.getBadgeLabel(lang),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SafeText(
                    sev.getTitle(lang),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  SafeText(
                    sev.getDescription(lang),
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.8),
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // Content area
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Recommendation card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sev.color.withOpacity(0.25),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.07),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: sev.color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.lightbulb_rounded, color: sev.color, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _getRecommendationTitle(lang),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _kDark.withOpacity(0.45),
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SafeText(
                          sev.getRecommendation(lang),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: _kDark,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action Buttons
                  if (result.needsMedical) ...[
                    _buildActionButton(
                      label: _getGoToHospitalLabel(lang),
                      icon: Icons.local_hospital_rounded,
                      gradient: const LinearGradient(
                        colors: [_kCritical, Color(0xFFB71C1C)],
                      ),
                      onPressed: _navigateToHospital,
                    ),
                    const SizedBox(height: 12),
                  ],

                  _buildActionButton(
                    label: _getGoToShelterLabel(lang),
                    icon: Icons.night_shelter_rounded,
                    gradient: result.needsMedical
                        ? const LinearGradient(colors: [Color(0xFFEEEEEE), Color(0xFFE0E0E0)])
                        : const LinearGradient(colors: [_kEmerald, _kEmeraldDark]),
                    textColor: result.needsMedical ? _kDark : Colors.white,
                    onPressed: _navigateToShelter,
                  ),
                  const SizedBox(height: 24),

                  // Restart
                  Center(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _currentStep = 0;
                          _answers.clear();
                          _result = null;
                          _criticalLocked = false;
                        });
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: _kDark.withOpacity(0.45),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.refresh_rounded, size: 16),
                          const SizedBox(width: 6),
                          SafeText(
                            _getRestartLabel(lang),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Gradient gradient,
    Color textColor = Colors.white,
    required VoidCallback onPressed,
  }) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: textColor),
              const SizedBox(width: 10),
              SafeText(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
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
        color: const Color(0xFF5B9CF6),
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
        color: _kCritical,
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
        color: const Color(0xFF9C6FE4),
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
        color: _kUrgent,
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
        color: _kModerate,
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
    // Apple HIG semantic colors。国際 START 法と完全一致ではないが
    // (START は黒/赤/黄/緑) 一般ユーザ向けに重症度が直感的に伝わる順序を保つ。
    switch (this) {
      case TriageSeverity.critical:
        return AppColors.emergencyRed;
      case TriageSeverity.urgent:
        return AppColors.warningOrange;
      case TriageSeverity.moderate:
        return AppColors.warningOrange;
      case TriageSeverity.minor:
        return AppColors.primaryGreen;
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

  /// Short pill label (ALL CAPS style)
  String getBadgeLabel(String lang) {
    switch (this) {
      case TriageSeverity.critical:
        return 'CRITICAL';
      case TriageSeverity.urgent:
        return 'URGENT';
      case TriageSeverity.moderate:
        return 'MODERATE';
      case TriageSeverity.minor:
        return 'MINOR';
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
