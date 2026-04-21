import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/accessibility.dart';
import '../utils/localization.dart';
import '../utils/apple_design_system.dart';
import '../widgets/survival_guide_modal.dart';
import '../providers/shelter_provider.dart';
import '../providers/user_profile_provider.dart';
import '../providers/language_provider.dart';
import '../constants/survival_data.dart';
import 'chat_screen.dart';
import 'emergency_card_screen.dart';

/// ============================================================================
/// ShelterDashboardScreen - Apple HIG準拠の避難所ダッシュボード
/// ============================================================================
///
/// デザインコンセプト: "Safe & Calm"
/// 避難完了後の安心感を視覚的に伝える緑基調のApple風デザイン
class ShelterDashboardScreen extends StatefulWidget {
  const ShelterDashboardScreen({super.key});

  @override
  State<ShelterDashboardScreen> createState() => _ShelterDashboardScreenState();
}

class _ShelterDashboardScreenState extends State<ShelterDashboardScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // 安全インジケーターのパルスアニメーション
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // 言語変更時に再描画
    final reduce = AppleAccessibility.reduceMotion(context);
    if (reduce && _pulseController.isAnimating) {
      _pulseController.stop();
    } else if (!reduce && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
    return Scaffold(
      backgroundColor: AppleColors.systemBackground,
      body: CustomScrollView(
        slivers: [
          // Apple風カスタムAppBar
          _buildSliverAppBar(context),

          // コンテンツ
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 1. Safety Status Card (メイン)
                _buildSafetyStatusCard(),
                const SizedBox(height: 24),

                // 2. Quick Actions
                _buildQuickActions(context),
                const SizedBox(height: 32),

                // 3. Emergency ID Card
                _buildSectionHeader(Icons.badge_rounded,
                    GapLessL10n.t('header_emergency_gear')),
                const SizedBox(height: 12),
                _buildEmergencyIdCard(context),
                const SizedBox(height: 32),

                // 4. Survival Guide Grid
                _buildSectionHeader(Icons.menu_book_rounded,
                    GapLessL10n.t('header_survival_guide')),
                const SizedBox(height: 12),
                _buildSurvivalGrid(context),
              ]),
            ),
          ),
        ],
      ),

      // AI Chat FAB (グラスモーフィズム)
      floatingActionButton: _buildGlassFab(context),
    );
  }

  // ============================================
  // Apple風 Sliver AppBar
  // ============================================
  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      backgroundColor: AppleColors.safetyGreen,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () {
          context.read<ShelterProvider>().setSafeInShelter(false);
          // 元の画面(NavigationScreen)に戻る
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            Navigator.of(context).pushReplacementNamed('/compass');
          }
        },
      ),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: Text(
          GapLessL10n.t('header_shelter_support'),
          style: AppleTypography.headline.copyWith(
            color: Colors.white,
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppleColors.safetyGreen,
                AppleColors.safetyGreen.withValues(alpha: 0.8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================
  // Safety Status Card (メインバナー)
  // ============================================
  Widget _buildSafetyStatusCard() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppleColors.safetyGreen.withValues(alpha: 0.15),
                  AppleColors.safetyGreen.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppleColors.safetyGreen.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                // Checkmark Icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppleColors.safetyGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppleColors.safetyGreen.withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 20),

                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        GapLessL10n.t('header_safe_banner_title'),
                        style: AppleTypography.title2.copyWith(
                          color: AppleColors.safetyGreen,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        GapLessL10n.t('header_safe_banner_desc'),
                        style: AppleTypography.subhead.copyWith(
                          color: AppleColors.safetyGreen.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================
  // Quick Actions (横スクロールボタン)
  // ============================================
  Widget _buildQuickActions(BuildContext context) {
    return SizedBox(
      height: 80,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Show to Staff (緊急)
          _buildQuickActionButton(
            icon: Icons.medical_information_rounded,
            label: GapLessL10n.t('btn_show_staff'),
            color: AppleColors.dangerRed,
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => Container(
                  height: MediaQuery.of(context).size.height * 0.9,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: const EmergencyCardScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 12),

          // Talk to AI
          _buildQuickActionButton(
            icon: Icons.smart_toy_rounded,
            label: GapLessL10n.t('btn_talk_ai'),
            color: AppleColors.actionBlue,
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => Container(
                  height: MediaQuery.of(context).size.height * 0.9,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: const ChatScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppleTypography.headline.copyWith(
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // Section Header
  // ============================================
  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: AppleColors.secondaryLabel, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppleTypography.headline.copyWith(
            color: AppleColors.label,
          ),
        ),
      ],
    );
  }

  // ============================================
  // Emergency ID Card (Apple風)
  // ============================================
  Widget _buildEmergencyIdCard(BuildContext context) {
    final profile = context.watch<UserProfileProvider>().profile;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppleColors.secondaryBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppleColors.separator,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppleColors.actionBlue.withValues(alpha: 0.3),
                  AppleColors.actionBlue.withValues(alpha: 0.1),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              size: 32,
              color: AppleColors.actionBlue,
            ),
          ),
          const SizedBox(width: 16),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name.isNotEmpty
                      ? profile.name
                      : GapLessL10n.t('label_unknown'),
                  style: AppleTypography.title3.copyWith(
                    color: AppleColors.label,
                  ),
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  '${GapLessL10n.t('label_blood')}:',
                  profile.bloodType.isNotEmpty ? profile.bloodType : '-',
                  AppleColors.dangerRed,
                ),
                const SizedBox(height: 4),
                _buildInfoRow(
                  '${GapLessL10n.t('label_allergies')}:',
                  profile.allergies.isNotEmpty
                      ? profile.allergies.join(', ')
                      : GapLessL10n.t('label_unknown'),
                  AppleColors.warningOrange,
                ),
              ],
            ),
          ),

          // Arrow
          Icon(
            Icons.chevron_right_rounded,
            color: AppleColors.tertiaryLabel,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color accentColor) {
    return Row(
      children: [
        Text(
          label,
          style: AppleTypography.caption1.copyWith(
            color: AppleColors.secondaryLabel,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: AppleTypography.caption1.copyWith(
            color: accentColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ============================================
  // Survival Guide Grid (Apple風)
  // ============================================
  Widget _buildSurvivalGrid(BuildContext context) {
    final region = context.watch<ShelterProvider>().currentRegion;
    final guides = SurvivalData.getOfficialGuides(region);
    final lang = context.read<LanguageProvider>().currentLanguage;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.0,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: guides.length,
      itemBuilder: (context, index) {
        final item = guides[index];
        final title = item.title[lang] ?? item.title['en']!;

        return GestureDetector(
          onTap: () => SurvivalGuideModal.show(context, item, lang),
          child: Container(
            decoration: BoxDecoration(
              color: AppleColors.secondaryBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppleColors.separator,
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon with gradient background
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppleColors.dangerRed.withValues(alpha: 0.15),
                        AppleColors.dangerRed.withValues(alpha: 0.05),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    item.icon,
                    size: 28,
                    color: AppleColors.dangerRed,
                  ),
                ),
                const SizedBox(height: 12),

                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppleTypography.subhead.copyWith(
                      color: AppleColors.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================
  // Glass FAB
  // ============================================
  Widget _buildGlassFab(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => Container(
            height: MediaQuery.of(context).size.height * 0.9,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: const ChatScreen(),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppleColors.actionBlue.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppleColors.actionBlue.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.smart_toy_rounded,
                    color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Text(
                  GapLessL10n.t('btn_talk_ai'),
                  style: AppleTypography.headline.copyWith(
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
