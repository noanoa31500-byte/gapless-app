import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/localization.dart';
import '../providers/shelter_provider.dart';
import '../providers/language_provider.dart';
import '../utils/styles.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isInitialized = false;
  String _loadingKey = 'splash_loading';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  /// バックグラウンドでアプリを初期化
  Future<void> _initializeApp() async {
    // 1. 言語設定
    setState(() => _loadingKey = 'splash_loading_lang');
    await GapLessL10n.loadLanguage();
    
    if (mounted) {
      final languageProvider = context.read<LanguageProvider>();
      await languageProvider.loadLanguage();
    }

    // 2. マップデータ（避難所・ハザード情報）
    if (!mounted) return;
    setState(() => _loadingKey = 'splash_loading_map');
    if (mounted) {
      final shelterProvider = context.read<ShelterProvider>();
      await shelterProvider.loadShelters();
      if (!mounted) return;
      setState(() => _loadingKey = 'splash_loading_hazard');
      await shelterProvider.loadHazardPolygons();
    }

    if (!mounted) return;
    setState(() {
      _loadingKey = 'splash_ready';
      _isInitialized = true;
    });
  }

  /// 同意して開始
  Future<void> _agreeAndStart() async {
    if (mounted) {
      // HomeScreenに遷移
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // 言語変更時に再描画
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    
                    // ロゴ
                    _buildLogo(),
                    
                    const SizedBox(height: 48),
                    
                    // 免責事項カード
                    _buildDisclaimerCard(),
                    
                    const SizedBox(height: 32),
                    
                    // 同意ボタン
                    _buildAgreeButton(),
                    
                    const Spacer(),
                    
                    // バージョン情報
                    const Text(
                      'v5.3',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'Version 1.0.0 - Mitou Junior',
                      style: emergencyTextStyle(size: 12, color: const Color(0xFF6B7280)),
                    ),
                    
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ロゴ
  Widget _buildLogo() {
    return Column(
      children: [
        // アイコン
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFFE53935),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE53935).withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.shield,
            size: 60,
            color: Colors.white,
          ),
        ),
        
        const SizedBox(height: 24),
        
        // タイトル（GapLess ロゴ）
        RichText(
          text: TextSpan(
            style: emergencyTextStyle(size: 32),
            children: [
              TextSpan(
                text: 'Gap',
                style: emergencyTextStyle(size: 32, isBold: true, color: const Color(0xFF111827)),
              ),
              TextSpan(
                text: 'Less',
                style: emergencyTextStyle(size: 32, isBold: true, color: const Color(0xFFE53935)),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 8),
        
        // サブタイトル
        Text(
          GapLessL10n.t('splash_subtitle'),
          style: emergencyTextStyle(size: 14, color: const Color(0xFF6B7280)),
        ),
      ],
    );
  }

  /// 免責事項カード
  Widget _buildDisclaimerCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE53935).withValues(alpha: 0.2),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // タイトル
          Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: Color(0xFFE53935),
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                GapLessL10n.t('splash_disclaimer_title'),
                style: emergencyTextStyle(size: 18, isBold: true, color: const Color(0xFF111827)),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          const Divider(),
          
          const SizedBox(height: 16),
          
          // 本文（日本語）
          Text(
            GapLessL10n.t('splash_disclaimer_jp'),
            style: emergencyTextStyle(size: 14, color: const Color(0xFF374151)),
          ),
          
          const SizedBox(height: 12),
          
          // 本文（英語）
          Text(
            GapLessL10n.t('splash_disclaimer_en'),
            style: emergencyTextStyle(size: 13, color: const Color(0xFF6B7280)),
          ),
          
          const SizedBox(height: 16),
          
          // 注意事項
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber,
                  color: Color(0xFFD97706),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    GapLessL10n.t('splash_warning'),
                    style: emergencyTextStyle(
                      size: 12,
                      color: const Color(0xFF92400E),
                      isBold: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 同意ボタン
  Widget _buildAgreeButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isInitialized ? _agreeAndStart : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE53935),
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isInitialized
            ? Text(
                GapLessL10n.t('splash_agree'),
                style: emergencyTextStyle(size: 18, isBold: true, color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                   const SizedBox(width: 12),
                  Text(
                    GapLessL10n.t(_loadingKey),
                    style: emergencyTextStyle(size: 16, color: Colors.white),
                  ),
                ],
              ),
      ),
    );
  }
}
