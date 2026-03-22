// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Sinhala Sinhalese (`si`).
class AppLocalizationsSi extends AppLocalizations {
  AppLocalizationsSi([String locale = 'si']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => 'සිතියම පූරණය වෙමින්...';

  @override
  String get hazardZone => 'අනතුරු කලාපය';

  @override
  String get safeRoute => 'ආරක්ෂිත මාර්ගය';

  @override
  String get currentLocation => 'වත්මන් ස්ථානය';

  @override
  String get offlineMode => 'ඔෆ්ලයින් මාදිලිය';

  @override
  String get noDataAvailable => 'දත්ත නොමැත';

  @override
  String get compassHeading => 'දිශාව';

  @override
  String get nearbyHazard => 'ළඟ අනතුරු කලාපයක් ඇත';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return 'අනතුරු කලාපය $distanceStringම දුරින් ඇත';
  }

  @override
  String get downloadingData => 'දත්ත බාගත වෙමින්...';

  @override
  String get downloadComplete => 'බාගැනීම සම්පූර්ණයි';

  @override
  String get downloadError => 'දත්ත ලබා ගැනීමට අසාර්ථකයි';

  @override
  String get poiHospital => 'රෝහල / වෛද්‍යාල';

  @override
  String get poiShelter => 'ජනතාව ඉවත් කිරීමේ නවාතැන';

  @override
  String get poiStore => 'පහසු සාප්පුව / සුපර්මාර්කට්';

  @override
  String get poiWater => 'ජල සැපයුම';

  @override
  String get riskLow => 'ගංවතුර අවදානම: අඩු';

  @override
  String get riskMedium => 'ගංවතුර අවදානම: මධ්‍යම';

  @override
  String get riskHigh => 'ගංවතුර අවදානම: ඉහළ';
}
