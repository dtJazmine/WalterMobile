import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'menu_drawer.dart';
import 'parking_map_screen.dart';
import 'qr_generation_screen.dart'; // for the shared FloatingQrButton

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D4A91),
        // No title \u2014 the hamburger (from `drawer` below) still shows
        // automatically on the left via automaticallyImplyLeading.
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Streams the user's Firestore doc so the greeting stays
                // in sync if their name is ever edited elsewhere in the
                // app, without needing to rebuild HomeScreen manually.
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: uid == null
                      ? null
                      : FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .snapshots(),
                  builder: (context, snapshot) {
                    final userData = snapshot.data?.data() ?? {};
                    return Text(
                      "Hello, ${userData['name'] ?? ''}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, color: Color(0xFF0D4A91), size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
      drawer: const MenuDrawer(activeItem: 'home'),
      body: const SafeArea(child: ParkingMapBody()),
      // Pinned outside the scrollable ParkingMapBody \u2014 stays fixed
      // at the bottom of the screen no matter how far the parking map
      // content above is scrolled.
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.zero,
        child: FloatingQrButton(
          label: 'Generate QR code',
          onPressed: () {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid == null) {
              // Not signed in \u2014 shouldn't normally happen if this
              // screen is behind auth, but guard anyway.
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
