import 'package:flutter/material.dart';

class LogoBlock extends StatelessWidget {
  const LogoBlock({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/Waltermart.png',
      height: 180,
    );
  }
}

class BackgroundPainter extends CustomPainter {
  const BackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF0D4A91);

    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * -0.12),
      size.width * 0.52,
      paint,
    );

    final path = Path()
      ..moveTo(-size.width * 0.16, size.height * 0.72)
      ..lineTo(size.width * 0.24, size.height * 0.6)
      ..lineTo(size.width * 0.42, size.height * 0.94)
      ..lineTo(size.width * 0.04, size.height * 0.98)
      ..close();

    canvas.drawPath(path, paint);

    final strokePaint = Paint()
      ..color = const Color(0xFF0D4A91)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final accentPath = Path()
      ..moveTo(size.width * 0.04, size.height * 0.78)
      ..lineTo(size.width * 0.04, size.height * 0.98)
      ..lineTo(size.width * 0.26, size.height * 0.86);

    canvas.drawPath(accentPath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}