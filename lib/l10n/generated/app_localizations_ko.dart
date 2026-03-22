// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => '지도 로딩 중...';

  @override
  String get hazardZone => '위험 구역';

  @override
  String get safeRoute => '안전 경로';

  @override
  String get currentLocation => '현재 위치';

  @override
  String get offlineMode => '오프라인 모드';

  @override
  String get noDataAvailable => '데이터 없음';

  @override
  String get compassHeading => '방향';

  @override
  String get nearbyHazard => '근처에 위험 구역이 있습니다';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return '위험 구역까지 ${distanceString}m';
  }

  @override
  String get downloadingData => '데이터 다운로드 중...';

  @override
  String get downloadComplete => '다운로드 완료';

  @override
  String get downloadError => '데이터 가져오기 실패';

  @override
  String get poiHospital => '병원 / 진료소';

  @override
  String get poiShelter => '대피소';

  @override
  String get poiStore => '편의점 / 슈퍼마켓';

  @override
  String get poiWater => '급수 지점';

  @override
  String get riskLow => '침수 위험: 낮음';

  @override
  String get riskMedium => '침수 위험: 중간';

  @override
  String get riskHigh => '침수 위험: 높음';
}
