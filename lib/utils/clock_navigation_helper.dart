import 'package:flutter/material.dart';

/// ============================================================================
/// ClockNavigationHelper - 0.1秒判断のためのナビゲーションUI変換ロジック
/// ============================================================================
///
/// 【設計思想】
/// パニック状態の被災者は、複雑な情報を処理できません。
/// 本クラスは「色」と「短い言葉」だけで、0.1秒で行動を決定できるUIを生成します。
///
/// 【認知心理学的根拠】
/// - 緑 = GO（本能的に「進め」と認識）
/// - 黄/橙 = 注意（方向修正が必要）
/// - 赤 = STOP（即座に行動を止める）
///
/// これは世界共通の信号機カラーコードであり、言語を超えて理解されます。
/// ============================================================================

/// ナビゲーション状態の区分
enum NavZone {
  /// 正解（前方 ±11.25度）- そのまま進め
  go,

  /// 微修正（前方〜斜め前 ±45度）- 少し方向を変えて
  slightAdjust,

  /// 要修正（斜め〜横 ±45〜112.5度）- 大きく方向を変えて
  majorAdjust,

  /// 逆方向（後方 ±112.5度以上）- 引き返せ
  reverse,
}

/// ============================================================================
/// ClockNavState - ナビゲーション状態を保持するイミュータブルクラス
/// ============================================================================
class ClockNavState {
  /// 表示メッセージ（多言語対応）
  final String messageJa;
  final String messageEn;
  final String messageTh;

  /// 短縮メッセージ（UI表示用）
  final String shortMessage;

  /// 背景色
  final Color backgroundColor;

  /// テキスト色
  final Color textColor;

  /// アイコン
  final IconData icon;

  /// アイコンの回転角（ラジアン）
  final double iconRotation;

  /// ナビゲーション区分
  final NavZone zone;

  /// 角度差（デバッグ用）
  final double relativeAngle;

  /// 時計位置（1-12、0は12時）
  final int clockPosition;

  const ClockNavState({
    required this.messageJa,
    required this.messageEn,
    required this.messageTh,
    required this.shortMessage,
    required this.backgroundColor,
    required this.textColor,
    required this.icon,
    required this.iconRotation,
    required this.zone,
    required this.relativeAngle,
    required this.clockPosition,
  });

  /// 言語に応じたメッセージを取得
  String getMessage(String lang) {
    switch (lang) {
      case 'ja':
        return messageJa;
      case 'th':
        return messageTh;
      default:
        return messageEn;
    }
  }

  /// 正解方向を向いているか
  bool get isOnTarget => zone == NavZone.go;

  /// 修正が必要か
  bool get needsAdjustment =>
      zone == NavZone.slightAdjust || zone == NavZone.majorAdjust;

  /// 逆方向か
  bool get isReverse => zone == NavZone.reverse;
}

/// ============================================================================
/// ClockNavigationHelper - メインヘルパークラス
/// ============================================================================
class ClockNavigationHelper {
  ClockNavigationHelper._(); // インスタンス化防止

  // === 定数定義 ===

  /// 正解範囲（±11.25度 = 時計の1目盛りの半分）
  static const double goThreshold = 11.25;

  /// 微修正範囲（±45度 = 前方寄り）
  static const double slightAdjustThreshold = 45.0;

  /// 要修正範囲（±112.5度 = 横〜斜め後ろ）
  static const double majorAdjustThreshold = 112.5;

  /// ヒステリシス幅（境界でのパタパタを防止）
  ///
  /// 【ヒステリシスとは】
  /// 状態が切り替わる閾値に「幅」を持たせること。
  /// 例: 11.25度で「GO」→「微修正」に切り替わる場合、
  ///     逆方向（「微修正」→「GO」）は9.25度で切り替わる。
  /// これにより、11.25度付近でのパタパタ表示を防止。
  static const double hysteresis = 2.0;

  // === カラー定義 ===

  /// 正解（緑）- 進め
  static const Color goColor = Color(0xFF00C853); // Green A700

  /// 微修正（黄）- 少し調整
  static const Color slightAdjustColor = Color(0xFFFFD600); // Yellow A700

  /// 要修正（橙）- 大きく調整
  static const Color majorAdjustColor = Color(0xFFFF9100); // Orange A700

  /// 逆方向（赤）- 戻れ
  static const Color reverseColor = Color(0xFFFF1744); // Red A400

  /// 前回の状態（ヒステリシス用）
  static NavZone? _previousZone;

  /// ============================================================================
  /// calculateState - 状態計算のメインエントリーポイント
  /// ============================================================================
  ///
  /// @param targetBearing 目的地への真方位（0-360度）
  /// @param deviceHeading 端末が向いている真方位（0-360度）
  /// @param applyHysteresis ヒステリシスを適用するか（デフォルト: true）
  /// @return ClockNavState ナビゲーション状態
  static ClockNavState calculateState(
    double targetBearing,
    double deviceHeading, {
    bool applyHysteresis = true,
  }) {
    // 1. 角度差を計算（-180〜+180に正規化）
    double relativeAngle = targetBearing - deviceHeading;
    while (relativeAngle > 180) relativeAngle -= 360;
    while (relativeAngle < -180) relativeAngle += 360;

    // 2. ナビゲーション区分を判定
    final zone = _determineZone(relativeAngle, applyHysteresis);
    _previousZone = zone;

    // 3. 時計位置を計算（1-12、0は12時扱い）
    final clockPosition = _angleToClockPosition(relativeAngle);

    // 4. 区分に応じた状態を生成
    return _createState(zone, relativeAngle, clockPosition);
  }

  /// ナビゲーション区分を判定（ヒステリシス対応）
  static NavZone _determineZone(double angle, bool applyHysteresis) {
    final absAngle = angle.abs();

    // ヒステリシス調整値
    double goThresholdAdj = goThreshold;
    double slightThresholdAdj = slightAdjustThreshold;
    double majorThresholdAdj = majorAdjustThreshold;

    if (applyHysteresis && _previousZone != null) {
      // 現在の状態から「抜ける」には、より大きな変化が必要
      switch (_previousZone!) {
        case NavZone.go:
          goThresholdAdj += hysteresis; // GOから抜けにくくする
          break;
        case NavZone.slightAdjust:
          goThresholdAdj -= hysteresis; // GOに入りやすくする
          slightThresholdAdj += hysteresis;
          break;
        case NavZone.majorAdjust:
          slightThresholdAdj -= hysteresis;
          majorThresholdAdj += hysteresis;
          break;
        case NavZone.reverse:
          majorThresholdAdj -= hysteresis;
          break;
      }
    }

    if (absAngle <= goThresholdAdj) {
      return NavZone.go;
    } else if (absAngle <= slightThresholdAdj) {
      return NavZone.slightAdjust;
    } else if (absAngle <= majorThresholdAdj) {
      return NavZone.majorAdjust;
    } else {
      return NavZone.reverse;
    }
  }

  /// 角度を時計位置（1-12）に変換
  ///
  /// 【変換ルール】
  /// - 0度（前方）= 12時
  /// - +30度（右斜め前）= 1時
  /// - +90度（右）= 3時
  /// - +180度（後方）= 6時
  /// - -90度（左）= 9時
  static int _angleToClockPosition(double angle) {
    // 角度を0-360に正規化
    double normalized = angle;
    while (normalized < 0) normalized += 360;
    while (normalized >= 360) normalized -= 360;

    // 30度刻みで時計位置に変換
    // 各位置の中心: 0(12時), 30(1時), 60(2時), ...
    int position = ((normalized + 15) / 30).floor() % 12;
    return position == 0 ? 12 : position;
  }

  /// 状態オブジェクトを生成
  static ClockNavState _createState(
      NavZone zone, double angle, int clockPosition) {
    switch (zone) {
      case NavZone.go:
        return ClockNavState(
          messageJa: 'そのまま真っすぐ',
          messageEn: 'Go straight',
          messageTh: 'ตรงไปเลย',
          shortMessage: 'GO',
          backgroundColor: goColor,
          textColor: Colors.white,
          icon: Icons.arrow_upward,
          iconRotation: 0,
          zone: zone,
          relativeAngle: angle,
          clockPosition: 12,
        );

      case NavZone.slightAdjust:
        return _createAdjustState(
          zone: zone,
          angle: angle,
          clockPosition: clockPosition,
          backgroundColor: slightAdjustColor,
          textColor: Colors.black87,
        );

      case NavZone.majorAdjust:
        return _createAdjustState(
          zone: zone,
          angle: angle,
          clockPosition: clockPosition,
          backgroundColor: majorAdjustColor,
          textColor: Colors.white,
        );

      case NavZone.reverse:
        return ClockNavState(
          messageJa: '逆方向です（戻れ）',
          messageEn: 'Wrong way (turn back)',
          messageTh: 'ผิดทาง (กลับตัว)',
          shortMessage: 'BACK',
          backgroundColor: reverseColor,
          textColor: Colors.white,
          icon: Icons.u_turn_left,
          iconRotation: 0,
          zone: zone,
          relativeAngle: angle,
          clockPosition: 6,
        );
    }
  }

  /// 微修正/要修正状態を生成
  static ClockNavState _createAdjustState({
    required NavZone zone,
    required double angle,
    required int clockPosition,
    required Color backgroundColor,
    required Color textColor,
  }) {
    final isRight = angle > 0;
    final clockText = '$clockPosition時';
    final directionJa = isRight ? '右' : '左';
    final directionEn = isRight ? 'right' : 'left';
    final directionTh = isRight ? 'ขวา' : 'ซ้าย';

    // 詳細な方向説明
    String detailJa, detailEn, detailTh;
    if (angle.abs() <= 45) {
      detailJa = '斜め前';
      detailEn = 'diagonal';
      detailTh = 'เฉียง';
    } else if (angle.abs() <= 90) {
      detailJa = '横';
      detailEn = 'side';
      detailTh = 'ข้าง';
    } else {
      detailJa = '斜め後ろ';
      detailEn = 'behind';
      detailTh = 'เฉียงหลัง';
    }

    return ClockNavState(
      messageJa: '$clockText方向（$directionJa$detailJa）',
      messageEn: '$clockPosition o\'clock ($directionEn $detailEn)',
      messageTh: '$clockPosition นาฬิกา ($directionTh$detailTh)',
      shortMessage: clockText,
      backgroundColor: backgroundColor,
      textColor: textColor,
      icon: isRight ? Icons.turn_slight_right : Icons.turn_slight_left,
      iconRotation: angle * (3.14159265359 / 180), // 実際の角度で回転
      zone: zone,
      relativeAngle: angle,
      clockPosition: clockPosition,
    );
  }

  /// ヒステリシス状態をリセット
  static void resetHysteresis() {
    _previousZone = null;
  }

  /// デバッグ情報を出力
  static void printDebugInfo(ClockNavState state) {
    debugPrint('''
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🕐 ClockNavigationHelper Debug
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📐 Relative Angle: ${state.relativeAngle.toStringAsFixed(1)}°
🕐 Clock Position: ${state.clockPosition}時
🎯 Zone: ${state.zone}
📝 Message: ${state.messageJa}
🎨 Color: ${state.backgroundColor}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
  }
}
