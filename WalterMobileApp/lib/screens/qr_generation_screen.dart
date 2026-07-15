import 'dart:async';
import 'package:flutter/material.dart';
import 'app_colors.dart';
// Add to pubspec.yaml: qr_flutter: ^4.1.0
// import 'package:qr_flutter/qr_flutter.dart';

class QrGenerationScreen extends StatefulWidget {
  final String accountId;

  const QrGenerationScreen({
    super.key,
    required this.accountId,
  });

  @override
  State<QrGenerationScreen> createState() => _QrGenerationScreenState();
}

class _QrGenerationScreenState extends State<QrGenerationScreen> {
  // 3 minutes.
  static const int _expirySeconds = 180;
  int _secondsLeft = _expirySeconds;
  Timer? _timer;
  String? _qrPayload;

  @override
  void initState() {
    super.initState();
    _generateQr();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _generateQr() {
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(seconds: _expirySeconds));
    _qrPayload =
        '${widget.accountId}|${now.millisecondsSinceEpoch}|${expiresAt.millisecondsSinceEpoch}';

    setState(() => _secondsLeft = _expirySeconds);

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) timer.cancel();
      });
    });
  }

  String get _formattedTime {
    final m = (_secondsLeft.clamp(0, _expirySeconds) ~/ 60)
        .toString()
        .padLeft(2, '0');
    final s = (_secondsLeft.clamp(0, _expirySeconds) % 60)
        .toString()
        .padLeft(2, '0');
    return '$m:$s';
  }

  bool get _isExpired => _secondsLeft <= 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          'Entry QR code',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        ),
      ),
      // Scrollable content only. The floating button lives outside this,
      // in bottomNavigationBar, so it never moves when the content scrolls.
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            children: [
              const Text(
                'Show this at the entrance gate',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              // QR display box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    AnimatedOpacity(
                      opacity: _isExpired ? 0.35 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        width: 200,
                        height: 200,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _qrPayload == null
                            ? const SizedBox.shrink()
                            // Replace with QrImageView(data: _qrPayload!, size: 176)
                            : const Center(
                                child: Icon(Icons.qr_code_2,
                                    size: 160, color: AppColors.textPrimary),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.access_time,
                            size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          _isExpired ? 'Expired' : 'Expires in',
                          style: const TextStyle(
                              fontSize: 14, color: Colors.white),
                        ),
                        if (!_isExpired) ...[
                          const SizedBox(width: 6),
                          Text(
                            _formattedTime,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: _InfoRow(label: 'Account ID', value: widget.accountId),
              ),

              const SizedBox(height: 14),
              Text(
                _isExpired
                    ? 'This code has expired. Generate a new one.'
                    : 'This code can only be scanned once',
                style:
                    const TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),

              // Small bottom padding so the last content isn't flush
              // against the floating button when scrolled all the way down.
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      // Pinned outside the scrollable body \u2014 stays fixed at the bottom
      // of the screen no matter how far the content above is scrolled.
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.zero,
        child: FloatingQrButton(
          label: 'Generate QR Code',
          onPressed: _generateQr,
        ),
      ),
    );
  }
}

/// Reusable pill-shaped button with a circular QR icon floating above
/// and overlapping its top border. Used here and in parking_map_screen.dart
/// so both screens share one implementation.
class FloatingQrButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final double iconSize;

  const FloatingQrButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.iconSize = 60,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Padding(
            padding: EdgeInsets.only(top: iconSize / 2),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withOpacity(0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.primaryBlue, width: 2),
                  padding: const EdgeInsets.only(
                    left: 120,
                    right: 120,
                    top: 30,
                    bottom: 16,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: Container(
              width: iconSize,
              height: iconSize,
              decoration: const BoxDecoration(
                color: AppColors.primaryBlue,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.qr_code_2,
                  color: Colors.white, size: iconSize * 0.47),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
