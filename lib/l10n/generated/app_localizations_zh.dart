// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => '正在加载地图...';

  @override
  String get hazardZone => '危险区域';

  @override
  String get safeRoute => '安全路线';

  @override
  String get currentLocation => '当前位置';

  @override
  String get offlineMode => '离线模式';

  @override
  String get noDataAvailable => '暂无数据';

  @override
  String get compassHeading => '方向';

  @override
  String get nearbyHazard => '附近有危险区域';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return '距离危险区域${distanceString}m';
  }

  @override
  String get downloadingData => '正在下载数据...';

  @override
  String get downloadComplete => '下载完成';

  @override
  String get downloadError => '数据获取失败';

  @override
  String get poiHospital => '医院 / 诊所';

  @override
  String get poiShelter => '避难所';

  @override
  String get poiStore => '便利店 / 超市';

  @override
  String get poiWater => '供水点';

  @override
  String get riskLow => '洪水风险：低';

  @override
  String get riskMedium => '洪水风险：中';

  @override
  String get riskHigh => '洪水风险：高';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get appTitle => 'GapLess';

  @override
  String get loadingMap => '正在載入地圖...';

  @override
  String get hazardZone => '危險區域';

  @override
  String get safeRoute => '安全路線';

  @override
  String get currentLocation => '目前位置';

  @override
  String get offlineMode => '離線模式';

  @override
  String get noDataAvailable => '沒有可用資料';

  @override
  String get compassHeading => '方位';

  @override
  String get nearbyHazard => '附近有危險區域';

  @override
  String distanceToHazard(int distance) {
    final intl.NumberFormat distanceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String distanceString = distanceNumberFormat.format(distance);

    return '距離危險區域${distanceString}m';
  }

  @override
  String get downloadingData => '正在下載資料...';

  @override
  String get downloadComplete => '下載完成';

  @override
  String get downloadError => '資料獲取失敗';

  @override
  String get poiHospital => '醫院 / 診所';

  @override
  String get poiShelter => '避難所';

  @override
  String get poiStore => '便利商店 / 超市';

  @override
  String get poiWater => '供水點';

  @override
  String get riskLow => '淹水風險：低';

  @override
  String get riskMedium => '淹水風險：中';

  @override
  String get riskHigh => '淹水風險：高';
}
