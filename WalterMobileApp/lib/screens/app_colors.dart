import 'package:flutter/material.dart';

/// Shared color palette for the parking app.
/// Keeps the Waltermart blue as the primary brand color,
/// with semantic green/red for slot availability.
class AppColors {
  AppColors._();

  static const Color primaryBlue = Color(0xFF1565D8);
  static const Color darkNavy = Color(0xFF0F2A4A);
  static const Color background = Color(0xFFF7F8FA);
  static const Color cardBackground = Colors.white;

  static const Color slotAvailable = Color(0xFF1FA665);
  static const Color slotAvailableBg = Color(0xFFE1F5EE);
  static const Color slotOccupied = Color(0xFFE5484D);
  static const Color slotOccupiedBg = Color(0xFFFCEBEB);

  static const Color textPrimary = Color(0xFF1A1F2B);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);

  static const Color border = Color(0xFFE5E7EB);
}