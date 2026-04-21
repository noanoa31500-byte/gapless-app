import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/map_repository.dart';
import '../providers/language_provider.dart';
import '../utils/localization.dart';
import 'navigation_screen.dart';
import 'permission_gate_screen.dart';
import 'onboarding_screen.dart';

// ============================================================================
// MapDataLoadingScreen — マップデータダウンロード進捗画面
// ============================================================================
//
// ダウンロード中: 進捗インジケーター + "X/4 ファイル名..."
// ダウンロード失敗: エラーメッセージ + リトライボタン
// 完了: 次の画面（Onboarding / PermissionGate / Navigation）へ遷移
//
// ============================================================================

class MapDataLoadingScreen extends StatefulWidget {
  const MapDataLoadingScreen({super.key});

  @override
  State<MapDataLoadingScreen> createState() => _MapDataLoadingScreenState();
}

enum _DownloadState { downloading, error, done }

class _MapDataLoadingScreenState extends State<MapDataLoadingScreen> {
  _DownloadState _state = _DownloadState.downloading;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() {
      _state = _DownloadState.downloading;
      _errorMessage = '';
    });

    await MapRepository.instance.ensureAllData(
      progressCallback: (progress) {
        if (!mounted) return;
        if (progress.error != null) {
          setState(() {
            _state = _DownloadState.error;
            _errorMessage = progress.error!;
          });
          return;
        }
        if (progress.isDone) {
          setState(() => _state = _DownloadState.done);
          _navigateNext();
        }
      },
    );

    // ensureAllData がコールバックなしで完了した場合（全ファイル既存）
    if (mounted && _state == _DownloadState.downloading) {
      setState(() => _state = _DownloadState.done);
      await _navigateNext();
    }
  }

  Future<void> _navigateNext() async {
    if (!mounted) return;

    final languageProvider = context.read<LanguageProvider>();
    await languageProvider.loadLanguage();

    final isOnboardingCompleted = await OnboardingScreen.isCompleted();
    if (!mounted) return;

    if (!isOnboardingCompleted) {
      Navigator.pushReplacementNamed(context, '/onboarding');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final permissionsGranted = prefs.getBool('permissions_granted') ?? false;
    if (!mounted) return;

    if (permissionsGranted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const NavigationScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PermissionGateScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // 言語変更時に再描画
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ロゴ
              _buildLogo(),
              const SizedBox(height: 48),

              // コンテンツ（状態によって切替）
              if (_state == _DownloadState.downloading) _buildDownloading(),
              if (_state == _DownloadState.error) _buildError(),
              if (_state == _DownloadState.done) _buildDone(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFE53935),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE53935).withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.shield, size: 48, color: Colors.white),
        ),
        const SizedBox(height: 16),
        RichText(
          text: TextSpan(
            style: GapLessL10n.safeStyle(const TextStyle()),
            children: const [
              TextSpan(
                text: 'Gap',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
              TextSpan(
                text: 'Less',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE53935),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDownloading() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(
          color: Color(0xFF00C896),
          strokeWidth: 3,
        ),
        const SizedBox(height: 20),
        Text(
          GapLessL10n.t('map_download_title'),
          style: GapLessL10n.safeStyle(const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B7280),
          )),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      children: [
        const Icon(
          Icons.error_outline,
          size: 56,
          color: Color(0xFFD32F2F),
        ),
        const SizedBox(height: 16),
        Text(
          GapLessL10n.t('map_download_error'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFFD32F2F),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _errorMessage,
            style: TextStyle(
              fontSize: 12,
              color: const Color(0xFF991B1B),
              fontFamily: GapLessL10n.currentFont,
              fontFamilyFallback: GapLessL10n.fallbackFonts,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.refresh),
            label: Text(GapLessL10n.t('map_download_retry')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // ダウンロード失敗でも既存データで起動できるようスキップを許可
        TextButton(
          onPressed: _navigateNext,
          child: Text(
            GapLessL10n.t('map_download_skip'),
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildDone() {
    return Column(
      children: [
        const Icon(
          Icons.check_circle,
          size: 56,
          color: Color(0xFF16A34A),
        ),
        const SizedBox(height: 12),
        Text(
          GapLessL10n.t('map_download_done'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF16A34A),
          ),
        ),
        const SizedBox(height: 8),
        const CircularProgressIndicator(color: Color(0xFF2E7D32)),
      ],
    );
  }
}
