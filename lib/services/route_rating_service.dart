import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/route_rating.dart';
import 'device_id_service.dart';

/// ============================================================================
/// RouteRatingService - ルート評価の送信・重複チェック管理
/// ============================================================================
///
/// 【重複投票防止の仕組み】
/// 1. 機器ごとのUUID（DeviceIdService）を評価データに付加
/// 2. ローカルで「deviceId + routeId」の組み合わせを記録
/// 3. 同じ機器から同じルートへの重複評価をブロック
///
/// 【プライバシー設計】
/// - 送信データ: deviceId(UUID), routeId, score, ratingType, lat, lng, timestamp のみ
/// - 個人名・メールアドレス・電話番号は一切含まない
/// ============================================================================
class RouteRatingService {
  static final RouteRatingService instance = RouteRatingService._internal();
  RouteRatingService._internal();

  static const String _localRatingsKey = 'gapless_submitted_ratings';

  /// 評価済みの「deviceId:routeId」ペアをローカルに記録するセット
  Set<String> _submittedKeys = {};

  /// 初期化（送信済みリストをlocalStorageから復元）
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_localRatingsKey) ?? [];
      _submittedKeys = stored.toSet();
    } catch (e) {
      debugPrint('⚠️ RouteRatingService: 初期化エラー: $e');
    }
  }

  /// ============================================================
  /// 評価を送信する
  ///
  /// [routeId]    評価対象のルート/スポットID
  /// [score]      評価スコア (1〜5)
  /// [ratingType] 評価種別 ('road_safety', 'shelter_quality' など)
  /// [lat], [lng] 評価対象の場所の座標（任意）
  /// [comment]    コメント（任意・プレーンテキストのみ）
  ///
  /// 戻り値: 成功 → true、重複 or エラー → false
  /// ============================================================
  Future<RatingResult> submitRating({
    required String routeId,
    required int score,
    required String ratingType,
    double? lat,
    double? lng,
    String? comment,
  }) async {
    // 1. デバイスIDを取得（localStorageのUUID）
    final deviceId = DeviceIdService.instance.deviceId;
    if (deviceId == null) {
      debugPrint('⚠️ RouteRatingService: DeviceIdが未初期化');
      return RatingResult.error('DeviceId not initialized');
    }

    // 2. 重複チェック（同一機器から同一ルートへの投票を防ぐ）
    final compositeKey = '${deviceId}:${routeId}:${ratingType}';
    if (_submittedKeys.contains(compositeKey)) {
      debugPrint('⚠️ RouteRatingService: 重複評価をブロック (${routeId})');
      return RatingResult.duplicate();
    }

    // 3. 評価データを構築
    final rating = RouteRating(
      deviceId: deviceId, // ← localStorageのUUID (個人情報なし)
      routeId: routeId,
      score: score,
      ratingType: ratingType,
      lat: lat,
      lng: lng,
      comment: comment,
    );

    debugPrint('📊 RouteRatingService: 評価送信 → ${rating.toJson()}');

    // 4. ローカル保存（オフライン対応）
    await _saveLocally(rating);

    // 5. 送信済みとしてマーク
    await _markAsSubmitted(compositeKey);

    debugPrint('✅ RouteRatingService: 評価送信完了 (score: $score)');
    return RatingResult.success(rating);
  }

  /// 評価をローカルに保存（SharedPreferences経由でlocalStorageへ）
  Future<void> _saveLocally(RouteRating rating) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList('gapless_ratings_queue') ?? [];
      existing.add(jsonEncode(rating.toJson()));
      // 最大100件まで保持（古いものは削除）
      if (existing.length > 100) {
        existing.removeRange(0, existing.length - 100);
      }
      await prefs.setStringList('gapless_ratings_queue', existing);
    } catch (e) {
      debugPrint('⚠️ RouteRatingService: ローカル保存エラー: $e');
    }
  }

  /// 送信済みとしてマーク（重複チェック用）
  Future<void> _markAsSubmitted(String compositeKey) async {
    _submittedKeys.add(compositeKey);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_localRatingsKey, _submittedKeys.toList());
    } catch (e) {
      debugPrint('⚠️ RouteRatingService: 送信済みマーク保存エラー: $e');
    }
  }

  /// 指定ルートへの評価済みかどうか確認
  bool hasRated({required String routeId, required String ratingType}) {
    final deviceId = DeviceIdService.instance.deviceId;
    if (deviceId == null) return false;
    return _submittedKeys.contains('${deviceId}:${routeId}:${ratingType}');
  }

  /// ローカルに保存された未送信の評価を取得（サーバー同期用）
  Future<List<Map<String, dynamic>>> getPendingRatings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList('gapless_ratings_queue') ?? [];
      return queue.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
    } catch (e) {
      return [];
    }
  }
}

/// ============================================================
/// RatingResult - 評価送信の結果
/// ============================================================
class RatingResult {
  final bool success;
  final bool isDuplicate;
  final String? error;
  final RouteRating? rating;

  const RatingResult._({
    required this.success,
    required this.isDuplicate,
    this.error,
    this.rating,
  });

  factory RatingResult.success(RouteRating rating) => RatingResult._(
        success: true,
        isDuplicate: false,
        rating: rating,
      );

  factory RatingResult.duplicate() => RatingResult._(
        success: false,
        isDuplicate: true,
      );

  factory RatingResult.error(String message) => RatingResult._(
        success: false,
        isDuplicate: false,
        error: message,
      );
}
