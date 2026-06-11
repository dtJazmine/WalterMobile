import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String phoneNumber;

  const ResetPasswordScreen({super.key, required this.phoneNumber});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    final fakeEmail = '${widget.phoneNumber}@waltermart.com';
    final newPassword = _passwordController.text;

    try {
      // Fetch stored password from Firestore to re-authenticate
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: widget.phoneNumber)
          .limit(1)
          .get();

      if (query.docs.isEmpty) throw Exception('User not found.');

      final userDoc = query.docs.first;
      final storedPassword = userDoc['password'] as String;

      // Sign in with stored credentials to get a fresh auth session
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
        email: fakeEmail,
        password: storedPassword,
      );

      // Update password in Firebase Auth
      await userCredential.user!.updatePassword(newPassword);

      // Keep Firestore password field in sync
      await userDoc.reference.update({'password': newPassword});

      if (!mounted) return;

      Fluttertoast.showToast(
        msg: 'Password reset successfully! Please sign in.',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: const Color(0xFF0D4A91),
        textColor: Colors.white,
        fontSize: 16.0,
      );

      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);

    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'weak-password':
          message = 'Password must be at least 6 characters.';
          break;
        case 'wrong-password':
          message = 'Authentication failed. Please try again.';
          break;
        default:
          message = 'Reset failed: ${e.message}';
      }
      if (!mounted) return;
      Fluttertoast.showToast(
        msg: message,
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.redAccent,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    } catch (e) {
      if (!mounted) return;
      Fluttertoast.showToast(
        msg: 'Something went wrong. Please try again.',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.redAccent,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        constraints: const BoxConstraints.expand(),
        decoration: const BoxDecoration(
          color: Color(0xFFFEE101),
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20)
                  .copyWith(top: 40),
              child: SizedBox(
                height: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.vertical,
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Reset your Password',
                        style: TextStyle(
                          color: Color(0xFF0D4A91),
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                      _buildTextField(
                        controller: _passwordController,
                        label: 'Create New Password',
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'New password is required';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      _buildTextField(
                        controller: _confirmController,
                        label: 'Confirm Your Password',
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (value != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 30),
                      _isLoading
                          ? const CircularProgressIndicator(
                              color: Color(0xFF0D4A91))
                          : _buildActionButton('Save Password', _savePassword),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: label,
        hintStyle: const TextStyle(color: Color(0xFF6D6D83)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide:
              const BorderSide(color: Color(0xFF0D4A91), width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide:
              const BorderSide(color: Color(0xFF0D4A91), width: 2),
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildActionButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0D4A91),
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(60),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style:
            const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}
