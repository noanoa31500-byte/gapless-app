// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => 'Cargando mapa...';

  @override
  String get hazardZone => 'Zona de peligro';

  @override
  String get safeRoute => 'Ruta segura';

  @override
  String get currentLocation => 'Ubicación actual';

  @override
  String get offlineMode => 'Modo sin conexión';

  @override
  String get noDataAvailable => 'No hay datos disponibles';

  @override
  String get compassHeading => 'Dirección';

  @override
  String get nearbyHazard => 'Zona de peligro cercana';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return 'La zona de peligro está a ${distanceString}m';
  }

  @override
  String get downloadingData => 'Descargando datos...';

  @override
  String get downloadComplete => 'Descarga completa';

  @override
  String get downloadError => 'Error al recuperar datos';

  @override
  String get poiHospital => 'Hospital / Clínica';

  @override
  String get poiShelter => 'Refugio de evacuación';

  @override
  String get poiStore => 'Tienda de conveniencia / Supermercado';

  @override
  String get poiWater => 'Punto de agua';

  @override
  String get riskLow => 'Riesgo de inundación: Bajo';

  @override
  String get riskMedium => 'Riesgo de inundación: Medio';

  @override
  String get riskHigh => 'Riesgo de inundación: Alto';
}
