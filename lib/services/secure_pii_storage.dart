import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PII（血液型・アレルギー・要配慮事項・最終位置）を Keychain/Keystore に保存。
/// 旧 SharedPreferences からの自動マイグレーション付き。
class SecurePiiStorage {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kName = 'pii_user_name';
  static const _kBlood = 'pii_user_blood';
  static const _kAllergies = 'pii_user_allergies';
  static const _kNeeds = 'pii_user_special_needs';
  static const _kLastLat = 'pii_last_lat';
  static const _kLastLng = 'pii_last_lng';
  static const _kMigrated = 'pii_migrated_v1';

  static Future<void> migrateFromPrefsIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kMigrated) == true) return;

    final name = prefs.getString('user_name');
    final blood = prefs.getString('user_blood');
    final allergies = prefs.getStringList('user_allergies');
    final needs = prefs.getStringList('user_special_needs');
    final lat = prefs.getDouble('last_lat');
    final lng = prefs.getDouble('last_lng');

    if (name != null) await _storage.write(key: _kName, value: name);
    if (blood != null) await _storage.write(key: _kBlood, value: blood);
    if (allergies != null) {
      await _storage.write(key: _kAllergies, value: jsonEncode(allergies));
    }
    if (needs != null) {
      await _storage.write(key: _kNeeds, value: jsonEncode(needs));
    }
    if (lat != null)
      await _storage.write(key: _kLastLat, value: lat.toString());
    if (lng != null)
      await _storage.write(key: _kLastLng, value: lng.toString());

    await prefs.remove('user_name');
    await prefs.remove('user_blood');
    await prefs.remove('user_allergies');
    await prefs.remove('user_special_needs');
    await prefs.remove('last_lat');
    await prefs.remove('last_lng');
    await prefs.setBool(_kMigrated, true);
  }

  static Future<String?> getName() => _storage.read(key: _kName);
  static Future<void> setName(String v) =>
      _storage.write(key: _kName, value: v);

  static Future<String?> getBlood() => _storage.read(key: _kBlood);
  static Future<void> setBlood(String v) =>
      _storage.write(key: _kBlood, value: v);

  static Future<List<String>> getAllergies() async {
    final raw = await _storage.read(key: _kAllergies);
    if (raw == null) return [];
    return List<String>.from(jsonDecode(raw) as List);
  }

  static Future<void> setAllergies(List<String> v) =>
      _storage.write(key: _kAllergies, value: jsonEncode(v));

  static Future<List<String>> getNeeds() async {
    final raw = await _storage.read(key: _kNeeds);
    if (raw == null) return [];
    return List<String>.from(jsonDecode(raw) as List);
  }

  static Future<void> setNeeds(List<String> v) =>
      _storage.write(key: _kNeeds, value: jsonEncode(v));

  static Future<double?> getLastLat() async {
    final v = await _storage.read(key: _kLastLat);
    return v == null ? null : double.tryParse(v);
  }

  static Future<double?> getLastLng() async {
    final v = await _storage.read(key: _kLastLng);
    return v == null ? null : double.tryParse(v);
  }

  static Future<void> setLastLatLng(double lat, double lng) async {
    await _storage.write(key: _kLastLat, value: lat.toString());
    await _storage.write(key: _kLastLng, value: lng.toString());
  }

  static Future<void> clearLastLatLng() async {
    await _storage.delete(key: _kLastLat);
    await _storage.delete(key: _kLastLng);
  }
}
