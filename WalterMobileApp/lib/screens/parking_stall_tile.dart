import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'parking_slot.dart';

/// A single tappable parking stall indicator.
/// Color reflects live occupancy state; PWD stalls show a wheelchair icon.
class ParkingStallTile extends StatelessWidget {
  final ParkingSlot slot;
  final VoidCallback? onTap;

  const ParkingStallTile({super.key, required this.slot, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bgColor = slot.isOccupied ? AppColors.slotOccupiedBg : AppColors.slotAvailableBg;
    final fgColor = slot.isOccupied ? AppColors.slotOccupied : AppColors.slotAvailable;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (slot.isPwd) ...[
              Icon(Icons.accessible, size: 14, color: fgColor),
              const SizedBox(width: 3),
            ],
            Text(
              slot.id,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fgColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
