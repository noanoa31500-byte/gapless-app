import 'package:get_it/get_it.dart';
import '../providers/shelter_repository.dart';
import '../providers/hazard_service.dart';
import '../providers/nav_target_controller.dart';
import '../providers/disaster_mode_notifier.dart';
import '../services/safety_route_engine.dart';

/// ============================================================================
/// Service Locator (get_it) — Wave2 DI
/// ============================================================================
/// 16+ singletons がアプリ全体に散在していた問題への対処。
///
/// 使用例:
///   await setupServiceLocator();
///   final hazard = sl<HazardService>();
///
/// 注意:
///   - 既存スクリーンは Provider/直接シングルトン参照のままで動く（強制移行はしない）
///   - 新規コードは sl<T>() を経由して依存を取得することを推奨
final GetIt sl = GetIt.instance;

bool _initialized = false;

Future<void> setupServiceLocator() async {
  if (_initialized) return;
  _initialized = true;

  // ── Repositories (stateless / safe to share) ──────────────────────
  sl.registerLazySingleton<ShelterRepository>(() => ShelterRepository());

  // ── ChangeNotifier services (UI が listen する) ───────────────────
  sl.registerLazySingleton<HazardService>(() => HazardService());
  sl.registerLazySingleton<NavTargetController>(() => NavTargetController());
  sl.registerLazySingleton<DisasterModeNotifier>(() {
    final n = DisasterModeNotifier();
    // 永続化済みモードを非同期ロード（fire-and-forget）
    n.load();
    return n;
  });

  // ── Routing engine (factory: グラフは利用側で都度 build) ──────────
  sl.registerFactory<SafetyRouteEngine>(() => SafetyRouteEngine());
}

/// テストや再初期化用
Future<void> resetServiceLocator() async {
  await sl.reset();
  _initialized = false;
}
