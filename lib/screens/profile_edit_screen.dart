import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/styles.dart';
import '../utils/localization.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _nameController = TextEditingController();
  final _bloodController = TextEditingController();
  
  // チップ選択の状態管理
  final List<String> _selectedAllergies = [];
  final List<String> _selectedSpecialNeeds = [];

  final List<String> _allergyOptions = ['Eggs', 'Peanuts', 'Milk', 'Seafood', 'Wheat'];
  final List<String> _specialNeedsOptions = [
    'Wheelchair', 'Visual Impairment', 'Hearing Impairment', 'Pregnancy', 'Infant', 'Halal'
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('user_name') ?? '';
      _bloodController.text = prefs.getString('user_blood') ?? '';
      
      // リスト形式で保存されている前提（またはカンマ区切り）
      final savedAllergies = prefs.getStringList('user_allergies') ?? [];
      _selectedAllergies.clear();
      _selectedAllergies.addAll(savedAllergies);

      final savedSpecialNeeds = prefs.getStringList('user_special_needs') ?? [];
      _selectedSpecialNeeds.clear();
      _selectedSpecialNeeds.addAll(savedSpecialNeeds);
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameController.text);
    await prefs.setString('user_blood', _bloodController.text);
    await prefs.setStringList('user_allergies', _selectedAllergies);
    await prefs.setStringList('user_special_needs', _selectedSpecialNeeds);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.t('profile_saved'))),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.t('profile_settings'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController, 
              decoration: InputDecoration(labelText: AppLocalizations.t('label_name')),
              style: safeStyle(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bloodController, 
              decoration: InputDecoration(labelText: AppLocalizations.t('label_blood')),
              style: safeStyle(),
            ),
            const SizedBox(height: 24),
            
            _buildSectionTitle(AppLocalizations.t('label_allergies')),
            _buildChipGroup(_allergyOptions, _selectedAllergies),
            
            const SizedBox(height: 24),
            
            _buildSectionTitle(AppLocalizations.t('label_needs')),
            _buildChipGroup(_specialNeedsOptions, _selectedSpecialNeeds),
            
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveData,
                child: Text(AppLocalizations.t('profile_save')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: safeStyle(size: 16, isBold: true, color: Colors.grey.shade700),
      ),
    );
  }

  Widget _buildChipGroup(List<String> options, List<String> selectedList) {
    return Wrap(
      spacing: 8.0,
      runSpacing: 4.0,
      children: options.map((option) {
        final isSelected = selectedList.contains(option);
        return FilterChip(
          label: Text(option),
          selected: isSelected,
          onSelected: (bool selected) {
            setState(() {
              if (selected) {
                selectedList.add(option);
              } else {
                selectedList.remove(option);
              }
            });
          },
          selectedColor: Colors.red.shade100,
          checkmarkColor: Colors.red.shade900,
          labelStyle: safeStyle(
            size: 14, 
            isBold: isSelected,
            color: isSelected ? Colors.red.shade900 : Colors.black87,
          ),
          shape: StadiumBorder(
            side: BorderSide(
              color: isSelected ? Colors.red.shade900 : Colors.grey.shade400,
              width: 1,
            ),
          ),
          backgroundColor: Colors.white,
        );
      }).toList(),
    );
  }
}