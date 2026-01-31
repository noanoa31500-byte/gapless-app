
import 'package:flutter/material.dart';
import 'survival/survival_data_jp.dart';
import 'survival/survival_data_th.dart';

class SurvivalStep {
  final Map<String, String> instruction;
  final IconData? icon;
  final int? durationSeconds; // For breathing guidance

  const SurvivalStep({
    required this.instruction,
    this.icon,
    this.durationSeconds,
  });
}

class SurvivalGuideItem {
  final String id;
  final IconData icon;
  final Map<String, String> title;
  final Map<String, String> action; // Summary or fallback
  final List<SurvivalStep>? steps; // New: Detailed visual steps
  final String source; 

  const SurvivalGuideItem({
    required this.id,
    required this.icon,
    required this.title,
    required this.action,
    this.steps,
    required this.source,
  });
}

class SurvivalData {
  // Getter for dynamic access
  static List<SurvivalGuideItem> getOfficialGuides(String region) {
    if (region.startsWith('th')) return SurvivalDataTH.officialGuides;
    return SurvivalDataJP.officialGuides;
  }

  // Dynamic Switcher for AI Support
  static List<SurvivalGuideItem> getAiSupportGuides(String region) {
    if (region.startsWith('th')) return SurvivalDataTH.aiSupportGuides;
    return SurvivalDataJP.aiSupportGuides;
  }
}
