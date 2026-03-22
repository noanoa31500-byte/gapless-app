// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => '地図を読み込み中...';

  @override
  String get hazardZone => '危険地帯';

  @override
  String get safeRoute => '安全ルート';

  @override
  String get currentLocation => '現在地';

  @override
  String get offlineMode => 'オフラインモード';

  @override
  String get noDataAvailable => 'データがありません';

  @override
  String get compassHeading => '方位';

  @override
  String get nearbyHazard => '近くに危険地帯があります';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return '危険地帯まで${distanceString}m';
  }

  @override
  String get downloadingData => 'データをダウンロード中...';

  @override
  String get downloadComplete => 'ダウンロード完了';

  @override
  String get downloadError => 'データの取得に失敗しました';

  @override
  String get poiHospital => '病院・診療所';

  @override
  String get poiShelter => '避難所';

  @override
  String get poiStore => 'コンビニ・スーパー';

  @override
  String get poiWater => '給水所';

  @override
  String get riskLow => '浸水リスク：低';

  @override
  String get riskMedium => '浸水リスク：中';

  @override
  String get riskHigh => '浸水リスク：高';
}
