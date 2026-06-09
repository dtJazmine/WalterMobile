import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'add_vehicle_screen.dart';
import 'change_phone_screen.dart';
import 'change_password_screen.dart';
import 'menu_drawer.dart';

class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Stream<DocumentSnapshot<Map<String, dynamic>>>? getUserStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
  }

  List<String> _extractPlates(Map<String, dynamic> userData) {
    final plates = <String>[];
    if (userData['plateNumber'] != null) {
      plates.add(userData['plateNumber'] as String);
    }
    if (userData['plateNumbers'] != null) {
      plates.addAll(List<String>.from(userData['plateNumbers']));
    }
    return plates.toSet().toList();
  }

  @override
  Widget build(BuildContext context) {
    final userStream = getUserStream();

    return Scaffold(
      key: _scaffoldKey,
      drawerEnableOpenDragGesture: true,
      backgroundColor: const Color(0xFFF5F7FB),
      drawer: const MenuDrawer(activeItem: 'settings'),
      drawerScrimColor: const Color(0x33000000),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(context, userStream),
              const SizedBox(height: 24),
              const Text(
                'Account Details',
                style: TextStyle(
                  color: Color(0xFF1F2A37),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Manage your profile details',
                style: TextStyle(
                  color: Color(0xFF7A7D84),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: userStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const Text("No user data found");
                  }

                  final userData = snapshot.data!.data()!;
                  final uniquePlates = _extractPlates(userData);

                  return Column(
                    children: [
                      _buildInfoCard(
                        title: 'Vehicle Plate Number',
                        actionLabel: 'Edit',
                        onActionTap: () {
                          _showPopup(context, const AddVehicleScreen());
                        },
                        children: [
                          if (uniquePlates.isEmpty)
                            const Text("No registered plate yet",
                                style: TextStyle(color: Color(0xFF7A7D84)))
                          else
                            for (var plate in uniquePlates)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  plate,
                                  style: const TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInfoCard(
                        title: 'Phone',
                        actionLabel: 'Change',
                        onActionTap: () {
                          _showPopup(context, const ChangePhoneScreen());
                        },
                        children: [
                          Text(userData['phoneNumber'] ?? '',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInfoCard(
                        title: 'Password',
                        actionLabel: 'Change',
                        onActionTap: () {
                          _showPopup(context, const ChangePasswordScreen());
                        },
                        children: [
                          Text(
                            '•' * (userData['passwordLength'] ?? 8),
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, Stream<DocumentSnapshot<Map<String, dynamic>>>? userStream) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.menu, color: Color(0xFF0D4A91)),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        const Spacer(),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: userStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Text("Loading...");
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Text("No user");
            }
            final userData = snapshot.data!.data()!;
            return Text(
              "Hello, ${userData['name'] ?? ''}",
              style: const TextStyle(
                color: Color(0xFF1F2A37),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0xFF0D4A91),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String actionLabel,
    required VoidCallback onActionTap,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3E6EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              GestureDetector(
                onTap: onActionTap,
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF0D4A91),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Future<void> _showPopup(BuildContext context, Widget child) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: const Color(0x33000000),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              color: const Color(0x33000000),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GestureDetector(
                      onTap: () {},
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
