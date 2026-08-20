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
  // swapping in a fresh one — long enough to register as a real event,
  // short enough that the screen never feels stuck/broken.
  static const int _autoRefreshDelaySeconds = 3;
  // Last N seconds before expiry: timer text flips to amber as a heads-up.
  static const int _warningThresholdSeconds = 15;

  int _secondsLeft = _expirySeconds;
  Timer? _countdownTimer;
  Timer? _autoRefreshTimer;
  String? _qrPayload;
  int _generation = 0; // bumps every regen, used as AnimatedSwitcher key

  // Whether the Account ID value is shown in plain text or masked.
  // Hidden by default; user can tap the eye icon to reveal it.
  bool _accountIdVisible = false;

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

    // Payload changes on every generation — timestamp + a lightweight
    // nonce — so the actual QR pattern visibly redraws each refresh,
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
  // — mirrors how real gate-entry QR systems behave, where you're never
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

  Color get _statusColor {
    if (_isExpired) return AppColors.slotOccupied;
    if (_isWarning) return const Color(0xFFF5A524); // amber heads-up
    return Colors.white;
  }

  // Masks the account ID with dots, keeping the same length so the
  // layout doesn't jump when toggling visibility.
  String get _maskedAccountId => '•' * widget.accountId.length;

  void _toggleAccountIdVisibility() {
    setState(() {
      _accountIdVisible = !_accountIdVisible;
    });
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
                              // ~4cm x 4cm on typical mobile density.
                              width: 280,
                              height: 280,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: _qrPayload == null
                                  ? const SizedBox.shrink()
                                  : QrImageView(
                                      data: _qrPayload!,
                                      size: 252,
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
                        // brief expired-→-new-code gap, so the transition
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
                          _isExpired ? 'Expired — refreshing' : 'Expires in',
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Account ID',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              _accountIdVisible
                                  ? widget.accountId
                                  : _maskedAccountId,
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: _toggleAccountIdVisibility,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                _accountIdVisible
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 18,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
      // No manual button — the code refreshes itself automatically
      // (see _scheduleAutoRefresh), including during the brief
      // "Expired — refreshing" window, so there's nothing for the user
      // to tap at any point in the flow.
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
          'Generating new code…',
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
///
/// [onPressed] is nullable — pass null to render it disabled/greyed-out
/// (e.g. while a QR code is still active and shouldn't be regenerable).
class FloatingQrButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  // Optional override for the circular icon size. Leave null (the
  // default) to let the button size itself responsively based on the
  // screen width — see build() below. Only pass this if some caller
  // ever needs to force a specific size regardless of screen.
  final double? iconSize;

  const FloatingQrButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = onPressed != null;
    // Dim both the icon and the button itself when disabled, so it reads
    // clearly as "not tappable right now" rather than looking broken.
    final Color iconColor =
        isEnabled ? AppColors.primaryBlue : AppColors.textTertiary;
    final Color borderColor =
        isEnabled ? AppColors.primaryBlue : AppColors.border;
    final Color labelColor =
        isEnabled ? Colors.black87 : AppColors.textTertiary;

    // Scale every dimension off the actual screen width instead of using
    // fixed numbers, so the pill neither crowds a small phone (iPhone
    // SE/7, ~375pt wide) nor looks tiny and lost on a big one (iPhone 15
    // Pro Max, ~430pt wide). Each value is clamped to a sensible
    // min/max range so it degrades gracefully outside that too (small
    // tablets, split-screen, etc.) instead of scaling without limit.
    final double screenWidth = MediaQuery.of(context).size.width;
    final double resolvedIconSize =
        iconSize ?? (screenWidth * 0.155).clamp(52.0, 68.0);
    final double horizontalPadding =
        (screenWidth * 0.22).clamp(56.0, 120.0);
    final double fontSize = (screenWidth * 0.047).clamp(15.0, 19.0);
    final double topPadding = resolvedIconSize * 0.5 + 4;

    return SizedBox(
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Padding(
            padding: EdgeInsets.only(top: resolvedIconSize / 2),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                boxShadow: isEnabled
                    ? [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : const [],
              ),
              child: OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.textPrimary,
                  disabledForegroundColor: AppColors.textTertiary,
                  side: BorderSide(color: borderColor, width: 2),
                  padding: EdgeInsets.only(
                    left: horizontalPadding,
                    right: horizontalPadding,
                    top: topPadding,
                    bottom: 16,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: Container(
              width: resolvedIconSize,
              height: resolvedIconSize,
              decoration: BoxDecoration(
                color: iconColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.qr_code_2,
                  color: Colors.white, size: resolvedIconSize * 0.47),
            ),
          ),
        ],
      ),
    );
  }
}
