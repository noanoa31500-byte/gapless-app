import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import '../providers/shelter_provider.dart';
import '../providers/location_provider.dart';
import '../providers/language_provider.dart';
import '../providers/user_profile_provider.dart';
import '../models/shelter.dart';

import '../utils/styles.dart';
import '../utils/localization.dart';
import '../services/chat_service.dart';
import 'safe_text.dart';

class AIChatWidget extends StatefulWidget {
  const AIChatWidget({super.key});

  @override
  State<AIChatWidget> createState() => _AIChatWidgetState();
}

class _AIChatWidgetState extends State<AIChatWidget> {
  String _aiMessage = '';
  bool _isAnalyzing = false;
  Shelter? _foundShelter;
  String _lastLang = '';

  @override
  void initState() {
    super.initState();
    _aiMessage = GapLessL10n.t('chat_prompt_main');
    _lastLang = GapLessL10n.lang;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset prompt when language changes (but not while analyzing)
    final currentLang = GapLessL10n.lang;
    if (!_isAnalyzing && currentLang != _lastLang) {
      _lastLang = currentLang;
      _aiMessage = GapLessL10n.t('chat_prompt_main');
      _foundShelter = null;
    }
  }

  Future<void> _handleUserSelection(String type) async {
    final locationProvider = context.read<LocationProvider>();
    final shelterProvider = context.read<ShelterProvider>();
    final userProfile = context.read<UserProfileProvider>().profile;

    setState(() {
      _isAnalyzing = true;
      _aiMessage = GapLessL10n.t('bot_analyzing');
    });

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    final region = shelterProvider.currentRegion;

    // Map chip type to guide key for ChatService
    String inputKey = type;
    if (type == 'hospital') inputKey = 'water blood injury';
    if (type == 'water') inputKey = 'water';
    if (type == 'convenience') inputKey = 'food';
    if (type == 'shelter') inputKey = 'shelter';

    final botResponse = ChatService.generateResponse(
      guideId: inputKey,
      isSafeInShelter: shelterProvider.isSafeInShelter,
      profile: userProfile,
      region: region,
    );

    final userLoc = locationProvider.currentLocation;

    if (userLoc == null) {
      setState(() {
        _isAnalyzing = false;
        _aiMessage = '${botResponse.text}\n\n${GapLessL10n.t('bot_loc_error')}';
      });
      return;
    }

    // Map type to shelter search types
    List<String> targetTypes;
    if (type == 'shelter') {
      targetTypes = ['shelter', 'school', 'gov', 'community_centre', 'temple'];
    } else if (type == 'hospital') {
      targetTypes = ['hospital'];
    } else if (type == 'convenience') {
      targetTypes = ['convenience', 'store'];
    } else {
      targetTypes = [type];
    }

    final nearest = shelterProvider.getNearestShelter(
      LatLng(userLoc.latitude, userLoc.longitude),
      includeTypes: targetTypes,
    );

    setState(() {
      _isAnalyzing = false;

      String finalMsg = botResponse.text;

      if (nearest != null) {
        _foundShelter = nearest;
        final distance = const Distance().as(
          LengthUnit.Meter,
          LatLng(userLoc.latitude, userLoc.longitude),
          LatLng(nearest.lat, nearest.lng),
        );
        final foundDesc = GapLessL10n.t('bot_found_desc')
            .replaceAll('@name', nearest.name)
            .replaceAll('@dist', '${distance.toStringAsFixed(0)}m');
        finalMsg += '\n\n${GapLessL10n.t('bot_found')}\n$foundDesc';
      } else {
        _foundShelter = null;
        finalMsg +=
            '\n\n${GapLessL10n.t('bot_not_found')}\n${GapLessL10n.t('bot_not_found_desc')}';
      }

      _aiMessage = finalMsg;
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // rebuild on language change
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // AI Message Area
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFE53935).withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFE53935),
                child: Text(
                  'AI',
                  style: emergencyTextStyle(color: Colors.white, isBold: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _isAnalyzing
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFE53935)),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SafeText(
                            _aiMessage,
                            style: safeStyle(size: 15, color: Colors.black87),
                          ),
                          if (_foundShelter != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12.0),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    FocusScope.of(context).unfocus();
                                    final provider =
                                        context.read<ShelterProvider>();
                                    final newTarget = _foundShelter!;
                                    provider.startNavigation(newTarget);

                                    ScaffoldMessenger.of(context)
                                        .hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: SafeText(
                                          GapLessL10n.t('bot_dest_set')
                                              .replaceAll(
                                                  '@name', newTarget.name),
                                          style: safeStyle(
                                              color: Colors.white, size: 14),
                                        ),
                                        backgroundColor: Colors.green,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.navigation, size: 18),
                                  label: SafeText(
                                    GapLessL10n.t('bot_go_to').replaceAll(
                                        '@name', _foundShelter?.name ?? ''),
                                    style: emergencyTextStyle(
                                        isBold: true, color: Colors.white),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),

        // Action Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildChip(
                type: 'water',
                labelKey: 'bot_water',
              ),
              const SizedBox(width: 8),
              _buildChip(
                type: 'hospital',
                labelKey: 'bot_hospital',
              ),
              const SizedBox(width: 8),
              _buildChip(
                type: 'convenience',
                labelKey: 'bot_store',
              ),
              const SizedBox(width: 8),
              _buildChip(
                type: 'shelter',
                labelKey: 'bot_safe_shelter',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChip({
    required String type,
    required String labelKey,
  }) {
    return ActionChip(
      label: SafeText(
        GapLessL10n.t(labelKey),
        style: safeStyle(size: 14, color: Colors.black87),
      ),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 2,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () => _handleUserSelection(type),
    );
  }
}
