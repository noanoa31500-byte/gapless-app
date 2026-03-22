
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfile {
  String name;
  String nationality;
  String bloodType;
  String birthDate;
  String medications;
  List<String> allergies;
  List<String> needs;

  UserProfile({
    this.name = '',
    this.nationality = '',
    this.bloodType = '',
    this.birthDate = '',
    this.medications = '',
    this.allergies = const [],
    this.needs = const [],
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'nationality': nationality,
    'bloodType': bloodType,
    'birthDate': birthDate,
    'medications': medications,
    'allergies': allergies,
    'needs': needs,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] ?? '',
      nationality: json['nationality'] ?? '',
      bloodType: json['bloodType'] ?? '',
      birthDate: json['birthDate'] ?? '',
      medications: json['medications'] ?? '',
      allergies: List<String>.from(json['allergies'] ?? []),
      needs: List<String>.from(json['needs'] ?? []),
    );
  }
}

class UserProfileProvider with ChangeNotifier {
  UserProfile _profile = UserProfile();
  static const String _storageKey = 'user_profile_data';

  UserProfile get profile => _profile;

  UserProfileProvider() {
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString != null) {
      try {
        final Map<String, dynamic> jsonMap = json.decode(jsonString);
        _profile = UserProfile.fromJson(jsonMap);
        notifyListeners();
      } catch (e) {
        debugPrint('Error loading profile: $e');
      }
    }
  }

  Future<void> saveProfile(UserProfile newProfile) async {
    _profile = newProfile;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(_profile.toJson());
    await prefs.setString(_storageKey, jsonString);
  }

  // Helpers for modifying specific fields if needed
  Future<void> updateName(String name) async {
    _profile.name = name;
    await saveProfile(_profile);
  }
}
