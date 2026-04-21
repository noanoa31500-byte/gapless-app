import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/localization.dart';
import '../providers/user_profile_provider.dart';
import '../providers/language_provider.dart';
import '../utils/styles.dart';
import '../widgets/safe_text.dart';

// ─────────────────────────────────────────────────────────────────────────────
// チップデータ定義（言語コード触れず、インライン多言語ラベル）
// ─────────────────────────────────────────────────────────────────────────────

const _kRed     = Color(0xFFB71C1C);
const _kRedLight = Color(0xFFE53935);
const _kSurface = Color(0xFFF8F9FE);

class _ChipItem {
  final String id;
  final String label; // displayed as-is (bilingual inline)
  final IconData icon;
  const _ChipItem(this.id, this.label, this.icon);
}

const _allergyItems = [
  _ChipItem('Eggs',       'allergy_eggs',      Icons.egg_outlined),
  _ChipItem('Peanuts',    'allergy_peanuts',   Icons.grass),
  _ChipItem('Milk',       'allergy_milk',      Icons.water_drop_outlined),
  _ChipItem('Seafood',    'allergy_seafood',   Icons.set_meal_outlined),
  _ChipItem('Wheat',      'allergy_wheat',     Icons.grain),
  _ChipItem('Soy',        'allergy_soy',       Icons.spa_outlined),
  _ChipItem('Tree Nuts',  'allergy_tree_nuts', Icons.forest_outlined),
  _ChipItem('Shellfish',  'allergy_shellfish', Icons.water),
  _ChipItem('Gluten',     'allergy_gluten',    Icons.no_meals_outlined),
  _ChipItem('Sesame',     'allergy_sesame',    Icons.circle_outlined),
  _ChipItem('Alcohol',    'allergy_alcohol',   Icons.local_bar_outlined),
  _ChipItem('Latex',      'allergy_latex',     Icons.healing_outlined),
];

const _needItems = [
  _ChipItem('Wheelchair',         'need_wheelchair',     Icons.accessible),
  _ChipItem('Visual Impairment',  'need_visual',         Icons.visibility_off_outlined),
  _ChipItem('Hearing Impairment', 'need_hearing',        Icons.hearing_disabled_outlined),
  _ChipItem('Pregnancy',          'need_pregnancy',      Icons.pregnant_woman),
  _ChipItem('Infant',             'need_infant',         Icons.child_care_outlined),
  _ChipItem('Elderly',            'need_elderly',        Icons.elderly_outlined),
  _ChipItem('Halal',              'need_halal',          Icons.cruelty_free_outlined),
  _ChipItem('Kosher',             'need_kosher',         Icons.star_outline),
  _ChipItem('Vegan',              'need_vegan',          Icons.eco_outlined),
  _ChipItem('Pet',                'need_pet',            Icons.pets_outlined),
  _ChipItem('Service Animal',     'need_service_animal', Icons.support_agent_outlined),
  _ChipItem('Oxygen',             'need_oxygen',         Icons.air_outlined),
  _ChipItem('Dialysis',           'need_dialysis',       Icons.medical_services_outlined),
];

const _conditionItems = [
  _ChipItem('Hypertension',   'cond_hypertension',  Icons.monitor_heart_outlined),
  _ChipItem('Heart Disease',  'cond_heart_disease', Icons.favorite_border),
  _ChipItem('Diabetes',       'cond_diabetes',      Icons.bloodtype_outlined),
  _ChipItem('Asthma',         'cond_asthma',        Icons.air),
  _ChipItem('Epilepsy',       'cond_epilepsy',      Icons.bolt_outlined),
  _ChipItem('Dementia',       'cond_dementia',      Icons.psychology_outlined),
  _ChipItem('Mental Health',  'cond_mental_health', Icons.self_improvement_outlined),
  _ChipItem('Kidney Disease', 'cond_kidney_disease',Icons.health_and_safety_outlined),
  _ChipItem('Stroke History', 'cond_stroke',        Icons.emergency_outlined),
  _ChipItem('Cancer',         'cond_cancer',        Icons.medication_outlined),
];

const _languageItems = [
  _ChipItem('Japanese',   'lang_japanese',   Icons.language),
  _ChipItem('English',    'lang_english',    Icons.language),
  _ChipItem('French',     'lang_french',     Icons.language),
  _ChipItem('Chinese',    'lang_chinese',    Icons.language),
  _ChipItem('Korean',     'lang_korean',     Icons.language),
  _ChipItem('Spanish',    'lang_spanish',    Icons.language),
  _ChipItem('Arabic',     'lang_arabic',     Icons.language),
  _ChipItem('Portuguese', 'lang_portuguese', Icons.language),
  _ChipItem('Thai',       'lang_thai',       Icons.language),
  _ChipItem('Vietnamese', 'lang_vietnamese', Icons.language),
  _ChipItem('Tagalog',    'lang_tagalog',    Icons.language),
  _ChipItem('Malay',      'lang_malay',      Icons.language),
];

// ─────────────────────────────────────────────────────────────────────────────

class EmergencyCardPage extends StatefulWidget {
  const EmergencyCardPage({super.key});

  @override
  State<EmergencyCardPage> createState() => _EmergencyCardPageState();
}

class _EmergencyCardPageState extends State<EmergencyCardPage> {
  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final profileProvider = context.watch<UserProfileProvider>();
    final profile = profileProvider.profile;

    return Scaffold(
      backgroundColor: _kRed,
      appBar: AppBar(
        title: SafeText(GapLessL10n.t('header_emergency_gear'),
            style: safeStyle(size: 18, isBold: true, color: Colors.white)),
        backgroundColor: _kRedLight,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            tooltip: GapLessL10n.t('label_edit'),
            onPressed: () => _showEditSheet(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildIdentityCard(profile),
            const SizedBox(height: 12),
            if (profile.allergies.isNotEmpty || profile.conditions.isNotEmpty)
              _buildMedicalCard(profile),
            if (profile.allergies.isNotEmpty || profile.conditions.isNotEmpty)
              const SizedBox(height: 12),
            if (profile.needs.isNotEmpty || profile.languages.isNotEmpty)
              _buildSupportCard(profile),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ── カード: 基本情報 ────────────────────────────────────────────────────────

  Widget _buildIdentityCard(UserProfile p) {
    return _card(
      icon: Icons.person_outline,
      title: GapLessL10n.t('label_name'),
      children: [
        _row(GapLessL10n.t('label_name'), p.name.isEmpty ? '-' : p.name, large: true),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _row(GapLessL10n.t('label_blood'), p.bloodType.isEmpty ? '-' : p.bloodType)),
          Expanded(child: _row(GapLessL10n.t('label_nation'), p.nationality.isEmpty ? '-' : p.nationality)),
        ]),
        if (p.birthDate.isNotEmpty) ...[
          const SizedBox(height: 10),
          _row(GapLessL10n.t('label_dob'), p.birthDate),
        ],
        if (p.emergencyContact.isNotEmpty || p.emergencyPhone.isNotEmpty) ...[
          const Divider(height: 20),
          _row(GapLessL10n.t('section_emergency_contact'),
              [p.emergencyContact, p.emergencyPhone].where((s) => s.isNotEmpty).join('  ·  ')),
        ],
        if (p.medications.isNotEmpty) ...[
          const Divider(height: 20),
          _row(GapLessL10n.t('section_medications'), p.medications),
        ],
      ],
    );
  }

  // ── カード: 医療情報 ────────────────────────────────────────────────────────

  Widget _buildMedicalCard(UserProfile p) {
    return _card(
      icon: Icons.local_hospital_outlined,
      title: GapLessL10n.t('card_medical'),
      children: [
        if (p.allergies.isNotEmpty) ...[
          _label(GapLessL10n.t('section_allergies')),
          _chips(p.allergies, _allergyItems, const Color(0xFFFFEBEE), _kRed),
        ],
        if (p.allergies.isNotEmpty && p.conditions.isNotEmpty)
          const SizedBox(height: 10),
        if (p.conditions.isNotEmpty) ...[
          _label(GapLessL10n.t('section_conditions')),
          _chips(p.conditions, _conditionItems, const Color(0xFFFFF3E0), Color(0xFFE65100)),
        ],
      ],
    );
  }

  // ── カード: サポート・言語 ─────────────────────────────────────────────────

  Widget _buildSupportCard(UserProfile p) {
    return _card(
      icon: Icons.support_outlined,
      title: GapLessL10n.t('card_support_language'),
      children: [
        if (p.needs.isNotEmpty) ...[
          _label(GapLessL10n.t('section_needs')),
          _chips(p.needs, _needItems, const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
        ],
        if (p.needs.isNotEmpty && p.languages.isNotEmpty)
          const SizedBox(height: 10),
        if (p.languages.isNotEmpty) ...[
          _label(GapLessL10n.t('section_languages')),
          _chips(p.languages, _languageItems, const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
        ],
      ],
    );
  }

  // ── 共通パーツ ──────────────────────────────────────────────────────────────

  Widget _card({required IconData icon, required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: _kRed),
          const SizedBox(width: 6),
          SafeText(title, style: safeStyle(size: 13, isBold: true, color: _kRed)),
        ]),
        const Divider(height: 16),
        ...children,
      ]),
    );
  }

  Widget _row(String label, String value, {bool large = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SafeText(label, style: safeStyle(size: 10, color: Colors.grey[500]!)),
      const SizedBox(height: 2),
      SafeText(value, style: safeStyle(size: large ? 20 : 15, isBold: true)),
    ]);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SafeText(text, style: safeStyle(size: 12, isBold: true, color: Colors.grey[600]!)),
      );

  Widget _chips(List<String> selected, List<_ChipItem> items, Color bg, Color fg) {
    final labels = <Widget>[];
    for (final item in items) {
      if (!selected.contains(item.id)) continue;
      labels.add(Container(
        margin: const EdgeInsets.only(right: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(item.icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(GapLessL10n.t(item.label), style: TextStyle(
            fontSize: 12, color: fg, fontWeight: FontWeight.w600,
            fontFamily: GapLessL10n.currentFont,
            fontFamilyFallback: GapLessL10n.fallbackFonts,
          )),
        ]),
      ));
    }
    return Wrap(children: labels);
  }

  // ── 編集ボトムシート ────────────────────────────────────────────────────────

  void _showEditSheet(BuildContext context) {
    final profile = context.read<UserProfileProvider>().profile;
    final nameCtrl = TextEditingController(text: profile.name);
    final natCtrl  = TextEditingController(text: profile.nationality);
    final bloodCtrl = TextEditingController(text: profile.bloodType);
    final dobCtrl  = TextEditingController(text: profile.birthDate);
    final medCtrl  = TextEditingController(text: profile.medications);
    final ecCtrl   = TextEditingController(text: profile.emergencyContact);
    final epCtrl   = TextEditingController(text: profile.emergencyPhone);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        maxChildSize: 0.97,
        minChildSize: 0.5,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Consumer<UserProfileProvider>(
            builder: (ctx, provider, _) {
              final p = provider.profile;
              return ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  // ヘッダー
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    SafeText(GapLessL10n.t('label_edit'), style: safeStyle(size: 20, isBold: true)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: MaterialLocalizations.of(ctx).closeButtonTooltip,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ]),
                  const Divider(),
                  const SizedBox(height: 8),

                  _sectionHeader(GapLessL10n.t('section_basic_info'), Icons.person_outline),
                  _field(GapLessL10n.t('label_name'), nameCtrl, (v) { p.name = v; provider.saveProfile(p); }, hint: GapLessL10n.t('hint_name')),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _field(GapLessL10n.t('label_blood'), bloodCtrl, (v) { p.bloodType = v; provider.saveProfile(p); })),
                    const SizedBox(width: 12),
                    Expanded(child: _field(GapLessL10n.t('label_nation'), natCtrl, (v) { p.nationality = v; provider.saveProfile(p); })),
                  ]),
                  const SizedBox(height: 12),
                  _field(GapLessL10n.t('label_dob'), dobCtrl, (v) { p.birthDate = v; provider.saveProfile(p); }, hint: 'YYYY-MM-DD'),
                  const SizedBox(height: 20),

                  _sectionHeader(GapLessL10n.t('section_emergency_contact'), Icons.phone_outlined),
                  _field(GapLessL10n.t('label_emergency_name'), ecCtrl, (v) { p.emergencyContact = v; provider.saveProfile(p); }),
                  const SizedBox(height: 12),
                  _field(GapLessL10n.t('label_emergency_phone'), epCtrl, (v) { p.emergencyPhone = v; provider.saveProfile(p); }, keyboardType: TextInputType.phone),
                  const SizedBox(height: 20),

                  _sectionHeader(GapLessL10n.t('section_medications'), Icons.medication_outlined),
                  _field(GapLessL10n.t('label_medication_names'), medCtrl, (v) { p.medications = v; provider.saveProfile(p); }, maxLines: 2),
                  const SizedBox(height: 24),

                  _sectionHeader(GapLessL10n.t('section_allergies'), Icons.warning_amber_outlined),
                  _chipSelector(p.allergies, _allergyItems, _kRed, (id, sel) {
                    sel ? p.allergies.add(id) : p.allergies.remove(id);
                    provider.saveProfile(p);
                  }),
                  const SizedBox(height: 24),

                  _sectionHeader(GapLessL10n.t('section_conditions'), Icons.local_hospital_outlined),
                  _chipSelector(p.conditions, _conditionItems, const Color(0xFFE65100), (id, sel) {
                    sel ? p.conditions.add(id) : p.conditions.remove(id);
                    provider.saveProfile(p);
                  }),
                  const SizedBox(height: 24),

                  _sectionHeader(GapLessL10n.t('section_needs'), Icons.support_outlined),
                  _chipSelector(p.needs, _needItems, const Color(0xFF1565C0), (id, sel) {
                    sel ? p.needs.add(id) : p.needs.remove(id);
                    provider.saveProfile(p);
                  }),
                  const SizedBox(height: 24),

                  _sectionHeader(GapLessL10n.t('section_languages'), Icons.language_outlined),
                  _chipSelector(p.languages, _languageItems, const Color(0xFF2E7D32), (id, sel) {
                    sel ? p.languages.add(id) : p.languages.remove(id);
                    provider.saveProfile(p);
                  }),
                  const SizedBox(height: 40),
                ],
              );
            },
          ),
        ),
      ),
    ).then((_) {
      nameCtrl.dispose(); natCtrl.dispose(); bloodCtrl.dispose();
      dobCtrl.dispose(); medCtrl.dispose(); ecCtrl.dispose(); epCtrl.dispose();
    });
  }

  Widget _sectionHeader(String text, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, size: 16, color: _kRed),
          const SizedBox(width: 6),
          SafeText(text, style: safeStyle(size: 14, isBold: true, color: _kRed)),
        ]),
      );

  Widget _field(String label, TextEditingController ctrl, Function(String) onChange,
      {String? hint, TextInputType? keyboardType, int maxLines = 1}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SafeText(label, style: safeStyle(size: 12, isBold: true, color: Colors.grey[600]!)),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        onChanged: onChange,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: safeStyle(size: 15),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: GapLessL10n.safeStyle(const TextStyle(fontSize: 14, color: Color(0xFFBDBDBD))),
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          filled: true,
          fillColor: _kSurface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _kRed, width: 1.5),
          ),
        ),
      ),
    ]);
  }

  Widget _chipSelector(List<String> selected, List<_ChipItem> items, Color activeColor,
      void Function(String id, bool selected) onChange) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        final isSel = selected.contains(item.id);
        return FilterChip(
          avatar: Icon(item.icon, size: 14, color: isSel ? Colors.white : activeColor),
          label: Text(GapLessL10n.t(item.label),
              style: TextStyle(
                fontSize: 12, color: isSel ? Colors.white : Colors.black87, fontWeight: FontWeight.w500,
                fontFamily: GapLessL10n.currentFont,
                fontFamilyFallback: GapLessL10n.fallbackFonts,
              )),
          selected: isSel,
          selectedColor: activeColor,
          backgroundColor: _kSurface,
          side: BorderSide(color: isSel ? activeColor : Colors.black12),
          showCheckmark: false,
          onSelected: (v) => onChange(item.id, v),
        );
      }).toList(),
    );
  }
}

class EmergencyCardScreen extends EmergencyCardPage {
  const EmergencyCardScreen({super.key});
}
