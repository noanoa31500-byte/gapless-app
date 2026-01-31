import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/first_aid_data.dart';
import '../constants/survival_data.dart';
import '../providers/shelter_provider.dart';
import '../utils/localization.dart';
import '../utils/styles.dart';
import '../widgets/safe_text.dart';

/// サバイバルガイド画面
/// 応急処置ガイド + 災害別行動指針 + 避難所生活ガイドをオフラインで表示
class SurvivalGuideScreen extends StatefulWidget {
  const SurvivalGuideScreen({super.key});

  @override
  State<SurvivalGuideScreen> createState() => _SurvivalGuideScreenState();
}

class _SurvivalGuideScreenState extends State<SurvivalGuideScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppLocalizations.lang;

    return Scaffold(
      appBar: AppBar(
        title: SafeText(
          _getTitle(lang),
          style: emergencyTextStyle(size: 20, isBold: true),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFE53935),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFFE53935),
          isScrollable: true,
          tabs: [
            Tab(
              icon: const Icon(Icons.healing),
              text: _getTabFirstAid(lang),
            ),
            Tab(
              icon: const Icon(Icons.warning_amber),
              text: _getTabDisaster(lang),
            ),
            Tab(
              icon: const Icon(Icons.home_work),
              text: _getTabShelterLife(lang),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFirstAidTab(lang),
          _buildDisasterTab(lang),
          _buildShelterLifeTab(lang),
        ],
      ),
    );
  }

  String _getTitle(String lang) {
    switch (lang) {
      case 'ja':
        return 'サバイバルガイド';
      case 'th':
        return 'คู่มือเอาตัวรอด';
      default:
        return 'Survival Guide';
    }
  }

  String _getTabFirstAid(String lang) {
    switch (lang) {
      case 'ja':
        return '応急処置';
      case 'th':
        return 'ปฐมพยาบาล';
      default:
        return 'First Aid';
    }
  }

  String _getTabDisaster(String lang) {
    switch (lang) {
      case 'ja':
        return '災害別行動';
      case 'th':
        return 'ภัยพิบัติ';
      default:
        return 'Disasters';
    }
  }

  String _getTabShelterLife(String lang) {
    switch (lang) {
      case 'ja':
        return '避難所生活';
      case 'th':
        return 'ชีวิตในศูนย์พักพิง';
      default:
        return 'Shelter Life';
    }
  }

  /// 応急処置タブ
  Widget _buildFirstAidTab(String lang) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: FirstAidData.items.length,
      itemBuilder: (context, index) {
        final item = FirstAidData.items[index];
        return _buildFirstAidCard(item, lang);
      },
    );
  }

  Widget _buildFirstAidCard(FirstAidItem item, String lang) {
    final title = item.title[lang] ?? item.title['en']!;
    final summary = item.summary[lang] ?? item.summary['en']!;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: item.isLifeThreatening
            ? BorderSide(color: item.color, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _showFirstAidDetail(item, lang),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, size: 28, color: item.color),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (item.isLifeThreatening)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: item.color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: SafeText(
                              _getUrgentLabel(lang),
                              style: emergencyTextStyle(
                                  size: 10, color: Colors.white, isBold: true),
                            ),
                          ),
                        Expanded(
                          child: SafeText(
                            title,
                            style: emergencyTextStyle(size: 16, isBold: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SafeText(
                      summary,
                      style: emergencyTextStyle(size: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  String _getUrgentLabel(String lang) {
    switch (lang) {
      case 'ja':
        return '緊急';
      case 'th':
        return 'ฉุกเฉิน';
      default:
        return 'URGENT';
    }
  }

  /// 応急処置詳細モーダル
  void _showFirstAidDetail(FirstAidItem item, String lang) {
    final title = item.title[lang] ?? item.title['en']!;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    // Handle
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Icon & Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: item.color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child:
                              Icon(item.icon, size: 32, color: Colors.white),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SafeText(
                                title,
                                style:
                                    emergencyTextStyle(size: 24, isBold: true),
                              ),
                              if (item.isLifeThreatening)
                                SafeText(
                                  _getLifeThreateningLabel(lang),
                                  style: emergencyTextStyle(
                                      size: 12, color: item.color),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Steps
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: item.steps.length,
                  itemBuilder: (context, index) {
                    final step = item.steps[index];
                    final instruction =
                        step.instruction[lang] ?? step.instruction['en']!;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Step Number / Icon
                          Column(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: step.isWarning
                                      ? Colors.orange
                                      : item.color,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: step.icon != null
                                      ? Icon(step.icon,
                                          size: 18, color: Colors.white)
                                      : SafeText(
                                          '${index + 1}',
                                          style: emergencyTextStyle(
                                              color: Colors.white,
                                              isBold: true),
                                        ),
                                ),
                              ),
                              if (index < item.steps.length - 1)
                                Container(
                                  width: 2,
                                  height: 40,
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  color: Colors.grey[200],
                                ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          // Instruction
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: step.isWarning
                                        ? Colors.orange.withValues(alpha: 0.1)
                                        : Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: step.isWarning
                                        ? Border.all(color: Colors.orange)
                                        : null,
                                  ),
                                  child: SafeText(
                                    instruction,
                                    style: emergencyTextStyle(
                                      size: 16,
                                      isBold: true,
                                      color: step.isWarning
                                          ? (Colors.orange[900] ?? Colors.orange)
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                                if (step.durationSeconds != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Chip(
                                      avatar: const Icon(Icons.timer, size: 16),
                                      label: SafeText(
                                        _formatDuration(
                                            step.durationSeconds!, lang),
                                        style: emergencyTextStyle(size: 12),
                                      ),
                                      backgroundColor: Colors.blue[50],
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Close Button
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: item.color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: SafeText(
                      _getCloseLabel(lang),
                      style:
                          emergencyTextStyle(color: Colors.white, isBold: true),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getLifeThreateningLabel(String lang) {
    switch (lang) {
      case 'ja':
        return '⚠️ 命に関わる緊急事態';
      case 'th':
        return '⚠️ เหตุฉุกเฉินที่คุกคามชีวิต';
      default:
        return '⚠️ Life-threatening emergency';
    }
  }

  String _formatDuration(int seconds, String lang) {
    if (seconds >= 60) {
      final minutes = seconds ~/ 60;
      switch (lang) {
        case 'ja':
          return '$minutes分以上';
        case 'th':
          return '$minutes+ นาที';
        default:
          return '$minutes+ min';
      }
    } else {
      switch (lang) {
        case 'ja':
          return '$seconds秒';
        case 'th':
          return '$seconds วินาที';
        default:
          return '$seconds sec';
      }
    }
  }

  String _getCloseLabel(String lang) {
    switch (lang) {
      case 'ja':
        return '閉じる';
      case 'th':
        return 'ปิด';
      default:
        return 'Close';
    }
  }

  /// 災害別行動タブ
  Widget _buildDisasterTab(String lang) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: DisasterActionData.items.length,
      itemBuilder: (context, index) {
        final item = DisasterActionData.items[index];
        return _buildDisasterCard(item, lang);
      },
    );
  }

  Widget _buildDisasterCard(DisasterActionItem item, String lang) {
    final title = item.title[lang] ?? item.title['en']!;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () => _showDisasterDetail(item, lang),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, size: 28, color: item.color),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: SafeText(
                  title,
                  style: emergencyTextStyle(size: 16, isBold: true),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  /// 災害別行動詳細モーダル
  void _showDisasterDetail(DisasterActionItem item, String lang) {
    final title = item.title[lang] ?? item.title['en']!;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    // Handle
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Icon & Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: item.color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child:
                              Icon(item.icon, size: 32, color: Colors.white),
                        ),
                        const SizedBox(width: 16),
                        SafeText(
                          title,
                          style: emergencyTextStyle(size: 24, isBold: true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Steps
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: item.steps.length,
                  itemBuilder: (context, index) {
                    final step = item.steps[index];
                    final action = step.action[lang] ?? step.action['en']!;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: step.isDont
                            ? Colors.red.withValues(alpha: 0.1)
                            : Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: step.isDont
                              ? Colors.red.withValues(alpha: 0.3)
                              : Colors.green.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (step.icon != null)
                            Container(
                              padding: const EdgeInsets.all(8),
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                color: step.isDont
                                    ? Colors.red.withValues(alpha: 0.2)
                                    : Colors.green.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                step.icon,
                                size: 24,
                                color: step.isDont ? Colors.red : Colors.green,
                              ),
                            ),
                          Expanded(
                            child: SafeText(
                              action,
                              style: emergencyTextStyle(
                                size: 16,
                                isBold: true,
                                color: step.isDont
                                    ? (Colors.red[900] ?? Colors.red)
                                    : (Colors.green[900] ?? Colors.green),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Close Button
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: item.color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: SafeText(
                      _getCloseLabel(lang),
                      style:
                          emergencyTextStyle(color: Colors.white, isBold: true),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================================
  // 避難所生活タブ（オンラインコンテンツをオフラインでも表示）
  // ============================================================================
  
  Widget _buildShelterLifeTab(String lang) {
    final shelterProvider = context.watch<ShelterProvider>();
    final region = shelterProvider.currentRegion;
    
    final officialGuides = SurvivalData.getOfficialGuides(region);
    final aiSupportGuides = SurvivalData.getAiSupportGuides(region);
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Official Guides Section
        _buildSectionTitle(
          lang == 'ja' ? '📋 公式ガイドライン' 
              : lang == 'th' ? '📋 คู่มือทางการ' 
              : '📋 Official Guidelines',
          lang == 'ja' ? '政府・公的機関の推奨事項'
              : lang == 'th' ? 'คำแนะนำจากหน่วยงานราชการ'
              : 'Recommendations from government agencies',
        ),
        const SizedBox(height: 12),
        ...officialGuides.map((item) => _buildShelterGuideCard(item, lang)),
        
        const SizedBox(height: 24),
        
        // AI Support Guides Section
        _buildSectionTitle(
          lang == 'ja' ? '🤖 AIサポートガイド'
              : lang == 'th' ? '🤖 คู่มือจาก AI'
              : '🤖 AI Support Guides',
          lang == 'ja' ? '避難所生活のヒント・アドバイス'
              : lang == 'th' ? 'เคล็ดลับสำหรับชีวิตในศูนย์พักพิง'
              : 'Tips and advice for shelter life',
        ),
        const SizedBox(height: 12),
        ...aiSupportGuides.map((item) => _buildShelterGuideCard(item, lang)),
        
        const SizedBox(height: 40),
      ],
    );
  }
  
  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafeText(
          title,
          style: emergencyTextStyle(size: 18, isBold: true),
        ),
        const SizedBox(height: 4),
        SafeText(
          subtitle,
          style: emergencyTextStyle(size: 12, color: Colors.grey),
        ),
      ],
    );
  }
  
  Widget _buildShelterGuideCard(SurvivalGuideItem item, String lang) {
    final title = item.title[lang] ?? item.title['en']!;
    final action = item.action[lang] ?? item.action['en']!;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () => _showShelterGuideDetail(item, lang),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, size: 28, color: const Color(0xFFE53935)),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SafeText(
                      title,
                      style: emergencyTextStyle(size: 16, isBold: true),
                    ),
                    const SizedBox(height: 4),
                    SafeText(
                      action,
                      style: emergencyTextStyle(size: 12, color: Colors.grey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    SafeText(
                      item.source,
                      style: emergencyTextStyle(size: 10, color: Colors.blue),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showShelterGuideDetail(SurvivalGuideItem item, String lang) {
    final title = item.title[lang] ?? item.title['en']!;
    final action = item.action[lang] ?? item.action['en']!;
    final steps = item.steps;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    // Handle
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Icon & Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(item.icon, size: 32, color: Colors.white),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SafeText(
                                title,
                                style: emergencyTextStyle(size: 20, isBold: true),
                              ),
                              const SizedBox(height: 4),
                              SafeText(
                                item.source,
                                style: emergencyTextStyle(size: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Action/Summary
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_outline, color: Colors.blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SafeText(
                                action,
                                style: emergencyTextStyle(size: 16, isBold: true),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Steps if available
                      if (steps != null && steps.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        SafeText(
                          _getStepsLabel(lang),
                          style: emergencyTextStyle(size: 14, isBold: true, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        ...steps.asMap().entries.map((entry) {
                          final index = entry.key;
                          final step = entry.value;
                          final instruction = step.instruction[lang] ?? step.instruction['en']!;
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE53935),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: step.icon != null
                                        ? Icon(step.icon, size: 18, color: Colors.white)
                                        : SafeText(
                                            '${index + 1}',
                                            style: emergencyTextStyle(
                                                color: Colors.white, isBold: true),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: SafeText(
                                      instruction,
                                      style: emergencyTextStyle(size: 16),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      
                      // Multi-language section
                      const SizedBox(height: 24),
                      ExpansionTile(
                        title: SafeText(
                          _getMultiLangLabel(lang),
                          style: emergencyTextStyle(size: 14, color: Colors.grey),
                        ),
                        children: [
                          _buildLangRow('English', item.action['en']!),
                          _buildLangRow('日本語', item.action['ja']!),
                          _buildLangRow('ไทย', item.action['th']!),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              // Close Button
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: SafeText(
                      _getCloseLabel(lang),
                      style: emergencyTextStyle(color: Colors.white, isBold: true),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  String _getStepsLabel(String lang) {
    switch (lang) {
      case 'ja':
        return '📝 手順';
      case 'th':
        return '📝 ขั้นตอน';
      default:
        return '📝 Steps';
    }
  }
  
  String _getMultiLangLabel(String lang) {
    switch (lang) {
      case 'ja':
        return '🌐 多言語で見る';
      case 'th':
        return '🌐 ดูในภาษาอื่น';
      default:
        return '🌐 View in other languages';
    }
  }
  
  Widget _buildLangRow(String label, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafeText(
            label,
            style: emergencyTextStyle(size: 12, isBold: true, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          SafeText(
            text,
            style: emergencyTextStyle(size: 14),
          ),
        ],
      ),
    );
  }
}
