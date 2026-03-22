// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bengali Bangla (`bn`).
class AppLocalizationsBn extends AppLocalizations {
  AppLocalizationsBn([String locale = 'bn']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => 'মানচিত্র লোড হচ্ছে...';

  @override
  String get hazardZone => 'বিপজ্জনক এলাকা';

  @override
  String get safeRoute => 'নিরাপদ পথ';

  @override
  String get currentLocation => 'বর্তমান অবস্থান';

  @override
  String get offlineMode => 'অফলাইন মোড';

  @override
  String get noDataAvailable => 'কোনো তথ্য নেই';

  @override
  String get compassHeading => 'দিক';

  @override
  String get nearbyHazard => 'কাছে বিপজ্জনক এলাকা আছে';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return 'বিপজ্জনক এলাকা $distanceStringমি দূরে';
  }

  @override
  String get downloadingData => 'ডেটা ডাউনলোড হচ্ছে...';

  @override
  String get downloadComplete => 'ডাউনলোড সম্পন্ন';

  @override
  String get downloadError => 'ডেটা পুনরুদ্ধারে ব্যর্থ';

  @override
  String get poiHospital => 'হাসপাতাল / ক্লিনিক';

  @override
  String get poiShelter => 'আশ্রয় কেন্দ্র';

  @override
  String get poiStore => 'কনভেনিয়েন্স স্টোর / সুপারমার্কেট';

  @override
  String get poiWater => 'পানি সরবরাহ';

  @override
  String get riskLow => 'বন্যার ঝুঁকি: কম';

  @override
  String get riskMedium => 'বন্যার ঝুঁকি: মাঝারি';

  @override
  String get riskHigh => 'বন্যার ঝুঁকি: উচ্চ';
}
