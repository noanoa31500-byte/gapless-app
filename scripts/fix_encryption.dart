import 'dart:io';
import 'package:encrypt/encrypt.dart';

void main() {
  // Prompt for key securely
  stdout.write('Enter 32-character Encryption Key: ');
  stdin.echoMode = false;
  final keyString = stdin.readLineSync()?.trim() ?? '';
  stdin.echoMode = true;
  stdout.writeln();

  if (keyString.length != 32) {
    print('❌ Error: Key length must be 32.');
    return;
  }

  final key = Key.fromUtf8(keyString);
  final fixedIv = IV.fromUtf8('8888888888888888');
  
  final oldIvCandidates = [
    IV.fromBase64('fnP8KgVNiT2i49y1F8BcLg=='),
    IV.fromBase64('lYqT3fDInS8b6z05rQvTfw=='),
  ];
  
  final encrypter = Encrypter(AES(key));
  final dataDir = Directory('assets/data');

  if (!dataDir.existsSync()) return;

  final files = dataDir.listSync();
  for (var file in files) {
    if (file is File && file.path.endsWith('.aes')) {
      final bytes = file.readAsBytesSync();
      
      // locations_merged.aes は常に強制的に最新座標で再構築する
      if (file.path.contains('locations_merged')) {
        print('🔄 Force reconstructing ${file.path} with latest coordinates (14.1109, 100.3977)...');
        _reconstructLocationsMerged(file, encrypter, fixedIv);
        continue;
      }

      // 他のファイルは、まず現在の固定IVで復号できるか試す
      try {
        encrypter.decrypt(Encrypted(bytes), iv: fixedIv);
        print('✅ ${file.path} is already correct. Skipping.');
        continue;
      } catch (_) {}

      // 候補のIVで復号を試みる
      bool recovered = false;
      for (var iv in oldIvCandidates) {
        try {
          final decrypted = encrypter.decrypt(Encrypted(bytes), iv: iv);
          final reEncrypted = encrypter.encrypt(decrypted, iv: fixedIv);
          file.writeAsBytesSync(reEncrypted.bytes);
          print('♻️ ${file.path} recovered and updated to fixed IV.');
          recovered = true;
          break;
        } catch (_) {}
      }

      if (!recovered) {
        print('❌ Failed to recover ${file.path}.');
      }
    }
  }
}

void _reconstructLocationsMerged(File file, Encrypter encrypter, IV iv) {
  const backupJson = '''
[
  {
    "id": "pcshs_pathum",
    "name": "Princess Chulabhorn Science High School Pathum Thani",
    "name:ja": "プリンセス・チュラポーン・サイエンス・ハイスクール・パトゥムターニー",
    "name:th": "โรงเรียนวิทยาศาสตร์จุฬาภรณราชวิทยาลัย ปทุมธานี",
    "lat": 14.1109,
    "lng": 100.3977,
    "type": "school",
    "region": "th_pathum",
    "verified": true
  },
  {
    "id": "osaki_city_hall",
    "name": "Osaki City Hall",
    "name:ja": "大崎市役所",
    "lat": 38.5772,
    "lng": 140.9559,
    "type": "gov",
    "region": "jp_osaki",
    "verified": true
  },
  {
    "id": "local_demo_school",
    "name": "School (Here)",
    "name:ja": "現在地の学校（デモ用）",
    "lat": 35.6586,
    "lng": 139.7454,
    "type": "school",
    "region": "jp_tokyo",
    "verified": true
  }
]
''';
  final encrypted = encrypter.encrypt(backupJson, iv: iv);
  file.writeAsBytesSync(encrypted.bytes);
  print('✅ locations_merged.aes reconstructed successfully with coordinate 14.1109, 100.3977.');
}
