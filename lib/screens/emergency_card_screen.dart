import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/localization.dart';
import '../providers/user_profile_provider.dart';
import '../utils/styles.dart';
import '../widgets/safe_text.dart';

class EmergencyCardPage extends StatefulWidget {
  const EmergencyCardPage({super.key});

  @override
  State<EmergencyCardPage> createState() => _EmergencyCardPageState();
}

class _EmergencyCardPageState extends State<EmergencyCardPage> {

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<UserProfileProvider>();
    final profile = profileProvider.profile;

    return Scaffold(
      backgroundColor: const Color(0xFFB71C1C), // 災害時に目立つ深い赤 (A案)
      appBar: AppBar(
        title: SafeText(GapLessL10n.t('header_emergency_gear'), 
          style: safeStyle(size: 20, isBold: true, color: Colors.white)),
        backgroundColor: const Color(0xFFE53935),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: _buildIDSection(profile),
      ),
    );
  }

  Widget _buildIDSection(UserProfile profile) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SafeText(GapLessL10n.t('header_emergency_gear'), style: safeStyle(size: 14, isBold: true, color: const Color(0xFFB71C1C))),
              IconButton(
                icon: const Icon(Icons.edit, size: 20, color: Color(0xFFB71C1C)),
                onPressed: () => _showEditDialog(context),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          _buildInfoRow(GapLessL10n.t('label_name'), profile.name.isEmpty ? GapLessL10n.t('label_unknown') : profile.name),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildInfoRow(GapLessL10n.t('label_nation'), profile.nationality.isEmpty ? '-' : profile.nationality)),
              Expanded(child: _buildInfoRow(GapLessL10n.t('label_blood'), profile.bloodType.isEmpty ? '-' : profile.bloodType)),
            ],
          ),
          if (profile.allergies.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildInfoRow(GapLessL10n.t('label_allergies'), profile.allergies.join(', ')),
          ],
          if (profile.needs.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildInfoRow(GapLessL10n.t('label_needs'), profile.needs.join(', ')),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafeText(label, style: safeStyle(size: 11, color: Colors.grey[600]!)),
        SafeText(value, style: safeStyle(size: 16, isBold: true)),
      ],
    );
  }

  void _showEditDialog(BuildContext context) {
    final profile = context.read<UserProfileProvider>().profile;
    final nameCtrl = TextEditingController(text: profile.name)
      ..selection = TextSelection.fromPosition(TextPosition(offset: profile.name.length));
    final nationalityCtrl = TextEditingController(text: profile.nationality)
      ..selection = TextSelection.fromPosition(TextPosition(offset: profile.nationality.length));
    final bloodCtrl = TextEditingController(text: profile.bloodType)
      ..selection = TextSelection.fromPosition(TextPosition(offset: profile.bloodType.length));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Consumer<UserProfileProvider>(
              builder: (context, provider, _) {
                final profile = provider.profile;
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SafeText(GapLessL10n.t('label_edit'), 
                          style: safeStyle(size: 20, isBold: true)),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 16),
                    
                    // Name
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SafeText(GapLessL10n.t('label_name'), style: safeStyle(size: 12, color: Colors.grey[600]!, isBold: true)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: nameCtrl,
                          onChanged: (val) {
                            profile.name = val;
                            provider.saveProfile(profile);
                          },
                          style: safeStyle(size: 16),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFB71C1C), width: 2),
                            ),
                            hintText: GapLessL10n.t('hint_name'),
                            hintStyle: GapLessL10n.safeStyle(const TextStyle(fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: _buildEditField(GapLessL10n.t('label_nation'), nationalityCtrl, (val) {
                            profile.nationality = val;
                            provider.saveProfile(profile);
                          }),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildEditField(GapLessL10n.t('label_blood'), bloodCtrl, (val) {
                            profile.bloodType = val;
                            provider.saveProfile(profile);
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    _buildSectionLabel(GapLessL10n.t('label_allergies')),
                    Wrap(
                      spacing: 8,
                      children: ['Eggs', 'Peanuts', 'Milk', 'Seafood', 'Wheat'].map((allergy) {
                        final isSelected = profile.allergies.contains(allergy);
                        
                        // Map allergy ID to localization key
                        String label = allergy;
                        if (allergy == 'Eggs') label = GapLessL10n.t('allergy_eggs');
                        else if (allergy == 'Peanuts') label = GapLessL10n.t('allergy_peanuts');
                        else if (allergy == 'Milk') label = GapLessL10n.t('allergy_milk');
                        else if (allergy == 'Seafood') label = GapLessL10n.t('allergy_seafood');
                        else if (allergy == 'Wheat') label = GapLessL10n.t('allergy_wheat');

                        return FilterChip(
                          label: SafeText(label, style: safeStyle(size: 12)),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              profile.allergies.add(allergy);
                            } else {
                              profile.allergies.remove(allergy);
                            }
                            provider.saveProfile(profile);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    _buildSectionLabel(GapLessL10n.t('label_needs')),
                    Wrap(
                      spacing: 8,
                      children: ['Wheelchair', 'Visual Impairment', 'Hearing Impairment', 'Pregnancy', 'Infant', 'Halal'].map((need) {
                        final isSelected = profile.needs.contains(need);
                        
                        // Map need ID to localization key
                        String label = need;
                        if (need == 'Wheelchair') label = GapLessL10n.t('need_wheelchair');
                        else if (need == 'Visual Impairment') label = GapLessL10n.t('need_visual');
                        else if (need == 'Hearing Impairment') label = GapLessL10n.t('need_hearing');
                        else if (need == 'Pregnancy') label = GapLessL10n.t('need_pregnancy');
                        else if (need == 'Infant') label = GapLessL10n.t('need_infant');
                        else if (need == 'Halal') label = GapLessL10n.t('need_halal');

                        return FilterChip(
                          label: SafeText(label, style: safeStyle(size: 14)),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              profile.needs.add(need);
                            } else {
                              profile.needs.remove(need);
                            }
                            provider.saveProfile(profile);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 100),
                  ],
                );
              },
            ),
          );
        },
      ),
    ).then((_) {
      nameCtrl.dispose();
      nationalityCtrl.dispose();
      bloodCtrl.dispose();
    });
  }

  Widget _buildEditField(String label, TextEditingController controller, Function(String) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafeText(label, style: safeStyle(size: 12, color: Colors.grey[600]!, isBold: true)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: safeStyle(size: 16),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFB71C1C), width: 2),
            ),
            hintStyle: GapLessL10n.safeStyle(const TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SafeText(label, style: safeStyle(size: 14, isBold: true, color: Colors.grey[700]!)),
    );
  }
}

class EmergencyCardScreen extends EmergencyCardPage {
  const EmergencyCardScreen({super.key});
}