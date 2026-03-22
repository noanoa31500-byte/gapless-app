// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Uzbek (`uz`).
class AppLocalizationsUz extends AppLocalizations {
  AppLocalizationsUz([String locale = 'uz']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => 'Xarita yuklanmoqda...';

  @override
  String get hazardZone => 'Xavfli zona';

  @override
  String get safeRoute => 'Xavfsiz yo\'l';

  @override
  String get currentLocation => 'Joriy joylashuv';

  @override
  String get offlineMode => 'Oflayn rejim';

  @override
  String get noDataAvailable => 'Ma\'lumot yo\'q';

  @override
  String get compassHeading => 'Yo\'nalish';

  @override
  String get nearbyHazard => 'Yaqin atrofda xavfli zona bor';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return 'Xavfli zona ${distanceString}m uzoqda';
  }

  @override
  String get downloadingData => 'Ma\'lumot yuklanmoqda...';

  @override
  String get downloadComplete => 'Yuklash tugadi';

  @override
  String get downloadError => 'Ma\'lumot olishda xatolik';

  @override
  String get poiHospital => 'Kasalxona / Klinika';

  @override
  String get poiShelter => 'Evakuatsiya boshpanasi';

  @override
  String get poiStore => 'Qulay do\'kon / Supermarket';

  @override
  String get poiWater => 'Suv ta\'minoti';

  @override
  String get riskLow => 'Suv toshqini xavfi: Past';

  @override
  String get riskMedium => 'Suv toshqini xavfi: O\'rta';

  @override
  String get riskHigh => 'Suv toshqini xavfi: Yuqori';
}
