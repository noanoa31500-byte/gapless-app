// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => 'Memuat peta...';

  @override
  String get hazardZone => 'Zona bahaya';

  @override
  String get safeRoute => 'Rute aman';

  @override
  String get currentLocation => 'Lokasi saat ini';

  @override
  String get offlineMode => 'Mode offline';

  @override
  String get noDataAvailable => 'Tidak ada data tersedia';

  @override
  String get compassHeading => 'Arah';

  @override
  String get nearbyHazard => 'Ada zona bahaya di sekitar';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return 'Zona bahaya berjarak ${distanceString}m';
  }

  @override
  String get downloadingData => 'Mengunduh data...';

  @override
  String get downloadComplete => 'Unduhan selesai';

  @override
  String get downloadError => 'Gagal mengambil data';

  @override
  String get poiHospital => 'Rumah sakit / Klinik';

  @override
  String get poiShelter => 'Tempat pengungsian';

  @override
  String get poiStore => 'Minimarket / Supermarket';

  @override
  String get poiWater => 'Titik pasokan air';

  @override
  String get riskLow => 'Risiko banjir: Rendah';

  @override
  String get riskMedium => 'Risiko banjir: Sedang';

  @override
  String get riskHigh => 'Risiko banjir: Tinggi';
}
