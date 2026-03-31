import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../providers/location_provider.dart';
import '../utils/localization.dart';

/// GPS 消失中に画面上部に表示するバッジ
class DeadReckoningBadge extends StatelessWidget {
  const DeadReckoningBadge({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // rebuild on language change
    final loc = context.watch<LocationProvider>();
    if (!loc.isDeadReckoning) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE65100).withOpacity(0.93),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.gps_off, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            GapLessL10n.t('dr_badge').replaceAll('@steps', '${loc.deadReckoningStepCount}'),
            style: GapLessL10n.safeStyle(const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            )),
          ),
        ],
      ),
    );
  }
}
