import 'dart:async';
import 'package:flutter/material.dart';
import 'app_colors.dart';
// Add to pubspec.yaml: qr_flutter: ^4.1.0
import 'package:qr_flutter/qr_flutter.dart';

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
  // Once the code hits 0, wait this long showing "Expired" before quietly
  // swapping in a fresh one \u2014 long enough to register as a real event,
  // short enough that the screen never feels stuck/broken.
  static const int _autoRefreshDelaySeconds = 3;
  // Last N seconds before expiry: ring + timer flip to amber as a heads-up.
  static const int _warningThresholdSeconds = 15;

  int _secondsLeft = _expirySeconds;
  Timer? _countdownTimer;
  Timer? _autoRefreshTimer;
  String? _qrPayload;
  int _generation = 0; // bumps every regen, used as AnimatedSwitcher key

  @override
  void initState() {
    super.initState();
    _generateQr();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _generateQr() {
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(seconds: _expirySeconds));

    // Payload changes on every generation \u2014 timestamp + a lightweight
    // nonce \u2014 so the actual QR pattern visibly redraws each refresh,
    // not just the countdown label next to it.
    final nonce = now.microsecondsSinceEpoch.toRadixString(36);
    _qrPayload =
        '${widget.accountId}|${now.millisecondsSinceEpoch}|${expiresAt.millisecondsSinceEpoch}|$nonce';

    _autoRefreshTimer?.cancel();
    _countdownTimer?.cancel();

    setState(() {
      _secondsLeft = _expirySeconds;
      _generation++;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          timer.cancel();
          _scheduleAutoRefresh();
        }
      });
    });
  }

  // After sitting expired for a moment, generate a new code automatically
  // \u2014 mirrors how real gate-entry QR systems behave, where you're never
  // stuck staring at a dead code waiting to tap a button.
  void _scheduleAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer =
        Timer(const Duration(seconds: _autoRefreshDelaySeconds), () {
      if (mounted) _generateQr();
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
  bool get _isWarning =>
      !_isExpired && _secondsLeft <= _warningThresholdSeconds;

  double get _progress =>
      (_secondsLeft.clamp(0, _expirySeconds)) / _expirySeconds;

  Color get _statusColor {
    if (_isExpired) return AppColors.slotOccupied;
    if (_isWarning) return const Color(0xFFF5A524); // amber heads-up
    return Colors.white;
  }

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
                'Show this at the entrance/exit gate',
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
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Thin ring that visibly drains as the code counts
                        // down, then snaps back full the instant a new
                        // code is generated. Small detail, but it's what
                        // makes the timer read as "live" instead of decor.
                        SizedBox(
                          width: 300,
                          height: 300,
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey('ring-$_generation'),
                            tween: Tween(begin: 1.0, end: 0.0),
                            duration: Duration(seconds: _secondsLeft > 0
                                ? _secondsLeft
                                : _expirySeconds),
                            curve: Curves.linear,
                            builder: (context, value, _) {
                              return CircularProgressIndicator(
                                value: _isExpired ? 1.0 : value,
                                strokeWidth: 4,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.18),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(_statusColor),
                              );
                            },
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween(begin: 0.92, end: 1.0)
                                    .animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: AnimatedOpacity(
                            key: ValueKey('qr-$_generation'),
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
                                  : QrImageView(
                                      data: _qrPayload!,
                                      size: 176,
                                      gapless: true,
                                      backgroundColor: Colors.white,
                                      eyeStyle: const QrEyeStyle(
                                        eyeShape: QrEyeShape.square,
                                        color: AppColors.textPrimary,
                                      ),
                                      dataModuleStyle:
                                          const QrDataModuleStyle(
                                        dataModuleShape:
                                            QrDataModuleShape.square,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        // Small "refreshing" spinner shown only during the
                        // brief expired-\u2192-new-code gap, so the transition
                        // reads as intentional rather than a glitch.
                        if (_isExpired)
                          Positioned(
                            bottom: 4,
                            child: _RefreshingPill(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isExpired ? Icons.refresh : Icons.access_time,
                          size: 16,
                          color: _statusColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isExpired ? 'Expired \u2014 refreshing' : 'Expires in',
                          style: TextStyle(fontSize: 14, color: _statusColor),
                        ),
                        if (!_isExpired) ...[
                          const SizedBox(width: 6),
                          Text(
                            _formattedTime,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _statusColor,
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
                    ? 'This code has expired. A new one is on its way.'
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
      // Still here for a manual refresh; auto-refresh on expiry means the
      // user isn't ever forced to tap it, but it's a handy override.
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

/// Tiny pulsing "generating a new code" indicator shown only in the gap
/// between a code expiring and the next one appearing.
class _RefreshingPill extends StatefulWidget {
  @override
  State<_RefreshingPill> createState() => _RefreshingPillState();
}

class _RefreshingPillState extends State<_RefreshingPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.textPrimary.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'Generating new code\u2026',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
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
                    color: AppColors.primaryBlue.withValues(alpha: 0.18),
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
