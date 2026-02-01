
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';

class ShelterDataService {
  // CSVを読み込んでJSON形式のリストに変換する関数
  Future<List<Map<String, dynamic>>> loadSheltersFromCsv() async {
    try {
      // 1. CSVファイルを文字列として読み込む
      final rawData = await rootBundle.loadString('assets/data/osaki_shelters.csv');
      
      // 2. CSVをリストに変換 (カンマ区切りの場合)
      List<List<dynamic>> listData = const CsvToListConverter().convert(rawData);
      
      // 3. ヘッダー（1行目）を除いて、Map形式（JSONライク）に変換
      List<Map<String, dynamic>> shelters = [];
      for (var i = 1; i < listData.length; i++) {
        var row = listData[i];
        shelters.add({
          "name": row[0],         // CSVの1列目: 名前
          "lat": row[1],          // 2列目: 緯度
          "lon": row[2],          // 3列目: 経度
          "is_designated": row[3] == 'designated_emergency_evacuation_site', // 指定避難所判定
          "type": "school",       // 学校施設としてのタグ
        });
      }
      
      print('--- [DEBUG] ${shelters.length}件の避難所をCSVから読み込みました ---');
      return shelters;
    } catch (e) {
      print('--- [DEBUG] CSV読み込みエラー: $e ---');
      return [];
    }
  }
}