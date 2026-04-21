import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/accessibility.dart';
import '../utils/localization.dart';
// apple_design_system.dart removed — replaced by local design constants
import '../providers/location_provider.dart';
import '../providers/language_provider.dart';
import '../providers/shelter_provider.dart';
import '../providers/compass_provider.dart';

// Design system constants
const _kEmerald = Color(0xFF00C896);
const _kEmeraldDark = Color(0xFF00A87E);
const _kDark = Color(0xFF1A1A2E);
const _kDarkGreen = Color(0xFF0D3B2E);
const _kSurface = Color(0xFFF8F9FE);
const _kAmber = Color(0xFFFF6B35);

/// ============================================================================
/// OnboardingScreen - Apple HIG準拠のオンボーディング体験
/// ============================================================================
///
/// デザインコンセプト: "First Impression Matters"
/// 初回起動時の体験がアプリの印象を決定づける
/// Apple風のミニマルで洗練されたデザインを採用
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// オンボーディングが完了済みかチェック
  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_completed') ?? false;
  }

  /// オンボーディングを完了としてマーク
  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  String _selectedLanguage = 'ja';
  bool _locationPermissionGranted = false;
  bool _isLoading = false;
  double _loadingProgress = 0.0;
  String _loadingMessage = '';

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _goToNextStep() {
    _animController.reverse().then((_) {
      setState(() {
        _currentStep++;
      });
      _animController.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // 言語変更時に再描画
    if (AppleAccessibility.reduceMotion(context) &&
        _animController.value < 1.0) {
      _animController.value = 1.0;
    }
    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: _buildCurrentStep(),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildLanguageSelection();
      case 1:
        return _buildLocationPermission();
      case 2:
        return _buildTutorial();
      case 3:
        return _buildDataLoading();
      default:
        return const SizedBox();
    }
  }

  // ============================================
  // Step 1: 言語選択 (Modernized)
  // ============================================
  Widget _buildLanguageSelection() {
    return Padding(
      key: const ValueKey('language'),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 24),

          // Step progress pill
          _buildStepPills(0),
          const SizedBox(height: 28),

          // Icon with emerald gradient background
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_kEmerald, _kEmeraldDark],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _kEmerald.withOpacity(0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.language_rounded,
              size: 44,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 28),

          // Title
          Text(
            GapLessL10n.t('onb_select_language_title'),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: _kDark,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '言語を選択 / Select / เลือก / 选择语言',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: _kDark.withOpacity(0.5),
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),

          // Language Options (all 18 languages, scrollable)
          Expanded(
            child: ListView(
              children: GapLessL10n.availableLanguages.map((code) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildLanguageOption(
                    flag: GapLessL10n.flagForLanguage(code),
                    name: GapLessL10n.nameForLanguage(code),
                    code: code,
                  ),
                );
              }).toList(),
            ),
          ),

          // Next Button (gradient pill)
          _buildPrimaryButton(
            label: _getNextText(),
            onPressed: () async {
              await GapLessL10n.setLanguage(_selectedLanguage);
              if (mounted) {
                context.read<LanguageProvider>().setLanguage(_selectedLanguage);
                _goToNextStep();
              }
            },
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildLanguageOption({
    required String flag,
    required String name,
    required String code,
  }) {
    final isSelected = _selectedLanguage == code;

    return GestureDetector(
      onTap: () => setState(() => _selectedLanguage = code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? _kEmerald.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _kEmerald : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isSelected ? 0.05 : 0.04),
              blurRadius: isSelected ? 16 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? _kEmerald : _kDark,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: _kEmerald,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 14),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // Step 2: 位置情報許可 (Modernized)
  // ============================================
  Widget _buildLocationPermission() {
    final lang = _selectedLanguage;

    return Padding(
      key: const ValueKey('location'),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 24),
          _buildStepPills(1),
          const Spacer(flex: 2),

          // Icon with gradient
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_kEmerald, _kEmeraldDark],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _kEmerald.withOpacity(0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.location_on_rounded,
              size: 44,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 28),

          Text(
            _getLocationTitle(lang),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: _kDark,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            _getLocationDescription(lang),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: _kDark.withOpacity(0.55),
              height: 1.5,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 40),

          // Permission Status
          if (_locationPermissionGranted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: _kEmerald.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kEmerald.withOpacity(0.3), width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: _kEmerald, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    _getPermissionGrantedText(lang),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _kEmerald,
                    ),
                  ),
                ],
              ),
            ),

          const Spacer(flex: 2),

          // Request Permission Button
          if (!_locationPermissionGranted) ...[
            _buildPrimaryButton(
              label: _getAllowLocationText(lang),
              icon: Icons.location_searching_rounded,
              onPressed: _requestLocationPermission,
            ),
            const SizedBox(height: 14),
          ],

          // Skip / Next Button
          _locationPermissionGranted
              ? _buildPrimaryButton(
                  label: _getNextText(),
                  onPressed: _goToNextStep,
                )
              : TextButton(
                  onPressed: _goToNextStep,
                  child: Text(
                    _getSkipText(lang),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: _kDark.withOpacity(0.45),
                    ),
                  ),
                ),

          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Future<void> _requestLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showSnackBar(_getLocationServiceDisabledText(_selectedLanguage));
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          _showSnackBar(_getLocationDeniedText(_selectedLanguage));
        }
        return;
      }

      setState(() => _locationPermissionGranted = true);

      if (mounted) {
        await context.read<LocationProvider>().initLocation();
      }
    } catch (e) {
      debugPrint('Location permission error: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        backgroundColor: _kDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ============================================
  // Step 3: チュートリアル (Modernized)
  // ============================================
  Widget _buildTutorial() {
    final lang = _selectedLanguage;
    final pages = _getTutorialPages(lang);

    return _AppleTutorialPager(
      key: const ValueKey('tutorial'),
      pages: pages,
      lang: lang,
      onComplete: _goToNextStep,
      onSkip: _goToNextStep,
    );
  }

  // ============================================
  // Step 4: データローディング (Modernized)
  // ============================================
  Widget _buildDataLoading() {
    final lang = _selectedLanguage;

    if (!_isLoading) {
      _isLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadAllData();
      });
    }

    return Container(
      key: const ValueKey('loading'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kDark, _kDarkGreen],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App Logo with glow
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_kEmerald, _kEmeraldDark],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _kEmerald.withOpacity(0.45),
                      blurRadius: 36,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  size: 56,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),

              // GapLess Logo
              RichText(
                text: TextSpan(
                  style: GapLessL10n.safeStyle(const TextStyle()),
                  children: [
                    const TextSpan(
                      text: 'Gap',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    TextSpan(
                      text: 'Less',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: _kEmerald,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _getLoadingSubtitle(lang),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.6),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 16),

              // Latest Version Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _kEmerald.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _kEmerald.withOpacity(0.4),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      size: 14,
                      color: _kEmerald,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'v4.5 [Latest]',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _kEmerald,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 60),

              // Progress (circular with emerald)
              SizedBox(
                width: 88,
                height: 88,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background circle
                    SizedBox(
                      width: 88,
                      height: 88,
                      child: CircularProgressIndicator(
                        value: 1.0,
                        strokeWidth: 5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withOpacity(0.12),
                        ),
                      ),
                    ),
                    // Progress circle
                    SizedBox(
                      width: 88,
                      height: 88,
                      child: CircularProgressIndicator(
                        value: _loadingProgress,
                        strokeWidth: 5,
                        strokeCap: StrokeCap.round,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(_kEmerald),
                      ),
                    ),
                    // Percentage
                    Text(
                      '${(_loadingProgress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Text(
                _loadingMessage,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.65),
                  letterSpacing: 0.2,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadAllData() async {
    final lang = _selectedLanguage;
    final shelterProvider = context.read<ShelterProvider>();
    final locationProvider = context.read<LocationProvider>();
    final compassProvider = context.read<CompassProvider>();

    try {
      setState(() {
        _loadingMessage = _getLoadingMessage(lang, 'shelters');
        _loadingProgress = 0.1;
      });

      // 1. Start Heavy Loading Tasks in Parallel
      // Shelters, Hazard Polygons, Road Data
      final loadSheltersFuture = shelterProvider.loadShelters();
      final loadHazardsFuture = shelterProvider.loadHazardPolygons();
      final loadRoadsFuture =
          shelterProvider.loadRoadData(); // This is the heaviest

      // Simulate progress updates or just wait for all
      // We can await them individually if we want to update the progress bar incrementally,
      // but Future.wait is faster. Let's do a hybrid approach.

      await loadSheltersFuture;
      if (!mounted) return;
      setState(() {
        _loadingMessage = _getLoadingMessage(lang, 'hazard');
        _loadingProgress = 0.3;
      });

      await loadHazardsFuture;
      if (!mounted) return;
      setState(() {
        _loadingMessage = _getLoadingMessage(lang, 'roads');
        _loadingProgress = 0.5;
      });

      await loadRoadsFuture;
      if (!mounted) return;

      // 2. Start GPS wait (Robust 10s window)
      setState(() {
        _loadingMessage = _getLoadingMessage(lang, 'locating');
        _loadingProgress = 0.7;
      });

      // 最大10秒待機
      await locationProvider.waitForFreshGPS(timeoutSeconds: 10);
      if (!mounted) return;

      // コンパスリスナー開始
      await compassProvider.startListening();
      if (!mounted) return;

      // 3. Pre-calculate Routes (Ensure EVERYTHING is done)
      if (locationProvider.currentLocation != null) {
        setState(() {
          _loadingMessage = _getLoadingMessage(lang, 'graph');
          _loadingProgress = 0.9;
        });
      }

      if (!mounted) return;
      setState(() {
        _loadingMessage = _getLoadingMessage(lang, 'complete');
        _loadingProgress = 1.0;
      });
      await Future.delayed(const Duration(milliseconds: 500));

      await OnboardingScreen.markCompleted();

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      debugPrint('Data loading error: $e');
      await OnboardingScreen.markCompleted();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    }
  }

  // ============================================
  // 共通ウィジェット
  // ============================================

  /// Step progress pills (4 steps: 0-3)
  Widget _buildStepPills(int activeStep) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final isActive = i == activeStep;
        final isDone = i < activeStep;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? _kEmerald
                : isDone
                    ? _kEmerald.withOpacity(0.4)
                    : _kDark.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback onPressed,
    IconData? icon,
    Color? color,
  }) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: color != null
              ? [color, color.withOpacity(0.8)]
              : [_kEmerald, _kEmeraldDark],
        ),
        boxShadow: [
          BoxShadow(
            color: (color ?? _kEmerald).withOpacity(0.38),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
              if (icon != null) ...[
                Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: 10),
              ],
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // ローカライズヘルパー (GapLessL10n.t() ベース)
  // ============================================
  String _getNextText() => GapLessL10n.t('tutorial_start');
  String _getLocationTitle(String lang) => GapLessL10n.t('onb_location_title');
  String _getLocationDescription(String lang) =>
      GapLessL10n.t('onb_location_desc');
  String _getAllowLocationText(String lang) =>
      GapLessL10n.t('onb_allow_location');
  String _getPermissionGrantedText(String lang) =>
      GapLessL10n.t('onb_perm_granted');
  String _getSkipText(String lang) => GapLessL10n.t('onb_set_later');
  String _getLoadingSubtitle(String lang) =>
      GapLessL10n.t('onb_loading_subtitle');
  String _getLocationServiceDisabledText(String lang) =>
      GapLessL10n.t('onb_loc_service_disabled');
  String _getLocationDeniedText(String lang) => GapLessL10n.t('onb_loc_denied');

  String _getLoadingMessage(String lang, String step) {
    switch (step) {
      case 'shelters':
        return GapLessL10n.t('onb_load_shelters');
      case 'hazard':
        return GapLessL10n.t('onb_load_hazard');
      case 'roads':
        return GapLessL10n.t('onb_load_roads');
      case 'locating':
        return GapLessL10n.t('onb_load_locating');
      case 'graph':
        return GapLessL10n.t('onb_load_graph');
      case 'complete':
        return GapLessL10n.t('onb_load_complete');
      default:
        return '';
    }
  }

  List<_TutorialPageData> _getTutorialPages(String lang) {
    return [
      _TutorialPageData(
        icon: Icons.shield_rounded,
        color: const Color(0xFFFF6B35),
        title: GapLessL10n.t('tutorial_welcome_title'),
        description: GapLessL10n.t('tutorial_welcome_desc'),
      ),
      _TutorialPageData(
        icon: Icons.navigation_rounded,
        color: _kEmerald,
        title: GapLessL10n.t('tutorial_compass_title'),
        description: GapLessL10n.t('tutorial_compass_desc'),
      ),
      _TutorialPageData(
        icon: Icons.record_voice_over_rounded,
        color: const Color(0xFF5B9CF6),
        title: GapLessL10n.t('tutorial_voice_title'),
        description: GapLessL10n.t('tutorial_voice_desc'),
      ),
      _TutorialPageData(
        icon: Icons.healing_rounded,
        color: _kAmber,
        title: GapLessL10n.t('tutorial_first_aid_title'),
        description: GapLessL10n.t('tutorial_first_aid_desc'),
      ),
      _TutorialPageData(
        icon: Icons.check_circle_rounded,
        color: _kEmerald,
        title: GapLessL10n.t('tutorial_ready_title'),
        description: GapLessL10n.t('tutorial_ready_desc'),
      ),
    ];
  }
}

// ============================================================================
// Modern Tutorial Pager
// ============================================================================
class _AppleTutorialPager extends StatefulWidget {
  final List<_TutorialPageData> pages;
  final String lang;
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  const _AppleTutorialPager({
    super.key,
    required this.pages,
    required this.lang,
    required this.onComplete,
    required this.onSkip,
  });

  @override
  State<_AppleTutorialPager> createState() => _AppleTutorialPagerState();
}

class _AppleTutorialPagerState extends State<_AppleTutorialPager> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Skip Button
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextButton(
              onPressed: widget.onSkip,
              style: TextButton.styleFrom(
                foregroundColor: _kDark.withOpacity(0.45),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Text(
                GapLessL10n.t('tutorial_skip'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),

        // Pages
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.pages.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              final page = widget.pages[index];
              return _buildPage(page);
            },
          ),
        ),

        // Pill page indicators (emerald)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.pages.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _currentPage == index ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _currentPage == index
                      ? _kEmerald
                      : _kDark.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Navigation Buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            children: [
              // Back Button
              if (_currentPage > 0)
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      _controller.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: _kEmerald,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.arrow_back_ios_rounded, size: 15),
                        const SizedBox(width: 4),
                        Text(
                          GapLessL10n.t('tutorial_back'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Spacer(),

              // Next/Start Button — gradient pill
              Expanded(
                flex: 2,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      colors: [_kEmerald, _kEmeraldDark],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _kEmerald.withOpacity(0.38),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () {
                        if (_currentPage < widget.pages.length - 1) {
                          _controller.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          widget.onComplete();
                        }
                      },
                      child: Center(
                        child: Text(
                          _currentPage < widget.pages.length - 1
                              ? GapLessL10n.t('tutorial_next')
                              : GapLessL10n.t('tutorial_start'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              if (_currentPage > 0) const Spacer() else const SizedBox(),
            ],
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPage(_TutorialPageData page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with gradient circle
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  page.color.withOpacity(0.18),
                  page.color.withOpacity(0.06),
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: page.color.withOpacity(0.25),
                width: 1.5,
              ),
            ),
            child: Icon(page.icon, size: 52, color: page.color),
          ),
          const SizedBox(height: 28),

          Text(
            page.title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: _kDark,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),

          Text(
            page.description,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: _kDark.withOpacity(0.55),
              height: 1.6,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TutorialPageData {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _TutorialPageData({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });
}
