import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/styles.dart';
import '../utils/localization.dart';
import '../providers/language_provider.dart';

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

  // Stored IDs → localization key mapping
  static const Map<String, String> _allergyKeyMap = {
    'Eggs':    'allergy_eggs',
    'Peanuts': 'allergy_peanuts',
    'Milk':    'allergy_milk',
    'Seafood': 'allergy_seafood',
    'Wheat':   'allergy_wheat',
  };
  static const Map<String, String> _needsKeyMap = {
    'Wheelchair':         'need_wheelchair',
    'Visual Impairment':  'need_visual',
    'Hearing Impairment': 'need_hearing',
    'Pregnancy':          'need_pregnancy',
    'Infant':             'need_infant',
    'Halal':              'need_halal',
  };
  final List<String> _allergyOptions = ['Eggs', 'Peanuts', 'Milk', 'Seafood', 'Wheat'];
  final List<String> _specialNeedsOptions = [
    'Wheelchair', 'Visual Impairment', 'Hearing Impairment', 'Pregnancy', 'Infant', 'Halal'
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bloodController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
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
        SnackBar(content: Text(GapLessL10n.t('profile_saved'))),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // 言語変更時に再描画
    return Scaffold(
      appBar: AppBar(title: Text(GapLessL10n.t('profile_settings'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController, 
              decoration: InputDecoration(labelText: GapLessL10n.t('label_name')),
              style: safeStyle(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bloodController, 
              decoration: InputDecoration(labelText: GapLessL10n.t('label_blood')),
              style: safeStyle(),
            ),
            const SizedBox(height: 24),
            
            _buildSectionTitle(GapLessL10n.t('label_allergies')),
            _buildChipGroup(_allergyOptions, _selectedAllergies, _allergyKeyMap),
            
            const SizedBox(height: 24),
            
            _buildSectionTitle(GapLessL10n.t('label_needs')),
            _buildChipGroup(_specialNeedsOptions, _selectedSpecialNeeds, _needsKeyMap),
            
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveData,
                child: Text(GapLessL10n.t('profile_save')),
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

  Widget _buildChipGroup(List<String> options, List<String> selectedList, Map<String, String> keyMap) {
    return Wrap(
      spacing: 8.0,
      runSpacing: 4.0,
      children: options.map((option) {
        final isSelected = selectedList.contains(option);
        final l10nKey = keyMap[option];
        final label = l10nKey != null ? GapLessL10n.t(l10nKey) : option;
        return FilterChip(
          label: Text(label),
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