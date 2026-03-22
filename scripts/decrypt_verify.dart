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
  final iv = IV.fromUtf8('8888888888888888');
  final encrypter = Encrypter(AES(key));

  final file = File('assets/data/hazard_thailand.aes');
  if (!file.existsSync()) {
    print('File not found');
    return;
  }

  try {
    final bytes = file.readAsBytesSync();
    final decrypted = encrypter.decrypt(Encrypted(bytes), iv: iv);
    print('--- Decrypted Content ---');
    print(decrypted.substring(0, 1000)); // 先頭1000文字
    print('--- End ---');
  } catch (e) {
    print('Error decrypting: $e');
  }
}
