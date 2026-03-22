import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../utils/localization.dart';
import '../ble/ble_packet.dart';
import '../providers/location_provider.dart';
import '../services/ble_road_report_service.dart';

// ============================================================================
// QuickReportSheet — カメラ1枚で即時BLE危険報告（Cal AI方式）
// ============================================================================
//
// 【操作フロー】
//   1. showQuickReport() を呼ぶ
//   2. カメラが起動 → シャッターを切る（またはスキップ）
//   3. 写真サムネイル＋3択ボタムシートが表示される
//      ✅ 通れた (passable)
//      🚧 通れない (blocked)
//      ⚠️ 危険あり (danger)
//   4. 1タップで BleRoadReportService.enqueueFullReport() を呼ぶ
//      写真パスは payload JSON に含める（BLE帯域節約のため本体は端末保存のみ）
//
// ============================================================================

/// ナビ画面から呼ぶエントリポイント
Future<void> showQuickReport(BuildContext context) async {
  final loc = context.read<LocationProvider>().currentLocation;
  if (loc == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(GapLessL10n.t('nav_no_location'))),
    );
    return;
  }

  // カメラ起動
  final picker = ImagePicker();
  XFile? photo;
  try {
    photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 60,
      maxWidth: 1280,
    );
  } catch (_) {
    // カメラ拒否・エラー時はスキップして選択シートへ進む
  }

  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuickReportSheet(
      lat: loc.latitude,
      lng: loc.longitude,
      photoFile: photo != null ? File(photo.path) : null,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _QuickReportSheet extends StatefulWidget {
  final double lat;
  final double lng;
  final File? photoFile;

  const _QuickReportSheet({
    required this.lat,
    required this.lng,
    this.photoFile,
  });

  @override
  State<_QuickReportSheet> createState() => _QuickReportSheetState();
}

class _QuickReportSheetState extends State<_QuickReportSheet> {
  bool _submitting = false;

  Future<void> _submit(BleDataType dataType, String label) async {
    if (_submitting) return;
    setState(() => _submitting = true);

    // 写真パスを payload に含める（BLE帯域節約：パスだけ送って本体は端末ローカル）
    final payloadMap = <String, dynamic>{
      'manual': true,
      if (widget.photoFile != null) 'photo': widget.photoFile!.path,
    };
    final payload = jsonEncode(payloadMap);

    await BleRoadReportService.instance.enqueueFullReport(
      lat: widget.lat,
      lng: widget.lng,
      accuracyM: 10.0,
      dataType: dataType,
      payload: payload,
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(GapLessL10n.t('qr_reported').replaceAll('@label', label)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ドラッグハンドル
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // タイトル
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                const Icon(Icons.camera_alt, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Text(
                  GapLessL10n.t('qr_title'),
                  style: GapLessL10n.safeStyle(const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  )),
                ),
              ],
            ),
          ),

          // 写真サムネイル（撮影済みの場合）
          if (widget.photoFile != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                widget.photoFile!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ).padding(const EdgeInsets.symmetric(horizontal: 16)),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                GapLessL10n.t('qr_no_photo'),
                style: GapLessL10n.safeStyle(const TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // 3択ボタン
          _ReportButton(
            icon: Icons.check_circle,
            color: const Color(0xFF43A047),
            label: GapLessL10n.t('qr_passable'),
            sublabel: GapLessL10n.t('qr_passable_sub'),
            onTap: _submitting ? null : () => _submit(BleDataType.passable, GapLessL10n.t('qr_passable')),
          ),
          _ReportButton(
            icon: Icons.block,
            color: const Color(0xFFE53935),
            label: GapLessL10n.t('qr_blocked'),
            sublabel: GapLessL10n.t('qr_blocked_sub'),
            onTap: _submitting ? null : () => _submit(BleDataType.blocked, GapLessL10n.t('qr_blocked')),
          ),
          _ReportButton(
            icon: Icons.warning_amber,
            color: const Color(0xFFFF6F00),
            label: GapLessL10n.t('qr_danger'),
            sublabel: GapLessL10n.t('qr_danger_sub'),
            onTap: _submitting ? null : () => _submit(BleDataType.danger, GapLessL10n.t('qr_danger')),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ReportButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String sublabel;
  final VoidCallback? onTap;

  const _ReportButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GapLessL10n.safeStyle(TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        )),
                      ),
                      Text(
                        sublabel,
                        style: GapLessL10n.safeStyle(const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        )),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: color.withOpacity(0.6), size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget extension — padding helper
extension _PaddingExt on Widget {
  Widget padding(EdgeInsets p) => Padding(padding: p, child: this);
}
