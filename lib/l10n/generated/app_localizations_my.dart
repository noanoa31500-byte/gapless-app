// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Burmese (`my`).
class AppLocalizationsMy extends AppLocalizations {
  AppLocalizationsMy([String locale = 'my']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => 'မြေပုံ ဖွင့်နေသည်...';

  @override
  String get hazardZone => 'အန္တရာယ် ဇုန်';

  @override
  String get safeRoute => 'လုံခြုံသော လမ်းကြောင်း';

  @override
  String get currentLocation => 'လက်ရှိ တည်နေရာ';

  @override
  String get offlineMode => 'အွန်လိုင်းမဲ့ မုဒ်';

  @override
  String get noDataAvailable => 'ဒေတာ မရှိပါ';

  @override
  String get compassHeading => 'ဦးတည်ရာ';

  @override
  String get nearbyHazard => 'အနီးတွင် အန္တရာယ် ဇုန် ရှိသည်';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return 'အန္တရာယ် ဇုန် $distanceStringမီတာ ဝေးသည်';
  }

  @override
  String get downloadingData => 'ဒေတာ ဒေါင်းလုဒ် ဆွဲနေသည်...';

  @override
  String get downloadComplete => 'ဒေါင်းလုဒ် ပြီးမြောက်သည်';

  @override
  String get downloadError => 'ဒေတာ ရယူ၍ မရပါ';

  @override
  String get poiHospital => 'ဆေးရုံ / ဆေးခန်း';

  @override
  String get poiShelter => 'ဒုက္ခသည် စခန်း';

  @override
  String get poiStore => 'လက်ဖက်ရည်ဆိုင် / စူပါမားကတ်';

  @override
  String get poiWater => 'ရေ ထောက်ပံ့ ရေး';

  @override
  String get riskLow => 'ရေကြီး အန္တရာယ်: နိမ့်';

  @override
  String get riskMedium => 'ရေကြီး အန္တရာယ်: အလတ်';

  @override
  String get riskHigh => 'ရေကြီး အန္တရာယ်: မြင့်';
}
