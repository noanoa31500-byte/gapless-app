// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tagalog (`tl`).
class AppLocalizationsTl extends AppLocalizations {
  AppLocalizationsTl([String locale = 'tl']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => 'Naglo-load ng mapa...';

  @override
  String get hazardZone => 'Lugar ng panganib';

  @override
  String get safeRoute => 'Ligtas na ruta';

  @override
  String get currentLocation => 'Kasalukuyang lokasyon';

  @override
  String get offlineMode => 'Offline na mode';

  @override
  String get noDataAvailable => 'Walang available na data';

  @override
  String get compassHeading => 'Direksyon';

  @override
  String get nearbyHazard => 'May lugar ng panganib sa malapit';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return 'Ang lugar ng panganib ay ${distanceString}m ang layo';
  }

  @override
  String get downloadingData => 'Nagda-download ng data...';

  @override
  String get downloadComplete => 'Kumpleto na ang download';

  @override
  String get downloadError => 'Nabigo sa pagkuha ng data';

  @override
  String get poiHospital => 'Ospital / Klinika';

  @override
  String get poiShelter => 'Evacuation shelter';

  @override
  String get poiStore => 'Convenience store / Supermarket';

  @override
  String get poiWater => 'Pinagkukunan ng tubig';

  @override
  String get riskLow => 'Panganib ng baha: Mababa';

  @override
  String get riskMedium => 'Panganib ng baha: Katamtaman';

  @override
  String get riskHigh => 'Panganib ng baha: Mataas';
}
