// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Nepali (`ne`).
class AppLocalizationsNe extends AppLocalizations {
  AppLocalizationsNe([String locale = 'ne']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => 'नक्सा लोड हुँदैछ...';

  @override
  String get hazardZone => 'खतरा क्षेत्र';

  @override
  String get safeRoute => 'सुरक्षित मार्ग';

  @override
  String get currentLocation => 'हालको स्थान';

  @override
  String get offlineMode => 'अफलाइन मोड';

  @override
  String get noDataAvailable => 'डेटा उपलब्ध छैन';

  @override
  String get compassHeading => 'दिशा';

  @override
  String get nearbyHazard => 'नजिकमा खतरा क्षेत्र छ';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return 'खतरा क्षेत्र ${distanceString}m टाढा छ';
  }

  @override
  String get downloadingData => 'डेटा डाउनलोड हुँदैछ...';

  @override
  String get downloadComplete => 'डाउनलोड सम्पन्न';

  @override
  String get downloadError => 'डेटा प्राप्त गर्न असफल';

  @override
  String get poiHospital => 'अस्पताल / क्लिनिक';

  @override
  String get poiShelter => 'शरण स्थान';

  @override
  String get poiStore => 'सुविधा स्टोर / सुपरमार्केट';

  @override
  String get poiWater => 'पानी आपूर्ति';

  @override
  String get riskLow => 'बाढीको जोखिम: कम';

  @override
  String get riskMedium => 'बाढीको जोखिम: मध्यम';

  @override
  String get riskHigh => 'बाढीको जोखिम: उच्च';
}
