import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/accessibility.dart';
import '../utils/localization.dart';
import '../utils/apple_design_system.dart';
import '../providers/location_provider.dart';
import '../providers/language_provider.dart';
import '../providers/shelter_provider.dart';
import '../providers/compass_provider.dart';
import 'package:latlong2/latlong.dart';

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
    if (AppleAccessibility.reduceMotion(context) && _animController.value < 1.0) {
      _animController.value = 1.0;
    }
    return Scaffold(
      backgroundColor: AppleColors.systemBackground,
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
  // Step 1: 言語選択 (Apple風)
  // ============================================
  Widget _buildLanguageSelection() {
    return Padding(
      key: const ValueKey('language'),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Icon with subtle gradient background
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppleColors.actionBlue.withValues(alpha: 0.15),
                  AppleColors.actionBlue.withValues(alpha: 0.05),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.language_rounded,
              size: 48,
              color: AppleColors.actionBlue,
            ),
          ),
          const SizedBox(height: 32),

          // Title
          Text(
            GapLessL10n.t('onb_select_language_title'),
            style: AppleTypography.largeTitle.copyWith(
              color: AppleColors.label,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '言語を選択 / Select / เลือก / 选择语言',
            style: AppleTypography.body.copyWith(
              color: AppleColors.secondaryLabel,
            ),
          ),

          const SizedBox(height: 24),

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

          // Next Button (Apple風)
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
          
          const SizedBox(height: 48),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppleColors.actionBlue.withValues(alpha: 0.1) 
              : AppleColors.secondaryBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppleColors.actionBlue : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                name,
                style: AppleTypography.headline.copyWith(
                  color: isSelected ? AppleColors.actionBlue : AppleColors.label,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: AppleColors.actionBlue, size: 24),
          ],
        ),
      ),
    );
  }

  // ============================================
  // Step 2: 位置情報許可 (Apple風)
  // ============================================
  Widget _buildLocationPermission() {
    final lang = _selectedLanguage;
    
    return Padding(
      key: const ValueKey('location'),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 2),
          
          // Icon
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppleColors.safetyGreen.withValues(alpha: 0.15),
                  AppleColors.safetyGreen.withValues(alpha: 0.05),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on_rounded,
              size: 48,
              color: AppleColors.safetyGreen,
            ),
          ),
          const SizedBox(height: 32),

          Text(
            _getLocationTitle(lang),
            style: AppleTypography.largeTitle.copyWith(
              color: AppleColors.label,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            _getLocationDescription(lang),
            style: AppleTypography.body.copyWith(
              color: AppleColors.secondaryLabel,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 48),

          // Permission Status
          if (_locationPermissionGranted)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppleColors.safetyGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppleColors.safetyGreen),
                  const SizedBox(width: 8),
                  Text(
                    _getPermissionGrantedText(lang),
                    style: AppleTypography.headline.copyWith(
                      color: AppleColors.safetyGreen,
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
              color: AppleColors.safetyGreen,
              onPressed: _requestLocationPermission,
            ),
            const SizedBox(height: 16),
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
                    style: AppleTypography.body.copyWith(
                      color: AppleColors.secondaryLabel,
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
        content: Text(message, style: AppleTypography.subhead.copyWith(color: Colors.white)),
        backgroundColor: AppleColors.secondaryLabel,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ============================================
  // Step 3: チュートリアル (Apple風)
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
  // Step 4: データローディング (Apple風)
  // ============================================
  Widget _buildDataLoading() {
    final lang = _selectedLanguage;
    
    if (!_isLoading) {
      _isLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadAllData();
      });
    }
    
    return Center(
      key: const ValueKey('loading'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // App Logo
          Container(
            width: 120,
            height: 120,
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
            child: const Icon(
              Icons.shield_rounded,
              size: 56,
              color: AppleColors.dangerRed,
            ),
          ),
          const SizedBox(height: 32),

          // GapLess Logo
          RichText(
            text: TextSpan(
              style: GapLessL10n.safeStyle(const TextStyle()),
              children: [
                TextSpan(
                  text: 'Gap',
                  style: AppleTypography.largeTitle.copyWith(
                    color: AppleColors.label,
                  ),
                ),
                TextSpan(
                  text: 'Less',
                  style: AppleTypography.largeTitle.copyWith(
                    color: AppleColors.dangerRed,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getLoadingSubtitle(lang),
            style: AppleTypography.subhead.copyWith(
              color: AppleColors.secondaryLabel,
            ),
          ),
          const SizedBox(height: 16),
          
          // Latest Version Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppleColors.safetyGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppleColors.safetyGreen.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.verified_rounded,
                  size: 14,
                  color: AppleColors.safetyGreen,
                ),
                const SizedBox(width: 4),
                Text(
                  'v4.5 [Latest]',
                  style: AppleTypography.caption1.copyWith(
                    color: AppleColors.safetyGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 64),

          // Progress (Apple風の円形プログレス)
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background circle
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppleColors.separator,
                    ),
                  ),
                ),
                // Progress circle
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: _loadingProgress,
                    strokeWidth: 4,
                    strokeCap: StrokeCap.round,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppleColors.actionBlue,
                    ),
                  ),
                ),
                // Percentage
                Text(
                  '${(_loadingProgress * 100).toInt()}%',
                  style: AppleTypography.headline.copyWith(
                    color: AppleColors.label,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          Text(
            _loadingMessage,
            style: AppleTypography.subhead.copyWith(
              color: AppleColors.secondaryLabel,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
      final loadRoadsFuture = shelterProvider.loadRoadData(); // This is the heaviest
      
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
          
          // バックグラウンド計算（キャッシュ）を並列ではなく直列で待機し、確実に完了させる
          await shelterProvider.updateBackgroundRoutes(locationProvider.currentLocation!);
          
          if (shelterProvider.navTarget != null) {
              await shelterProvider.calculateSafestRoute(
                  LatLng(locationProvider.currentLocation!.latitude, locationProvider.currentLocation!.longitude),
                  LatLng(shelterProvider.navTarget!.lat, shelterProvider.navTarget!.lng),
                  target: shelterProvider.navTarget
              );
          }
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
  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback onPressed,
    IconData? icon,
    Color? color,
  }) {
    return Container(
      width: double.infinity,
      height: 56, // Taller for better touch target
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (color ?? AppleColors.actionBlue).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? AppleColors.actionBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.zero, // Use Container height
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppleTypography.headline.copyWith(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                height: 1.2, // Explicit height to prevent Safari clipping
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // ローカライズヘルパー (GapLessL10n.t() ベース)
  // ============================================
  String _getNextText() => GapLessL10n.t('tutorial_start');
  String _getLocationTitle(String lang) => GapLessL10n.t('onb_location_title');
  String _getLocationDescription(String lang) => GapLessL10n.t('onb_location_desc');
  String _getAllowLocationText(String lang) => GapLessL10n.t('onb_allow_location');
  String _getPermissionGrantedText(String lang) => GapLessL10n.t('onb_perm_granted');
  String _getSkipText(String lang) => GapLessL10n.t('onb_set_later');
  String _getLoadingSubtitle(String lang) => GapLessL10n.t('onb_loading_subtitle');
  String _getLocationServiceDisabledText(String lang) => GapLessL10n.t('onb_loc_service_disabled');
  String _getLocationDeniedText(String lang) => GapLessL10n.t('onb_loc_denied');

  String _getLoadingMessage(String lang, String step) {
    switch (step) {
      case 'shelters': return GapLessL10n.t('onb_load_shelters');
      case 'hazard': return GapLessL10n.t('onb_load_hazard');
      case 'roads': return GapLessL10n.t('onb_load_roads');
      case 'locating': return GapLessL10n.t('onb_load_locating');
      case 'graph': return GapLessL10n.t('onb_load_graph');
      case 'complete': return GapLessL10n.t('onb_load_complete');
      default: return '';
    }
  }

  List<_TutorialPageData> _getTutorialPages(String lang) {
    return [
      _TutorialPageData(
        icon: Icons.shield_rounded,
        color: AppleColors.dangerRed,
        title: GapLessL10n.t('tutorial_welcome_title'),
        description: GapLessL10n.t('tutorial_welcome_desc'),
      ),
      _TutorialPageData(
        icon: Icons.navigation_rounded,
        color: AppleColors.actionBlue,
        title: GapLessL10n.t('tutorial_compass_title'),
        description: GapLessL10n.t('tutorial_compass_desc'),
      ),
      _TutorialPageData(
        icon: Icons.record_voice_over_rounded,
        color: AppleColors.safetyGreen,
        title: GapLessL10n.t('tutorial_voice_title'),
        description: GapLessL10n.t('tutorial_voice_desc'),
      ),
      _TutorialPageData(
        icon: Icons.healing_rounded,
        color: AppleColors.warningOrange,
        title: GapLessL10n.t('tutorial_first_aid_title'),
        description: GapLessL10n.t('tutorial_first_aid_desc'),
      ),
      _TutorialPageData(
        icon: Icons.check_circle_rounded,
        color: AppleColors.safetyGreen,
        title: GapLessL10n.t('tutorial_ready_title'),
        description: GapLessL10n.t('tutorial_ready_desc'),
      ),
    ];
  }
}

// ============================================================================
// Apple風チュートリアルページャー
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
        // Skip Button (Apple風)
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton(
              onPressed: widget.onSkip,
              child: Text(
                GapLessL10n.t('tutorial_skip'),
                style: AppleTypography.body.copyWith(
                  color: AppleColors.secondaryLabel,
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

        // Apple風ページインジケーター
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.pages.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _currentPage == index ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _currentPage == index
                      ? AppleColors.actionBlue
                      : AppleColors.separator,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 16),

        // Navigation Buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.arrow_back_ios_rounded, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          GapLessL10n.t('tutorial_back'),
                          style: AppleTypography.body.copyWith(
                            color: AppleColors.actionBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Spacer(),
              
              // Next/Start Button
              Expanded(
                flex: 2,
                child: Container(
                  height: 56, // Slightly taller for better touch target and premium feel
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppleColors.actionBlue.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      if (_currentPage < widget.pages.length - 1) {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        widget.onComplete();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppleColors.actionBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.zero, // Use Container height
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _currentPage < widget.pages.length - 1
                            ? GapLessL10n.t('tutorial_next')
                            : GapLessL10n.t('tutorial_start'),
                        style: AppleTypography.headline.copyWith(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          height: 1.2, // Explicit height for Safari
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
        
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildPage(_TutorialPageData page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with gradient background
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  page.color.withValues(alpha: 0.15),
                  page.color.withValues(alpha: 0.05),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(page.icon, size: 56, color: page.color),
          ),
          const SizedBox(height: 48),
          
          Text(
            page.title,
            style: AppleTypography.title1.copyWith(
              color: AppleColors.label,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          
          Text(
            page.description,
            style: AppleTypography.body.copyWith(
              color: AppleColors.secondaryLabel,
              height: 1.5,
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
