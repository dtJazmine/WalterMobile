import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'parking_slot.dart';
import 'parking_stall_tile.dart';
import 'qr_generation_screen.dart'; // for the shared FloatingQrButton

/// Standalone screen wrapper. Use this only if you need to push the
/// parking map as its own route with its own AppBar.
/// For embedding inside home_screen.dart's existing Scaffold, use
/// [ParkingMapBody] directly instead.
///
/// NOTE: when embedding [ParkingMapBody] inside another Scaffold
/// (e.g. home_screen.dart), also add a [FloatingQrButton] to that
/// Scaffold's `bottomNavigationBar` \u2014 see the bottom of this file
/// for a ready-to-use helper. ParkingMapBody itself has no Scaffold,
/// so it can't pin its own bottom bar; only the parent Scaffold can.
class ParkingMapScreen extends StatelessWidget {
  const ParkingMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue,
        elevation: 0,
        title: const Text(
          'Parking map',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
      ),
      body: const SafeArea(child: ParkingMapBody()),
      // Standalone route owns its own Scaffold, so it CAN pin the button.
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.zero,
        child: FloatingQrButton(
          label: 'Generate QR code',
          onPressed: () {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please sign in again.')),
              );
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => QrGenerationScreen(accountId: uid),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The live parking map content only \u2014 no Scaffold, no AppBar, and
/// no Generate QR button. Designed to be dropped into another screen's
/// body, e.g. home_screen.dart. The parent screen is responsible for
/// adding its own FloatingQrButton to its Scaffold's bottomNavigationBar.
class ParkingMapBody extends StatefulWidget {
  const ParkingMapBody({super.key});

  @override
  State<ParkingMapBody> createState() => _ParkingMapBodyState();
}

class _ParkingMapBodyState extends State<ParkingMapBody> {
  String _selectedSection = 'front';

  // Set once the user confirms they're parked in a specific slot.
  // Drives the top banner switching from "SUGGESTED FOR YOU" to
  // "CURRENT PARKING SLOT".
  String? _confirmedSlotLabel;

  // The raw slot id (e.g. "F3") of the confirmed slot. Used to force
  // that specific tile to render as occupied + highlighted in the grid,
  // regardless of what the (currently static / eventually Firebase-fed)
  // isOccupied flag on the underlying ParkingSlot says.
  String? _confirmedSlotId;

  // True right after the user confirms they've left their slot. Drives
  // the banner to show a "THANK YOU" message briefly before it settles
  // back to "SUGGESTED FOR YOU".
  bool _showThankYouBanner = false;

  // Auto-reverts the thank-you banner back to the default suggestion.
  Timer? _thankYouTimer;

  @override
  void dispose() {
    _thankYouTimer?.cancel();
    super.dispose();
  }

  // TODO: Replace with a real-time Firebase stream (StreamBuilder)
  // listening to /slots/{section}/{subArea} in your Realtime Database.
  // Front splits into two sub-areas mirroring the real layout of
  // Waltermart Mabalacat. Side and Back are placeholders until their
  // physical layout is finalized.
  final Map<String, ParkingSection> _sections = {
    'front': ParkingSection(
      key: 'front',
      label: 'Front',
      subAreas: [
        ParkingSubArea(
          key: 'front_left',
          label: 'Front \u2014 Left side parking',
          leftColumn: const [
            ParkingSlot(id: 'F16', isOccupied: true),
            ParkingSlot(id: 'F17', isOccupied: true),
            ParkingSlot(id: 'F18', isOccupied: false),
            ParkingSlot(id: 'F19', isOccupied: true),
            ParkingSlot(id: 'F20', isOccupied: false),
            ParkingSlot(id: 'F21', isOccupied: true),
            ParkingSlot(id: 'F22', isOccupied: false),
          ],
          rightColumn: const [
            ParkingSlot(id: 'F1', isOccupied: false),
            ParkingSlot(id: 'F2', isOccupied: true),
            ParkingSlot(id: 'F3', isOccupied: false),
            ParkingSlot(id: 'F4', isOccupied: true),
            ParkingSlot(id: 'F5', isOccupied: false),
            ParkingSlot(id: 'F6', isOccupied: true),
            ParkingSlot(id: 'F7', isOccupied: true),
            ParkingSlot(id: 'F8', isOccupied: true),
            ParkingSlot(id: 'F9', isOccupied: false),
          ],
        ),
        ParkingSubArea(
          key: 'front_right',
          label: 'Front \u2014 Right side parking',
          leftColumn: const [
            ParkingSlot(id: 'F23', isOccupied: true),
            ParkingSlot(id: 'F24', isOccupied: true),
            ParkingSlot(id: 'F25', isOccupied: true),
            ParkingSlot(id: 'F26', isOccupied: false),
            ParkingSlot(id: 'F27', isOccupied: true),
            ParkingSlot(id: 'F28', isOccupied: false),
            ParkingSlot(id: 'F29', isOccupied: true),
            ParkingSlot(id: 'F30', isOccupied: false),
          ],
          rightColumn: const [
            ParkingSlot(id: 'F10', isOccupied: false, isPwd: true),
            ParkingSlot(id: 'F11', isOccupied: false, isPwd: true),
            ParkingSlot(id: 'F12', isOccupied: true),
            ParkingSlot(id: 'F13', isOccupied: true),
            ParkingSlot(id: 'F14', isOccupied: true),
            ParkingSlot(id: 'F15', isOccupied: true),
          ],
        ),
      ],
    ),
    'side': ParkingSection(
      key: 'side',
      label: 'Side',
      subAreas: [
        ParkingSubArea(
          key: 'side_main',
          label: 'Side parking',
          // Straight single-line layout \u2014 no drive lane split.
          // All 60 slots in one column, S1 to S60, aligned right.
          leftColumn: const [],
          rightColumn: List.generate(
            60,
            (i) => ParkingSlot(id: 'S${i + 1}', isOccupied: i % 3 == 0),
          ),
        ),
      ],
    ),
    'back': ParkingSection(
      key: 'back',
      label: 'Back',
      subAreas: [
        ParkingSubArea(
          key: 'back_main',
          label: 'Back parking',
          // 122 slots split evenly across the drive lane, B1\u2013B61 on the
          // left and B62\u2013B122 on the right.
          leftColumn: List.generate(
            61,
            (i) => ParkingSlot(id: 'B${i + 1}', isOccupied: i % 2 == 0),
          ),
          rightColumn: List.generate(
            61,
            (i) => ParkingSlot(id: 'B${i + 62}', isOccupied: i % 2 == 0),
          ),
        ),
      ],
    ),
  };

  String _selectedSubAreaKey = 'front_left';

  ParkingSection get _activeSection => _sections[_selectedSection]!;

  ParkingSubArea get _activeSubArea => _activeSection.subAreas
      .firstWhere((a) => a.key == _selectedSubAreaKey,
          orElse: () => _activeSection.subAreas.first);

  void _selectSection(String key) {
    setState(() {
      _selectedSection = key;
      // Default to the first sub-area whenever the section changes.
      _selectedSubAreaKey = _sections[key]!.subAreas.first.key;
    });
  }

  void _handleSlotTap(ParkingSlot slot, String sectionLabel) {
    // Occupied slots aren't tappable in the grid (see _ParkingGrid),
    // but guard here too in case this is ever called some other way.
    if (slot.isOccupied) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _ParkingDialog(
        headerTitle: 'PARKING SLOT CONFIRMATION',
        subtitleText: '$sectionLabel Parking \u2014 ${slot.id}',
        question: 'Are you currently parked in this slot?',
        confirmLabel: 'YES, I AM',
        confirmColor: AppColors.slotAvailable,
        onClose: () => Navigator.of(dialogContext).pop(),
        onConfirm: () {
          // Cancel any pending thank-you auto-revert so it doesn't
          // stomp on the newly confirmed slot a few seconds from now.
          _thankYouTimer?.cancel();
          setState(() {
            _confirmedSlotLabel = '$sectionLabel Parking \u2014 ${slot.id}';
            _confirmedSlotId = slot.id;
            _showThankYouBanner = false;
          });
          Navigator.of(dialogContext).pop();
        },
      ),
    );
  }

  // Tapping the user's own (highlighted, red) slot asks whether they're
  // leaving. Confirming frees the slot back to available/green and
  // switches the banner to a "thank you" message for a few seconds.
  void _handleLeaveSlotTap(ParkingSlot slot, String sectionLabel) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _ParkingDialog(
        headerTitle: 'LEAVING PARKING SLOT',
        subtitleText: '$sectionLabel Parking \u2014 ${slot.id}',
        question: 'Are you leaving this slot?',
        confirmLabel: "YES, I'M LEAVING",
        confirmColor: AppColors.slotOccupied,
        onClose: () => Navigator.of(dialogContext).pop(),
        onConfirm: () {
          setState(() {
            _confirmedSlotLabel = null;
            _confirmedSlotId = null;
            _showThankYouBanner = true;
          });
          Navigator.of(dialogContext).pop();

          _thankYouTimer?.cancel();
          _thankYouTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) setState(() => _showThankYouBanner = false);
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = _activeSection;
    final subArea = _activeSubArea;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Parking map',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            '212 stalls monitored \u2022 Live',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),

          _SuggestedSlotBanner(
            sectionLabel: section.label,
            confirmedSlotLabel: _confirmedSlotLabel,
            showThankYou: _showThankYouBanner,
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _SectionTabs(
                  sections: _sections.values.toList(),
                  selectedKey: _selectedSection,
                  onSelect: _selectSection,
                ),
                const SizedBox(height: 14),
                _StatsRow(section: section, confirmedSlotId: _confirmedSlotId),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Text(
            '${section.label.toUpperCase()} PARKING \u2014 LIVE MAP',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),

          if (section.subAreas.length > 1)
            _SubAreaDropdown(
              subAreas: section.subAreas,
              selectedKey: _selectedSubAreaKey,
              onSelect: (key) => setState(() => _selectedSubAreaKey = key),
            )
          else
            _SubAreaDropdown(
              subAreas: section.subAreas,
              selectedKey: subArea.key,
              onSelect: (_) {},
              enabled: false,
            ),
          const SizedBox(height: 16),

          _ParkingGrid(
            subArea: subArea,
            sectionLabel: section.label,
            confirmedSlotId: _confirmedSlotId,
            onSlotTap: (slot) => _handleSlotTap(slot, section.label),
            onConfirmedSlotTap: (slot) =>
                _handleLeaveSlotTap(slot, section.label),
          ),

          // Generate QR button intentionally removed from here.
          // It now belongs in the parent Scaffold's bottomNavigationBar
          // (see ParkingMapScreen above, or home_screen.dart) so it
          // stays fixed on screen instead of scrolling with this content.
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SuggestedSlotBanner extends StatelessWidget {
  final String sectionLabel;
  final String? confirmedSlotLabel;
  final bool showThankYou;
  const _SuggestedSlotBanner({
    required this.sectionLabel,
    this.confirmedSlotLabel,
    this.showThankYou = false,
  });

  @override
  Widget build(BuildContext context) {
    final isConfirmed = confirmedSlotLabel != null;

    // Three banner states: thank-you (just left) > confirmed (parked) >
    // suggested (default).
    final String eyebrow;
    final String message;
    final Color accentColor;
    if (showThankYou) {
      eyebrow = 'THANK YOU';
      message = 'Drive safe \u2014 come back soon!';
      accentColor = AppColors.slotAvailable;
    } else if (isConfirmed) {
      eyebrow = 'CURRENT PARKING SLOT';
      message = confirmedSlotLabel!;
      accentColor = AppColors.primaryBlue;
    } else {
      eyebrow = 'SUGGESTED FOR YOU';
      message = 'Front section \u2014 F1, F3, F5';
      accentColor = AppColors.primaryBlue;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey('$eyebrow-$message'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: showThankYou ? accentColor : AppColors.border,
            width: showThankYou ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              eyebrow,
              style: TextStyle(
                fontSize: 11,
                color: showThankYou ? accentColor : AppColors.textSecondary,
                fontWeight: showThankYou ? FontWeight.w700 : FontWeight.w400,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTabs extends StatelessWidget {
  final List<ParkingSection> sections;
  final String selectedKey;
  final ValueChanged<String> onSelect;

  const _SectionTabs({
    required this.sections,
    required this.selectedKey,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: sections.map((s) {
        final isActive = s.key == selectedKey;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => onSelect(s.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primaryBlue
                      : AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive ? AppColors.primaryBlue : AppColors.border,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${s.label} (${s.total})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isActive ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final ParkingSection section;
  // Passed in purely so the "Open"/"Taken" counts stay accurate once a
  // slot has been confirmed \u2014 the underlying isOccupied flag on that
  // ParkingSlot won't have flipped (it's still static/demo data), so we
  // adjust the displayed counts by one when the confirmed slot lives in
  // this section.
  final String? confirmedSlotId;
  const _StatsRow({required this.section, this.confirmedSlotId});

  bool get _confirmedIsInSection {
    if (confirmedSlotId == null) return false;
    return section.subAreas.any((a) =>
        a.leftColumn.any((s) => s.id == confirmedSlotId) ||
        a.rightColumn.any((s) => s.id == confirmedSlotId));
  }

  @override
  Widget build(BuildContext context) {
    // If the confirmed slot was originally "available" in this section's
    // static data, nudge the counts so Open/Taken reflect reality.
    final bumpTaken = _confirmedIsInSection;
    final available = bumpTaken ? section.available - 1 : section.available;
    final occupied = bumpTaken ? section.occupied + 1 : section.occupied;

    return Row(
      children: [
        _StatCard(label: 'Total', value: '${section.total}', color: AppColors.textPrimary),
        const SizedBox(width: 10),
        _StatCard(label: 'Available', value: '$available', color: AppColors.slotAvailable),
        const SizedBox(width: 10),
        _StatCard(label: 'Unavailable', value: '$occupied', color: AppColors.slotOccupied),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _LegendDot(color: AppColors.slotAvailable, label: 'Available'),
        SizedBox(width: 10),
        _LegendDot(color: AppColors.slotOccupied, label: 'Unavailable'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

/// Dropdown for selecting which sub-area's live map to display
/// (e.g. "Front \u2014 Left side parking" vs "Front \u2014 Right side parking").
class _SubAreaDropdown extends StatelessWidget {
  final List<ParkingSubArea> subAreas;
  final String selectedKey;
  final ValueChanged<String> onSelect;
  final bool enabled;

  const _SubAreaDropdown({
    required this.subAreas,
    required this.selectedKey,
    required this.onSelect,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedKey,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
          items: subAreas
              .map((area) => DropdownMenuItem(
                    value: area.key,
                    child: Text(area.label),
                  ))
              .toList(),
          onChanged: enabled
              ? (key) {
                  if (key != null) onSelect(key);
                }
              : null,
        ),
      ),
    );
  }
}

/// Renders a sub-area's slots as two columns split by a dashed drive lane,
/// matching the physical layout of the parking area. Available slots are
/// tappable; occupied slots are not (nothing to confirm there).
///
/// [confirmedSlotId], if set, forces that one tile to render as occupied
/// (red) and wraps it in a highlighted ring so the driver can spot their
/// own slot at a glance, even though the underlying demo/Firebase data
/// for that slot hasn't actually flipped to occupied yet.
class _ParkingGrid extends StatelessWidget {
  final ParkingSubArea subArea;
  final String sectionLabel;
  final String? confirmedSlotId;
  final void Function(ParkingSlot slot) onSlotTap;
  final void Function(ParkingSlot slot) onConfirmedSlotTap;

  const _ParkingGrid({
    required this.subArea,
    required this.sectionLabel,
    required this.onSlotTap,
    required this.onConfirmedSlotTap,
    this.confirmedSlotId,
  });

  Widget _buildTile(ParkingSlot slot) {
    final isConfirmed = confirmedSlotId != null && slot.id == confirmedSlotId;

    // Force the confirmed slot to render as occupied (red), regardless of
    // what its static isOccupied flag says.
    final effectiveSlot = isConfirmed
        ? ParkingSlot(id: slot.id, isOccupied: true, isPwd: slot.isPwd)
        : slot;

    Widget tile = ParkingStallTile(slot: effectiveSlot);

    if (isConfirmed) {
      // The user's own slot: tapping it now asks if they're leaving,
      // instead of being a dead end like other occupied slots.
      tile = _ConfirmedSlotHighlight(child: tile);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onConfirmedSlotTap(slot),
        child: tile,
      );
    }

    // Other occupied slots stay non-tappable; only available slots open
    // the park-confirmation dialog.
    if (effectiveSlot.isOccupied) return tile;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSlotTap(slot),
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerRight,
            child: _LegendRow(),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    children: subArea.leftColumn
                        .map((slot) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: _buildTile(slot),
                            ))
                        .toList(),
                  ),
                ),
                const _DriveLane(),
                Expanded(
                  child: Column(
                    children: subArea.rightColumn
                        .map((slot) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: _buildTile(slot),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps a confirmed slot's tile with a bold ring + glow and a small
/// "YOU" badge so it's immediately visible against the rest of the grid.
class _ConfirmedSlotHighlight extends StatelessWidget {
  final Widget child;
  const _ConfirmedSlotHighlight({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primaryBlue, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withOpacity(0.35),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue,
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 3),
              ],
            ),
            child: const Text(
              'YOU',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DriveLane extends StatelessWidget {
  const _DriveLane();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: const _DashedVerticalLine(),
    );
  }
}

class _DashedVerticalLine extends StatelessWidget {
  const _DashedVerticalLine();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedLinePainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textTertiary
      ..strokeWidth = 1.5;
    const dashHeight = 5.0;
    const dashSpace = 4.0;
    final height = size.height.isFinite ? size.height : 0.0;
    double y = 0;
    final x = size.width / 2;
    while (y < height) {
      canvas.drawLine(Offset(x, y), Offset(x, y + dashHeight), paint);
      y += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Shared confirmation popup, used both when the user taps an available
/// slot (asking if they're parked there) and when they tap their own
/// confirmed slot (asking if they're leaving).
class _ParkingDialog extends StatelessWidget {
  final String headerTitle;
  final String subtitleText;
  final String question;
  final String confirmLabel;
  final Color confirmColor;
  final VoidCallback onClose;
  final VoidCallback onConfirm;

  const _ParkingDialog({
    required this.headerTitle,
    required this.subtitleText,
    required this.question,
    required this.confirmLabel,
    required this.confirmColor,
    required this.onClose,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Blue header bar with title + close (X) button.
            Container(
              width: double.infinity,
              color: AppColors.primaryBlue,
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      headerTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onClose,
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            // Body: slot label, question, and action buttons.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                children: [
                  Text(
                    subtitleText,
                    style: const TextStyle(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    question,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onClose,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryBlue,
                            side: const BorderSide(
                                color: AppColors.primaryBlue, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'CLOSE',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onConfirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: confirmColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            confirmLabel,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
