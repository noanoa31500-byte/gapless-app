// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => 'मानचित्र लोड हो रहा है...';

  @override
  String get hazardZone => 'खतरा क्षेत्र';

  @override
  String get safeRoute => 'सुरक्षित मार्ग';

  @override
  String get currentLocation => 'वर्तमान स्थान';

  @override
  String get offlineMode => 'ऑफलाइन मोड';

  @override
  String get noDataAvailable => 'कोई डेटा उपलब्ध नहीं';

  @override
  String get compassHeading => 'दिशा';

  @override
  String get nearbyHazard => 'पास में खतरा क्षेत्र है';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return 'खतरा क्षेत्र $distanceStringमी दूर है';
  }

  @override
  String get downloadingData => 'डेटा डाउनलोड हो रहा है...';

  @override
  String get downloadComplete => 'डाउनलोड पूर्ण';

  @override
  String get downloadError => 'डेटा प्राप्त करने में विफल';

  @override
  String get poiHospital => 'अस्पताल / क्लिनिक';

  @override
  String get poiShelter => 'निकासी आश्रय';

  @override
  String get poiStore => 'सुविधा स्टोर / सुपरमार्केट';

  @override
  String get poiWater => 'जल आपूर्ति';

  @override
  String get riskLow => 'बाढ़ जोखिम: कम';

  @override
  String get riskMedium => 'बाढ़ जोखिम: मध्यम';

  @override
  String get riskHigh => 'बाढ़ जोखिम: उच्च';
}
