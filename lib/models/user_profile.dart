/// ユーザープロファイル — ナビゲーションのペナルティ係数を決定する
///
/// このモデルはアプリ設定画面で永続化し、経路計算エンジンに渡す。
class UserProfile {
  /// 車椅子・ベビーカー等、段差不可
  final bool requiresFlatRoute;

  /// 高齢者モード — 距離より平坦さ・広さを優先
  final bool isElderly;

  /// 歩行速度（m/s）。デフォルト 1.2 m/s（標準歩行）
  final double walkSpeedMps;

  const UserProfile({
    this.requiresFlatRoute = false,
    this.isElderly = false,
    this.walkSpeedMps = 1.2,
  });

  /// 標準プロファイル（健常成人）
  static const UserProfile standard = UserProfile();

  /// 車椅子ユーザー
  static const UserProfile wheelchair = UserProfile(
    requiresFlatRoute: true,
    walkSpeedMps: 0.8,
  );

  /// 高齢者
  static const UserProfile elderly = UserProfile(
    isElderly: true,
    walkSpeedMps: 0.9,
  );

  UserProfile copyWith({
    bool? requiresFlatRoute,
    bool? isElderly,
    double? walkSpeedMps,
  }) =>
      UserProfile(
        requiresFlatRoute: requiresFlatRoute ?? this.requiresFlatRoute,
        isElderly: isElderly ?? this.isElderly,
        walkSpeedMps: walkSpeedMps ?? this.walkSpeedMps,
      );
}
