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
  int count = 0;

  for (var file in files) {
    if (file is File && file.path.endsWith('.aes')) {
      print('Decrypting ${file.path}...');
      
      try {
        final encryptedBytes = file.readAsBytesSync();
        final decrypted = encrypter.decrypt(Encrypted(encryptedBytes), iv: iv);
        
        // Determine original extension based on content or filename heuristic
        // Default to .json as it's most common for this app
        String newPath = file.path.replaceAll('.aes', '.json');
        
        // Heuristic: Check if filename ends with _th or similar that might imply geojson if distinct
        // But the previous encrypt script mapped (json|geojson|csv) -> .aes
        // Since we don't know for sure which one it was, .json is the safest valid JSON extension.
        
        final outputFile = File(newPath);
        outputFile.writeAsStringSync(decrypted);
        
        // Delete the .aes file
        file.deleteSync();
        print('Restored: $newPath (AES deleted)');
        count++;
      } catch (e) {
        print('Failed to decrypt ${file.path}: $e');
      }
    }
  }

  print('\nTotal restored: $count files.');
}
