import 'dart:io';
import 'package:encrypt/encrypt.dart';

void main() {
  // Prompt for key securely
  stdout.write('Enter 32-character Encryption Key: ');
  stdin.echoMode = false;
  final keyString = stdin.readLineSync()?.trim() ?? '';
  stdin.echoMode = true;
  stdout.writeln(); // New line after hidden input

  if (keyString.length != 32) {
    print('❌ Error: Key must be exactly 32 characters long. (Currently: ${keyString.length})');
    return;
  }

  final key = Key.fromUtf8(keyString);
  final iv = IV.fromUtf8('8888888888888888');
  final encrypter = Encrypter(AES(key));

  final dataDir = Directory('assets/data');
  if (!dataDir.existsSync()) {
    print('Data directory not found!');
    return;
  }

  final files = dataDir.listSync();
  for (var file in files) {
    if (file is File && 
        (file.path.endsWith('.json') || file.path.endsWith('.geojson') || file.path.endsWith('.csv')) &&
        !file.path.endsWith('.aes')) {
      
      print('Encrypting ${file.path}...');
      final plainText = file.readAsStringSync();
      final encrypted = encrypter.encrypt(plainText, iv: iv);
      
      final outPath = file.path.replaceAll(RegExp(r'\.(json|geojson|csv)$'), '.aes');
      final outputFile = File(outPath);
      outputFile.writeAsBytesSync(encrypted.bytes);
      
      // 元のファイルを削除
      file.deleteSync();
      print('Done: $outPath (Original deleted)');
    }
  }

  print('\nAll data files encrypted successfully.');
  print('Key: ${key.base64}');
  print('IV: ${iv.base64}');
}
