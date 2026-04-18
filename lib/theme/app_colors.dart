// ============================================================
// app_colors.dart
// Apple Design System ベースの色定数
// ============================================================

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── ベースカラー ───────────────────────────────
  static const Color pureBlack = Color(0xFF000000);
  static const Color nearBlack = Color(0xFF1D1D1F);
  static const Color lightGray = Color(0xFFF5F5F7);
  static const Color white = Color(0xFFFFFFFF);

  // ── GapLess プライマリ（通常 = 緑）─────────────
  static const Color primaryGreen = Color(0xFF34C759);
  static const Color primaryGreenDark = Color(0xFF30D158);
  static const Color primaryGreenMuted = Color(0xFF1A6B2F);
  static const Color linkGreen = Color(0xFF248A3D);
  static const Color linkGreenDark = Color(0xFF30D158);

  // ── GapLess 緊急モード（emergency = 赤）─────────
  static const Color emergencyRed = Color(0xFFFF3B30);
  static const Color emergencyRedDark = Color(0xFFFF453A);
  static const Color emergencyRedMuted = Color(0xFF7A0000);
  static const Color emergencyRedSurface = Color(0xFF2C0000);

  // ── セマンティック ─────────────────────────────
  static const Color warningOrange = Color(0xFFFF9F0A);
  static const Color border = Color(0xFFD2D2D7);

  // ── ダークサーフェス ───────────────────────────
  static const Color darkSurface1 = Color(0xFF272729);
  static const Color darkSurface2 = Color(0xFF28282A);
  static const Color darkSurface3 = Color(0xFF2A2A2D);

  // ── テキスト透明度 ─────────────────────────────
  static const Color textSecondaryLight = Color(0x7A000000);
  static const Color textPrimaryLight = Color(0xCC000000);
  static const Color textSecondaryDark = Color(0x7AFFFFFF);
  static const Color textPrimaryDark = Color(0xCCFFFFFF);

  // ── オーバーレイ ───────────────────────────────
  static const Color overlayLight = Color(0xA3D2D2D7);
  static const Color overlayDark = Color(0xA33C3C43);
  static const Color navBgLight = Color(0xCC000000);
  static const Color navBgDark = Color(0xE1000000);
}
