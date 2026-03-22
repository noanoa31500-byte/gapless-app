import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_id.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_mn.dart';
import 'app_localizations_my.dart';
import 'app_localizations_ne.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_si.dart';
import 'app_localizations_th.dart';
import 'app_localizations_tl.dart';
import 'app_localizations_uz.dart';
import 'app_localizations_vi.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en'),
    Locale('es'),
    Locale('hi'),
    Locale('id'),
    Locale('ja'),
    Locale('ko'),
    Locale('mn'),
    Locale('my'),
    Locale('ne'),
    Locale('pt'),
    Locale('si'),
    Locale('th'),
    Locale('tl'),
    Locale('uz'),
    Locale('vi'),
    Locale('zh'),
    Locale('zh', 'TW')
  ];

  /// Application name. Do not translate.
  ///
  /// In en, this message translates to:
  /// **'GapLess'**
  String get appTitle;

  /// Shown while map data is being loaded
  ///
  /// In en, this message translates to:
  /// **'Loading map...'**
  String get loadingMap;

  /// Label for a flood/disaster hazard zone
  ///
  /// In en, this message translates to:
  /// **'Hazard zone'**
  String get hazardZone;

  /// Label for a safe evacuation route
  ///
  /// In en, this message translates to:
  /// **'Safe route'**
  String get safeRoute;

  /// Label for the user's current GPS location
  ///
  /// In en, this message translates to:
  /// **'Current location'**
  String get currentLocation;

  /// Indicator that the app is running without network
  ///
  /// In en, this message translates to:
  /// **'Offline mode'**
  String get offlineMode;

  /// Shown when no map or POI data is cached
  ///
  /// In en, this message translates to:
  /// **'No data available'**
  String get noDataAvailable;

  /// Compass bearing direction label
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get compassHeading;

  /// Alert shown when a hazard zone is within range
  ///
  /// In en, this message translates to:
  /// **'Hazard zone nearby'**
  String get nearbyHazard;

  /// Distance to the nearest hazard zone
  ///
  /// In en, this message translates to:
  /// **'Hazard zone is {distance}m away'**
  String distanceToHazard(int distance);

  /// Shown while map tile data is being downloaded
  ///
  /// In en, this message translates to:
  /// **'Downloading data...'**
  String get downloadingData;

  /// Shown when all tile data has finished downloading
  ///
  /// In en, this message translates to:
  /// **'Download complete'**
  String get downloadComplete;

  /// Shown when a download fails
  ///
  /// In en, this message translates to:
  /// **'Failed to retrieve data'**
  String get downloadError;

  /// POI category: medical facilities
  ///
  /// In en, this message translates to:
  /// **'Hospital / Clinic'**
  String get poiHospital;

  /// POI category: evacuation shelters
  ///
  /// In en, this message translates to:
  /// **'Evacuation shelter'**
  String get poiShelter;

  /// POI category: food supply stores
  ///
  /// In en, this message translates to:
  /// **'Convenience store / Supermarket'**
  String get poiStore;

  /// POI category: water supply points
  ///
  /// In en, this message translates to:
  /// **'Water supply'**
  String get poiWater;

  /// Hazard risk level 1
  ///
  /// In en, this message translates to:
  /// **'Flood risk: Low'**
  String get riskLow;

  /// Hazard risk level 2
  ///
  /// In en, this message translates to:
  /// **'Flood risk: Medium'**
  String get riskMedium;

  /// Hazard risk level 3
  ///
  /// In en, this message translates to:
  /// **'Flood risk: High'**
  String get riskHigh;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'bn',
        'en',
        'es',
        'hi',
        'id',
        'ja',
        'ko',
        'mn',
        'my',
        'ne',
        'pt',
        'si',
        'th',
        'tl',
        'uz',
        'vi',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'hi':
      return AppLocalizationsHi();
    case 'id':
      return AppLocalizationsId();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'mn':
      return AppLocalizationsMn();
    case 'my':
      return AppLocalizationsMy();
    case 'ne':
      return AppLocalizationsNe();
    case 'pt':
      return AppLocalizationsPt();
    case 'si':
      return AppLocalizationsSi();
    case 'th':
      return AppLocalizationsTh();
    case 'tl':
      return AppLocalizationsTl();
    case 'uz':
      return AppLocalizationsUz();
    case 'vi':
      return AppLocalizationsVi();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
