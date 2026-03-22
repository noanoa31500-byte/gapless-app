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
  int _current = 0;
  int _total = 4;
  String _currentFile = '';
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() {
      _state = _DownloadState.downloading;
      _current = 0;
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
          return;
        }
        setState(() {
          _current = progress.current;
          _total = progress.total;
          _currentFile = progress.fileName;
        });
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
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
    final progress = _total > 0 ? _current / _total : 0.0;

    return Column(
      children: [
        // 進捗テキスト
        Text(
          GapLessL10n.t('map_download_title'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111827),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '$_current / $_total',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2E7D32),
          ),
        ),
        const SizedBox(height: 4),
        if (_currentFile.isNotEmpty)
          Text(
            _currentFile,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
            ),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 24),

        // プログレスバー
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress > 0 ? progress : null,
            minHeight: 8,
            backgroundColor: const Color(0xFFE5E7EB),
            valueColor:
                const AlwaysStoppedAnimation<Color>(Color(0xFF2E7D32)),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          GapLessL10n.t('map_download_note'),
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF9CA3AF),
          ),
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
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF991B1B),
              fontFamily: 'monospace',
              fontFamilyFallback: [
                'NotoSansJP', 'NotoSansSC', 'NotoSansTC', 'NotoSansKR',
                'NotoSansThai', 'NotoSansMyanmar', 'NotoSansSinhala',
                'NotoSansDevanagari', 'NotoSansBengali', 'NotoSans', 'sans-serif',
              ],
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
