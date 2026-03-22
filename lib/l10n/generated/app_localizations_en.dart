// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => 'Loading map...';

  @override
  String get hazardZone => 'Hazard zone';

  @override
  String get safeRoute => 'Safe route';

  @override
  String get currentLocation => 'Current location';

  @override
  String get offlineMode => 'Offline mode';

  @override
  String get noDataAvailable => 'No data available';

  @override
  String get compassHeading => 'Heading';

  @override
  String get nearbyHazard => 'Hazard zone nearby';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return 'Hazard zone is ${distanceString}m away';
  }

  @override
  String get downloadingData => 'Downloading data...';

  @override
  String get downloadComplete => 'Download complete';

  @override
  String get downloadError => 'Failed to retrieve data';

  @override
  String get poiHospital => 'Hospital / Clinic';

  @override
  String get poiShelter => 'Evacuation shelter';

  @override
  String get poiStore => 'Convenience store / Supermarket';

  @override
  String get poiWater => 'Water supply';

  @override
  String get riskLow => 'Flood risk: Low';

  @override
  String get riskMedium => 'Flood risk: Medium';

  @override
  String get riskHigh => 'Flood risk: High';
}
