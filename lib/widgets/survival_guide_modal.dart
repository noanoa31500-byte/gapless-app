import 'package:flutter/material.dart';
import '../utils/styles.dart';
import '../utils/localization.dart';
import 'safe_text.dart';

import '../constants/survival_data.dart'; // Adjust path as needed

class SurvivalGuideModal {
  static void show(BuildContext context, SurvivalGuideItem item, String lang) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final title = item.title[lang] ?? item.title['en'] ?? '';
        final action = item.action[lang] ?? item.action['en'] ?? '';
        final steps = item.steps;

        return Container(
          padding: const EdgeInsets.all(24),
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Indicator
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Icon & Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon,
                        size: 32, color: const Color(0xFFE53935)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SafeText(
                          title,
                          style: emergencyTextStyle(
                            size: 20,
                            isBold: true,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SafeText(
                          item.source,
                          style: emergencyTextStyle(
                            size: 12,
                            color: Colors.grey,
                          ).copyWith(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (steps != null && steps.isNotEmpty) ...[
                        SafeText(
                          GapLessL10n.t('sg_steps_header'),
                          style: emergencyTextStyle(
                            size: 12,
                            isBold: true,
                            color: Colors.grey,
                          ).copyWith(letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 16),
                        ...steps.asMap().entries.map((entry) {
                          final index = entry.key;
                          final step = entry.value;
                          final stepText = step.instruction[lang] ??
                              step.instruction['en'] ??
                              '';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: const BoxDecoration(
                                        color: Colors.blue,
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: SafeText(
                                        '${index + 1}',
                                        style: emergencyTextStyle(
                                            color: Colors.white, isBold: true),
                                      ),
                                    ),
                                    if (index != steps.length - 1)
                                      Container(
                                        width: 2,
                                        height: 30,
                                        color: Colors.grey[200],
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 4),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (step.icon != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: Icon(step.icon,
                                              color: Colors.blue[800],
                                              size: 28),
                                        ),
                                      SafeText(
                                        stepText,
                                        style: emergencyTextStyle(
                                          size: 16,
                                          isBold: true,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      if (step.durationSeconds != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Chip(
                                            label: SafeText(
                                              GapLessL10n.t('sg_seconds')
                                                  .replaceAll('@n',
                                                      '${step.durationSeconds}'),
                                            ),
                                            backgroundColor: Colors.blue[50],
                                            labelStyle: emergencyTextStyle(
                                                color: Colors.blue[800]!,
                                                size: 12),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ] else ...[
                        SafeText(
                          GapLessL10n.t('sg_action_header'),
                          style: emergencyTextStyle(
                            size: 12,
                            isBold: true,
                            color: Colors.grey,
                          ).copyWith(letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 8),
                        SafeText(
                          action,
                          style: emergencyTextStyle(
                            size: 18,
                            isBold: true,
                            color: Colors.black87,
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Multi-language Reference
                      ExpansionTile(
                        title: SafeText(
                          GapLessL10n.t('sg_all_lang'),
                          style:
                              emergencyTextStyle(size: 16, color: Colors.grey),
                        ),
                        children: [
                          if (steps == null) ...[
                            _buildLangRow('English', item.action['en']!),
                            _buildLangRow('日本語', item.action['ja']!),
                            _buildLangRow('ไทย', item.action['th']!),
                          ] else ...[
                            _buildLangRow(
                                'Summary (English)', item.action['en']!),
                            _buildLangRow('サマリー (日本語)', item.action['ja']!),
                            _buildLangRow('สรุป (ไทย)', item.action['th']!),
                          ]
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              // Close Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[200],
                    foregroundColor: Colors.black87,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: SafeText(GapLessL10n.t('sg_close'),
                      style: emergencyTextStyle(isBold: true)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildLangRow(String label, String text) {
    // Replaced manual logic with SafeText for unified handling
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafeText(label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              )),
          const SizedBox(height: 2),
          SafeText(text,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
              )),
        ],
      ),
    );
  }
}
