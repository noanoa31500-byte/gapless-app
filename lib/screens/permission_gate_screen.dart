import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/localization.dart';
import 'navigation_screen.dart';

// ============================================================================
// PermissionGateScreen — 初回起動時パーミッション取得フロー
// ============================================================================
//
// 【フロー】
//   SharedPreferences 'permissions_granted' = true
//     → このスクリーンをスキップして NavigationScreen へ（呼び出し元で判定）
//
//   初回起動
//     ① 位置情報（必須）
//     ② モーション/センサー（任意: 拒否 → 警告を出して次へ）
//     ③ Bluetooth（任意: スキップ可能）
//     → NavigationScreen へ pushReplacement
//
// ============================================================================

// ── ステップ定義 ──────────────────────────────────────────────────────────────

class _PermStep {
  final String title;
  final String description;
  final IconData icon;

  /// true = 「スキップ」ボタンを表示する
  final bool isSkippable;

  /// true = 拒否されてもスキップして次へ（false = ダイアログを表示）
  final bool isOptional;

  const _PermStep({
    required this.title,
    required this.description,
    required this.icon,
    this.isSkippable = false,
    this.isOptional = false,
  });
}

// ── ウィジェット ──────────────────────────────────────────────────────────────

class PermissionGateScreen extends StatefulWidget {
  const PermissionGateScreen({super.key});

  @override
  State<PermissionGateScreen> createState() => _PermissionGateScreenState();
}

class _PermissionGateScreenState extends State<PermissionGateScreen> {
  // ── UI 定数 ───────────────────────────────────────────────────────────────
  static const Color _navyPrimary = Color(0xFF2E7D32);
  static const Color _orangeAccent = Color(0xFFFF6F00);

  // ── ステップ定義 ──────────────────────────────────────────────────────────
  static const List<_PermStep> _steps = [
    _PermStep(
      title: '位置情報',
      description: 'ルート案内中もバックグラウンドで現在地を取得します',
      icon: Icons.location_on_rounded,
      isSkippable: false,
      isOptional: false,
    ),
    _PermStep(
      title: 'モーション / センサー',
      description: 'コンパスと加速度センサーで正確な向きを計算します',
      icon: Icons.compass_calibration_rounded,
      isSkippable: false,
      isOptional: true,
    ),
    _PermStep(
      title: 'Bluetooth',
      description: '近くのユーザーと道路状況を共有します（任意）',
      icon: Icons.bluetooth_rounded,
      isSkippable: true,
      isOptional: true,
    ),
  ];

  // ── 状態 ─────────────────────────────────────────────────────────────────
  int _currentStep = 0;
  bool _isRequesting = false;
  String? _warningMessage;

  // ── パーミッション要求 ────────────────────────────────────────────────────

  Future<void> _onPermit() async {
    setState(() {
      _isRequesting = true;
      _warningMessage = null;
    });

    try {
      if (_currentStep == 0) {
        await _requestLocation();
      } else if (_currentStep == 1) {
        await _requestSensors();
      } else if (_currentStep == 2) {
        await _requestBluetooth();
      }
    } catch (e) {
      debugPrint('PermissionGateScreen: request error $e');
      // 予期しないエラーはオプション権限として扱い次へ進む
      if (_steps[_currentStep].isOptional) {
        _advance();
      }
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  // ① 位置情報（必須）
  Future<void> _requestLocation() async {
    // すでに許可済みなら即次へ
    if (await Permission.locationAlways.isGranted) {
      _advance();
      return;
    }

    final status = await Permission.locationAlways.request();

    if (!mounted) return;

    if (status.isGranted) {
      _advance();
    } else {
      // 拒否 or 永久拒否 → ダイアログ
      setState(() => _isRequesting = false);
      _showLocationDeniedDialog(isPermanent: status.isPermanentlyDenied);
    }
  }

  // ② センサー（任意）
  Future<void> _requestSensors() async {
    if (await Permission.sensors.isGranted) {
      _advance();
      return;
    }

    final status = await Permission.sensors.request();

    if (!mounted) return;

    if (!status.isGranted) {
      setState(() => _warningMessage = 'コンパス機能が制限されます');
    }
    _advance();
  }

  // ③ Bluetooth（任意・iOS と Android で対応が異なる）
  Future<void> _requestBluetooth() async {
    if (Platform.isIOS) {
      await Permission.bluetooth.request();
    } else {
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
    }
    if (mounted) _advance();
  }

  void _onSkip() {
    setState(() => _warningMessage = null);
    _advance();
  }

  void _advance() {
    if (_currentStep >= _steps.length - 1) {
      _complete();
    } else {
      setState(() {
        _currentStep++;
        _warningMessage = null;
        _isRequesting = false;
      });
    }
  }

  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_granted', true);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const NavigationScreen()),
    );
  }

  // ── ダイアログ ────────────────────────────────────────────────────────────

  void _showLocationDeniedDialog({required bool isPermanent}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          '位置情報が必要です',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          '位置情報がないとナビが使えません。\n設定から位置情報を「常に許可」してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(GapLessL10n.t('loc_open_settings')),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, animation) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          ),
          child: _buildStep(
            _steps[_currentStep],
            key: ValueKey(_currentStep),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(_PermStep step, {required Key key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          _buildProgressDots(),
          const Spacer(),
          _buildIcon(step.icon),
          const SizedBox(height: 40),
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            step.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFB0BEC5),
              fontSize: 16,
              height: 1.6,
            ),
          ),
          if (_warningMessage != null) ...[
            const SizedBox(height: 20),
            _buildWarning(_warningMessage!),
          ],
          const Spacer(),
          _buildPermitButton(),
          const SizedBox(height: 12),
          if (step.isSkippable) _buildSkipButton(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── プログレスドット ───────────────────────────────────────────────────────

  Widget _buildProgressDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_steps.length, (i) {
        final isActive = i == _currentStep;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? _orangeAccent : const Color(0xFF37474F),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ── アイコン ──────────────────────────────────────────────────────────────

  Widget _buildIcon(IconData icon) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF0D1257)],
        ),
        boxShadow: [
          BoxShadow(
            color: _navyPrimary.withValues(alpha: 0.5),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Icon(icon, size: 72, color: Colors.white),
    );
  }

  // ── 警告テキスト ──────────────────────────────────────────────────────────

  Widget _buildWarning(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _orangeAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _orangeAccent.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, color: _orangeAccent, size: 18),
          const SizedBox(width: 8),
          Text(
            message,
            style: const TextStyle(
              color: _orangeAccent,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── 「許可する」ボタン ────────────────────────────────────────────────────

  Widget _buildPermitButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isRequesting ? null : _onPermit,
        style: ElevatedButton.styleFrom(
          backgroundColor: _navyPrimary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF37474F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 4,
        ),
        child: _isRequesting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                '許可する',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  // ── 「スキップ」ボタン ────────────────────────────────────────────────────

  Widget _buildSkipButton() {
    return TextButton(
      onPressed: _isRequesting ? null : _onSkip,
      child: const Text(
        'スキップ',
        style: TextStyle(
          color: Color(0xFF78909C),
          fontSize: 14,
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFF78909C),
        ),
      ),
    );
  }
}
