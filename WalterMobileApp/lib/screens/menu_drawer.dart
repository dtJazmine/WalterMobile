import 'package:flutter/material.dart';
import 'account_details_screen.dart';
import 'welcome_screen.dart';
import 'home_screen.dart';

class MenuDrawer extends StatelessWidget {
  final String activeItem;
  const MenuDrawer({super.key, required this.activeItem});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                'assets/images/Walter_Mart_new_logo.png',
                height: 60,
              ),
              const SizedBox(height: 24),
              const Divider(color: Color(0xFFE3E6EB), thickness: 1),
              const SizedBox(height: 24),
              const Text(
                'MENU',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3A4552),
                ),
              ),
              const SizedBox(height: 16),
              _buildDrawerMenuItem(
                selected: activeItem == 'home',
                icon: Icons.local_parking,
                label: 'Live Parking Map',
                onTap: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                ),
              ),
              const SizedBox(height: 16),
              _buildDrawerMenuItem(
                selected: activeItem == 'settings',
                icon: Icons.settings,
                label: 'Settings',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountDetailsScreen()),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE42B40),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (route) => false,
                ),
                child: const Text(
                  'Sign Out',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerMenuItem({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

    if (selected) {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0D4A91),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          alignment: Alignment.centerLeft,
          shape: buttonShape,
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 24),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );
    }

    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF374151),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
        alignment: Alignment.centerLeft,
        shape: buttonShape,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 24, color: const Color(0xFF374151)),
      label: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}
