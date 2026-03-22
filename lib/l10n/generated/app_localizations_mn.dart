// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Mongolian (`mn`).
class AppLocalizationsMn extends AppLocalizations {
  AppLocalizationsMn([String locale = 'mn']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => 'Газрын зураг ачааллаж байна...';

  @override
  String get hazardZone => 'Аюулын бүс';

  @override
  String get safeRoute => 'Аюулгүй маршрут';

  @override
  String get currentLocation => 'Одоогийн байршил';

  @override
  String get offlineMode => 'Офлайн горим';

  @override
  String get noDataAvailable => 'Мэдээлэл байхгүй';

  @override
  String get compassHeading => 'Чиглэл';

  @override
  String get nearbyHazard => 'Ойролцоо аюулын бүс байна';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return 'Аюулын бүс $distanceStringм зайтай';
  }

  @override
  String get downloadingData => 'Мэдээлэл татаж байна...';

  @override
  String get downloadComplete => 'Татаж дуусав';

  @override
  String get downloadError => 'Мэдээлэл авч чадсангүй';

  @override
  String get poiHospital => 'Эмнэлэг / Клиник';

  @override
  String get poiShelter => 'Нүүлгэн шилжүүлэлтийн хоргодох газар';

  @override
  String get poiStore => 'Тохиромжтой дэлгүүр / Супермаркет';

  @override
  String get poiWater => 'Усны хангамж';

  @override
  String get riskLow => 'Үерийн эрсдэл: Бага';

  @override
  String get riskMedium => 'Үерийн эрсдэл: Дунд';

  @override
  String get riskHigh => 'Үерийн эрсдэл: Өндөр';
}
