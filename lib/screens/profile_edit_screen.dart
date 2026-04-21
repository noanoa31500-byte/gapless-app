import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/secure_pii_storage.dart';
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
    'Eggs': 'allergy_eggs',
    'Peanuts': 'allergy_peanuts',
    'Milk': 'allergy_milk',
    'Seafood': 'allergy_seafood',
    'Wheat': 'allergy_wheat',
  };
  static const Map<String, String> _needsKeyMap = {
    'Wheelchair': 'need_wheelchair',
    'Visual Impairment': 'need_visual',
    'Hearing Impairment': 'need_hearing',
    'Pregnancy': 'need_pregnancy',
    'Infant': 'need_infant',
    'Halal': 'need_halal',
  };
  final List<String> _allergyOptions = [
    'Eggs',
    'Peanuts',
    'Milk',
    'Seafood',
    'Wheat'
  ];
  final List<String> _specialNeedsOptions = [
    'Wheelchair',
    'Visual Impairment',
    'Hearing Impairment',
    'Pregnancy',
    'Infant',
    'Halal'
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
    final name = await SecurePiiStorage.getName() ?? '';
    final blood = await SecurePiiStorage.getBlood() ?? '';
    final allergies = await SecurePiiStorage.getAllergies();
    final needs = await SecurePiiStorage.getNeeds();
    if (!mounted) return;
    setState(() {
      _nameController.text = name;
      _bloodController.text = blood;
      _selectedAllergies
        ..clear()
        ..addAll(allergies);
      _selectedSpecialNeeds
        ..clear()
        ..addAll(needs);
    });
  }

  Future<void> _saveData() async {
    await SecurePiiStorage.setName(_nameController.text);
    await SecurePiiStorage.setBlood(_bloodController.text);
    await SecurePiiStorage.setAllergies(_selectedAllergies);
    await SecurePiiStorage.setNeeds(_selectedSpecialNeeds);

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
              decoration:
                  InputDecoration(labelText: GapLessL10n.t('label_name')),
              style: safeStyle(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bloodController,
              decoration:
                  InputDecoration(labelText: GapLessL10n.t('label_blood')),
              style: safeStyle(),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle(GapLessL10n.t('label_allergies')),
            _buildChipGroup(
                _allergyOptions, _selectedAllergies, _allergyKeyMap),
            const SizedBox(height: 24),
            _buildSectionTitle(GapLessL10n.t('label_needs')),
            _buildChipGroup(
                _specialNeedsOptions, _selectedSpecialNeeds, _needsKeyMap),
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

  Widget _buildChipGroup(List<String> options, List<String> selectedList,
      Map<String, String> keyMap) {
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
