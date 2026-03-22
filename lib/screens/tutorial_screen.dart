import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/localization.dart';
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
    final lang = GapLessL10n.lang;
    final pages = _getTutorialPages(lang);

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
                    _getSkipLabel(lang),
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
                              label: SafeText(_getBackLabel(lang)),
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
                              ? _getNextLabel(lang)
                              : _getStartLabel(lang),
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

  String _getSkipLabel(String lang) {
    switch (lang) {
      case 'ja':
        return 'スキップ';
      case 'th':
        return 'ข้าม';
      default:
        return 'Skip';
    }
  }

  String _getBackLabel(String lang) {
    switch (lang) {
      case 'ja':
        return '戻る';
      case 'th':
        return 'กลับ';
      default:
        return 'Back';
    }
  }

  String _getNextLabel(String lang) {
    switch (lang) {
      case 'ja':
        return '次へ';
      case 'th':
        return 'ถัดไป';
      default:
        return 'Next';
    }
  }

  String _getStartLabel(String lang) {
    switch (lang) {
      case 'ja':
        return 'はじめる';
      case 'th':
        return 'เริ่มต้น';
      default:
        return 'Get Started';
    }
  }

  List<TutorialPage> _getTutorialPages(String lang) {
    return [
      // Page 1: Welcome
      TutorialPage(
        icon: Icons.shield,
        color: const Color(0xFFE53935),
        title: lang == 'ja'
            ? 'GapLessへようこそ'
            : (lang == 'th' ? 'ยินดีต้อนรับสู่ GapLess' : 'Welcome to GapLess'),
        description: lang == 'ja'
            ? '災害時にあなたを安全な場所へ導く、オフライン対応の防災ナビゲーションアプリです。'
            : (lang == 'th'
                ? 'แอปนำทางป้องกันภัยพิบัติแบบออฟไลน์ที่จะนำทางคุณไปยังที่ปลอดภัย'
                : 'An offline disaster navigation app that guides you to safety.'),
      ),

      // Page 2: Compass
      TutorialPage(
        icon: Icons.navigation,
        color: Colors.blue,
        title: lang == 'ja'
            ? 'コンパスで避難'
            : (lang == 'th' ? 'นำทางด้วยเข็มทิศ' : 'Navigate with Compass'),
        description: lang == 'ja'
            ? '災害モードでは、大きな矢印が避難所の方向を指します。画面を見ながら、矢印の方向へ進んでください。'
            : (lang == 'th'
                ? 'ในโหมดภัยพิบัติ ลูกศรใหญ่จะชี้ไปยังที่พักพิง เดินตามทิศทางของลูกศร'
                : 'In disaster mode, a large arrow points to shelter. Follow the arrow direction.'),
      ),

      // Page 3: Voice Guidance
      TutorialPage(
        icon: Icons.record_voice_over,
        color: Colors.green,
        title: lang == 'ja'
            ? '音声ガイダンス'
            : (lang == 'th' ? 'คำแนะนำด้วยเสียง' : 'Voice Guidance'),
        description: lang == 'ja'
            ? '方向と距離を音声でお知らせします。パニック時でも、聞くだけで避難できます。'
            : (lang == 'th'
                ? 'บอกทิศทางและระยะทางด้วยเสียง แม้ตกใจก็สามารถอพยพได้'
                : 'Direction and distance are announced by voice. Even in panic, just listen to evacuate.'),
      ),

      // Page 4: First Aid
      TutorialPage(
        icon: Icons.healing,
        color: Colors.orange,
        title: lang == 'ja'
            ? '応急処置ガイド'
            : (lang == 'th' ? 'คู่มือปฐมพยาบาล' : 'First Aid Guide'),
        description: lang == 'ja'
            ? '止血・心肺蘇生などの応急処置を、ステップバイステップで確認できます。オフラインでも使えます。'
            : (lang == 'th'
                ? 'ดูการปฐมพยาบาลเช่น หยุดเลือด CPR แบบขั้นตอน ใช้ได้แม้ออฟไลน์'
                : 'Check first aid like bleeding control and CPR step by step. Works offline.'),
      ),

      // Page 5: Emergency Card
      TutorialPage(
        icon: Icons.contact_emergency,
        color: Colors.purple,
        title: lang == 'ja'
            ? 'Emergency Gear'
            : (lang == 'th' ? 'อุปกรณ์ฉุกเฉิน' : 'Emergency Gear'),
        description: lang == 'ja'
            ? '名前・血液型・アレルギーを登録しておくと、緊急時にスタッフに見せることができます。'
            : (lang == 'th'
                ? 'ลงทะเบียนชื่อ กรุ๊ปเลือด ภูมิแพ้ เพื่อแสดงให้เจ้าหน้าที่ในกรณีฉุกเฉิน'
                : 'Register name, blood type, and allergies to show staff in emergency.'),
      ),

      // Page 6: Ready
      TutorialPage(
        icon: Icons.check_circle,
        color: const Color(0xFF43A047),
        title: lang == 'ja'
            ? '準備完了！'
            : (lang == 'th' ? 'พร้อมแล้ว!' : 'You\'re Ready!'),
        description: lang == 'ja'
            ? 'いざという時、GapLessがあなたを守ります。まずは設定画面でプロフィールを登録しましょう。'
            : (lang == 'th'
                ? 'GapLess จะปกป้องคุณเมื่อเกิดเหตุ เริ่มต้นด้วยการลงทะเบียนโปรไฟล์'
                : 'GapLess will protect you. Start by registering your profile in settings.'),
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
