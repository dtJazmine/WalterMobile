import 'dart:async';
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Full-screen blocking prompt shown when the sensor detects occupancy
/// on a slot but no driver has confirmed it yet within the set time window.
///
/// This screen is non-dismissible by design (no back button, no tap-outside
/// dismiss) since a confirmation decision is required before the driver
/// can continue using the app. If the driver does not respond before
/// [responseSeconds] runs out, [onTimeout] fires so the caller can flag
/// an anomaly on the dashboard, per the system's anomaly detection rules.
class ParkingSlotConfirmationScreen extends StatefulWidget {
  final String slotId;
  final String floorLabel;
  final int responseSeconds;
  final VoidCallback onConfirm;
  final VoidCallback onNotMySlot;
  final VoidCallback onTimeout;

  const ParkingSlotConfirmationScreen({
    super.key,
    required this.slotId,
    required this.floorLabel,
    this.responseSeconds = 60,
    required this.onConfirm,
    required this.onNotMySlot,
    required this.onTimeout,
  });

  @override
  State<ParkingSlotConfirmationScreen> createState() =>
      _ParkingSlotConfirmationScreenState();
}

class _ParkingSlotConfirmationScreenState
    extends State<ParkingSlotConfirmationScreen> {
  late int _secondsLeft;
  Timer? _timer;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.responseSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        widget.onTimeout();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    setState(() => _isSubmitting = true);
    _timer?.cancel();
    // TODO: Write { confirmed: true } to the slot's Firebase document here.
    widget.onConfirm();
  }

  void _handleNotMySlot() {
    _timer?.cancel();
    // TODO: Surface this to the guard/admin flow, since the sensor detected
    // occupancy that the logged-in driver does not recognize as their own.
    widget.onNotMySlot();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Blocking: the driver cannot back out without making a decision.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.darkNavy,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),

                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.local_parking,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Did you park here?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'A vehicle was detected in ${widget.floorLabel} \u2014 ${widget.slotId}. Confirm so we can keep this slot accurate for other drivers.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),

                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        widget.slotId,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.floorLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.white54),
                    const SizedBox(width: 6),
                    Text(
                      'Respond within ${_secondsLeft}s',
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.slotAvailable,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Yes, this is my slot',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _isSubmitting ? null : _handleNotMySlot,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'This is not my slot',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
