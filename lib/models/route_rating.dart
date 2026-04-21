/// ============================================================================
/// RouteRating - ルート評価データモデル
/// ============================================================================
///
/// 【プライバシー設計】
/// - deviceId: 機器識別番号（UUIDのみ、個人と紐付かない）
/// - 氏名・連絡先など個人を特定する情報は一切含まない
/// - lat/lng は評価対象の「場所」の座標であり、利用者の位置ではない
/// ============================================================================
class RouteRating {
  /// 機器識別番号（重複投票防止用）
  /// SharedPreferencesのlocalStorageから取得したUUID v4
  final String deviceId;

  /// 評価対象のルートID（またはスポットID）
  final String routeId;

  /// 評価スコア（例: 1〜5）
  final int score;

  /// 評価コメント（任意・プレーンテキストのみ）
  final String? comment;

  /// 評価対象の緯度（場所の座標）
  final double? lat;

  /// 評価対象の経度（場所の座標）
  final double? lng;

  /// 評価日時（UTC）
  final DateTime timestamp;

  /// 評価の種類 (例: 'road_safety', 'shelter_quality', 'flood_risk')
  final String ratingType;

  RouteRating({
    required this.deviceId,
    required this.routeId,
    required this.score,
    required this.ratingType,
    this.comment,
    this.lat,
    this.lng,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  /// JSONに変換（サーバー送信・ローカル保存共通）
  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'route_id': routeId,
        'score': score,
        'rating_type': ratingType,
        if (comment != null && comment!.isNotEmpty) 'comment': comment,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'timestamp': timestamp.toIso8601String(),
        // ※ 個人情報フィールドは意図的に含めない
      };

  @override
  String toString() => 'RouteRating(routeId: $routeId, score: $score, '
      'deviceId: ${deviceId.substring(0, deviceId.length.clamp(0, 8))}****)';
}
