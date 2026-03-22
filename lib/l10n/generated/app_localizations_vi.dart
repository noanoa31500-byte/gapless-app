// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => 'Đang tải bản đồ...';

  @override
  String get hazardZone => 'Khu vực nguy hiểm';

  @override
  String get safeRoute => 'Tuyến đường an toàn';

  @override
  String get currentLocation => 'Vị trí hiện tại';

  @override
  String get offlineMode => 'Chế độ ngoại tuyến';

  @override
  String get noDataAvailable => 'Không có dữ liệu';

  @override
  String get compassHeading => 'Hướng';

  @override
  String get nearbyHazard => 'Có khu vực nguy hiểm gần đây';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return 'Khu vực nguy hiểm cách ${distanceString}m';
  }

  @override
  String get downloadingData => 'Đang tải dữ liệu...';

  @override
  String get downloadComplete => 'Tải xuống hoàn tất';

  @override
  String get downloadError => 'Lấy dữ liệu thất bại';

  @override
  String get poiHospital => 'Bệnh viện / Phòng khám';

  @override
  String get poiShelter => 'Nơi trú ẩn';

  @override
  String get poiStore => 'Cửa hàng tiện lợi / Siêu thị';

  @override
  String get poiWater => 'Điểm cấp nước';

  @override
  String get riskLow => 'Nguy cơ lũ lụt: Thấp';

  @override
  String get riskMedium => 'Nguy cơ lũ lụt: Trung bình';

  @override
  String get riskHigh => 'Nguy cơ lũ lụt: Cao';
}
