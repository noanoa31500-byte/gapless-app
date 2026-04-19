import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/localization.dart';
import '../providers/language_provider.dart';
import '../utils/styles.dart';
import '../widgets/safe_text.dart';

/// チュートリアル画面
/// 初回起動時にアプリの使い方を説明
class TutorialScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const TutorialScreen({super.key, required this.onComplete});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();

  /// チュートリアルが完了済みかチェック
  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('tutorial_completed') ?? false;
  }

  /// チュートリアルを完了としてマーク
  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tutorial_completed', true);
  }
}

class _TutorialScreenState extends State<TutorialScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // 言語変更時に再描画
    final pages = _getTutorialPages();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Skip Button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _completeTutorial,
                  child: SafeText(
                    GapLessL10n.t('tutorial_skip'),
                    style: emergencyTextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ),

            // Page Content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: pages.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  return _buildPage(pages[index]);
                },
              ),
            ),

            // Indicators & Navigation
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Page Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      pages.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? const Color(0xFFE53935)
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Navigation Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back Button
                      _currentPage > 0
                          ? TextButton.icon(
                              onPressed: () {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              },
                              icon: const Icon(Icons.arrow_back),
                              label: SafeText(GapLessL10n.t('tutorial_back')),
                            )
                          : const SizedBox(width: 100),

                      // Next/Start Button
                      ElevatedButton(
                        onPressed: () {
                          if (_currentPage < pages.length - 1) {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          } else {
                            _completeTutorial();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: SafeText(
                          _currentPage < pages.length - 1
                              ? GapLessL10n.t('tutorial_next')
                              : GapLessL10n.t('tutorial_start'),
                          style: emergencyTextStyle(
                              color: Colors.white, isBold: true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(TutorialPage page) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: page.color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              page.icon,
              size: 64,
              color: page.color,
            ),
          ),
          const SizedBox(height: 40),

          // Title
          SafeText(
            page.title,
            style: emergencyTextStyle(size: 28, isBold: true),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Description
          SafeText(
            page.description,
            style: emergencyTextStyle(size: 16, color: Colors.grey[700]!),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _completeTutorial() async {
    await TutorialScreen.markCompleted();
    widget.onComplete();
  }

  List<TutorialPage> _getTutorialPages() {
    return [
      TutorialPage(
        icon: Icons.shield,
        color: const Color(0xFFE53935),
        title: GapLessL10n.t('tutorial_welcome_title'),
        description: GapLessL10n.t('tutorial_welcome_desc'),
      ),
      TutorialPage(
        icon: Icons.navigation,
        color: Colors.blue,
        title: GapLessL10n.t('tutorial_compass_title'),
        description: GapLessL10n.t('tutorial_compass_desc'),
      ),
      TutorialPage(
        icon: Icons.record_voice_over,
        color: Colors.green,
        title: GapLessL10n.t('tutorial_voice_title'),
        description: GapLessL10n.t('tutorial_voice_desc'),
      ),
      TutorialPage(
        icon: Icons.healing,
        color: Colors.orange,
        title: GapLessL10n.t('tutorial_first_aid_title'),
        description: GapLessL10n.t('tutorial_first_aid_desc'),
      ),
      TutorialPage(
        icon: Icons.contact_emergency,
        color: Colors.purple,
        title: GapLessL10n.t('tutorial_emergency_gear_title'),
        description: GapLessL10n.t('tutorial_emergency_gear_desc'),
      ),
      TutorialPage(
        icon: Icons.check_circle,
        color: const Color(0xFF43A047),
        title: GapLessL10n.t('tutorial_ready_title'),
        description: GapLessL10n.t('tutorial_ready_desc'),
      ),
    ];
  }
}

class TutorialPage {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const TutorialPage({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });
}
