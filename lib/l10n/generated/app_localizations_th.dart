// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Thai (`th`).
class AppLocalizationsTh extends AppLocalizations {
  AppLocalizationsTh([String locale = 'th']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => 'กำลังโหลดแผนที่...';

  @override
  String get hazardZone => 'เขตอันตราย';

  @override
  String get safeRoute => 'เส้นทางปลอดภัย';

  @override
  String get currentLocation => 'ตำแหน่งปัจจุบัน';

  @override
  String get offlineMode => 'โหมดออฟไลน์';

  @override
  String get noDataAvailable => 'ไม่มีข้อมูล';

  @override
  String get compassHeading => 'ทิศทาง';

  @override
  String get nearbyHazard => 'มีเขตอันตรายอยู่ใกล้ๆ';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return 'เขตอันตรายอยู่ห่าง $distanceStringม.';
  }

  @override
  String get downloadingData => 'กำลังดาวน์โหลดข้อมูล...';

  @override
  String get downloadComplete => 'ดาวน์โหลดเสร็จสิ้น';

  @override
  String get downloadError => 'ไม่สามารถดึงข้อมูลได้';

  @override
  String get poiHospital => 'โรงพยาบาล / คลินิก';

  @override
  String get poiShelter => 'ศูนย์อพยพ';

  @override
  String get poiStore => 'ร้านสะดวกซื้อ / ซูเปอร์มาร์เก็ต';

  @override
  String get poiWater => 'จุดจ่ายน้ำ';

  @override
  String get riskLow => 'ความเสี่ยงน้ำท่วม: ต่ำ';

  @override
  String get riskMedium => 'ความเสี่ยงน้ำท่วม: ปานกลาง';

  @override
  String get riskHigh => 'ความเสี่ยงน้ำท่วม: สูง';
}
