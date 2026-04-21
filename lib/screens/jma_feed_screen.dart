import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/jma_alert_service.dart';
import '../utils/localization.dart';

// ============================================================================
// JmaFeedScreen — 気象庁オープンデータ 緊急地震速報・津波警報 一覧
// ============================================================================

class JmaFeedScreen extends StatefulWidget {
  const JmaFeedScreen({super.key});

  @override
  State<JmaFeedScreen> createState() => _JmaFeedScreenState();
}

class _JmaFeedScreenState extends State<JmaFeedScreen> {
  final _service = JmaAlertService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onUpdate);
    _service.startPolling();
  }

  @override
  void dispose() {
    _service.removeListener(_onUpdate);
    _service.stopPolling();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A0000),
        foregroundColor: Colors.white,
        title: Text(
          GapLessL10n.t('jma_feed_title'),
          style: GapLessL10n.safeStyle(
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ),
        actions: [
          if (_service.isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white70),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: GapLessL10n.t('jma_refresh'),
              onPressed: _service.refresh,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_service.isLoading && _service.alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFFE53935)),
            const SizedBox(height: 16),
            Text(GapLessL10n.t('jma_loading'),
                style: GapLessL10n.safeStyle(
                    const TextStyle(color: Colors.white54, fontSize: 14))),
          ],
        ),
      );
    }

    if (_service.lastError != null && _service.alerts.isEmpty) {
      return _buildError();
    }

    if (_service.alerts.isEmpty) {
      return _buildEmpty();
    }

    return RefreshIndicator(
      onRefresh: _service.refresh,
      color: const Color(0xFFE53935),
      backgroundColor: const Color(0xFF1A0000),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _service.alerts.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Color(0xFF2A2A2A)),
        itemBuilder: (_, i) => _AlertTile(alert: _service.alerts[i]),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 56, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              GapLessL10n.t('jma_error'),
              style: GapLessL10n.safeStyle(
                  const TextStyle(color: Colors.white54, fontSize: 14)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _service.refresh,
              icon: const Icon(Icons.refresh),
              label: Text(GapLessL10n.t('jma_refresh')),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB71C1C),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 64, color: Color(0xFF388E3C)),
          const SizedBox(height: 16),
          Text(
            GapLessL10n.t('jma_no_alerts'),
            style: GapLessL10n.safeStyle(
                const TextStyle(color: Colors.white70, fontSize: 16)),
          ),
          const SizedBox(height: 8),
          if (_service.lastFetchAt != null)
            Text(
              '${GapLessL10n.t("jma_last_updated")} '
              '${DateFormat('MM/dd HH:mm').format(_service.lastFetchAt!.toLocal())}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 警報タイル
// ---------------------------------------------------------------------------

class _AlertTile extends StatelessWidget {
  final JmaAlert alert;

  const _AlertTile({required this.alert});

  @override
  Widget build(BuildContext context) {
    final isEq = alert.isEarthquake;
    final color = isEq ? const Color(0xFFB71C1C) : const Color(0xFF0D47A1);
    final icon = isEq ? Icons.crisis_alert : Icons.waves;
    final timeStr = DateFormat('MM/dd HH:mm').format(alert.updatedAt.toLocal());
    final isActive = alert.isActive;

    return Container(
      color: isActive ? color.withValues(alpha: 0.12) : Colors.transparent,
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: isActive ? 0.9 : 0.4),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        title: Text(
          alert.title,
          style: GapLessL10n.safeStyle(TextStyle(
            color: isActive ? Colors.white : Colors.white54,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          )),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            if (isActive)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  GapLessL10n.t('jma_active'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
            Text(
              timeStr,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
    );
  }
}
