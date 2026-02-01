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

  // Handle key input (previously was Base64 encoded in this file, but now accepting raw string to match others)
  // If user inputs the raw 32 chars, we use fromUtf8.
  final key = Key.fromUtf8(keyString);
  // 13:29頃のログから推測されるIV
  final oldIv = IV.fromBase64('fnP8KgVNiT2i49y1F8BcLg==');
  
  // 新しい固定IV
  final newIv = IV.fromUtf8('8888888888888888');
  
  final encrypter = Encrypter(AES(key));
  final file = File('assets/data/locations_merged.aes');

  if (!file.existsSync()) {
    print('File not found');
    return;
  }

  print('Attempting to recover ${file.path}...');
  
  try {
    final encryptedBytes = file.readAsBytesSync();
    final decryptedPlainText = encrypter.decrypt(Encrypted(encryptedBytes), iv: oldIv);
    
    // 新しいIVで再暗号化
    final newEncrypted = encrypter.encrypt(decryptedPlainText, iv: newIv);
    file.writeAsBytesSync(newEncrypted.bytes);
    
    print('✅ Successfully recovered and re-encrypted with FIXED IV.');
  } catch (e) {
    print('❌ Failed to decrypt with IV: ${oldIv.base64}. Error: $e');
  }
}
