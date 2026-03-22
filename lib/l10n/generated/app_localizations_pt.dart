// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => 'Carregando mapa...';

  @override
  String get hazardZone => 'Zona de risco';

  @override
  String get safeRoute => 'Rota segura';

  @override
  String get currentLocation => 'Localização atual';

  @override
  String get offlineMode => 'Modo offline';

  @override
  String get noDataAvailable => 'Sem dados disponíveis';

  @override
  String get compassHeading => 'Direção';

  @override
  String get nearbyHazard => 'Zona de risco próxima';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return 'Zona de risco a ${distanceString}m';
  }

  @override
  String get downloadingData => 'Baixando dados...';

  @override
  String get downloadComplete => 'Download concluído';

  @override
  String get downloadError => 'Falha ao recuperar dados';

  @override
  String get poiHospital => 'Hospital / Clínica';

  @override
  String get poiShelter => 'Abrigo de evacuação';

  @override
  String get poiStore => 'Loja de conveniência / Supermercado';

  @override
  String get poiWater => 'Ponto de abastecimento de água';

  @override
  String get riskLow => 'Risco de inundação: Baixo';

  @override
  String get riskMedium => 'Risco de inundação: Médio';

  @override
  String get riskHigh => 'Risco de inundação: Alto';
}
