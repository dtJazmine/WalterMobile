import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _isLoading = false;

  void _showToast(String msg, {Color backgroundColor = Colors.redAccent}) {
    Fluttertoast.showToast(
      msg: msg,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: backgroundColor,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  Widget _buildPrimaryAction(String label, VoidCallback onPressed) {
    return _isLoading
        ? const Center(
            child: CircularProgressIndicator(color: Color(0xFF0D4A91)))
        : _buildPrimaryButton(label, onPressed);
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No user signed in.');

      // Re-authenticate with the current password first
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentController.text,
      );

      await user.reauthenticateWithCredential(credential);

      // Re-auth passed — update password in Firebase Auth
      await user.updatePassword(_newController.text);

      // Keep Firestore password field in sync
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'password': _newController.text});

      if (!mounted) return;

      _showToast(
        'Password changed successfully! Please sign in again.',
        backgroundColor: const Color(0xFF0D4A91),
      );

      await FirebaseAuth.instance.signOut(); // ← signs out current device
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);

    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          message = 'Current password is incorrect.';
          break;
        case 'weak-password':
          message = 'New password must be at least 6 characters.';
          break;
        case 'requires-recent-login':
          message = 'Session expired. Please sign in again.';
          break;
        default:
          message = 'Something went wrong: ${e.message}';
      }
      if (!mounted) return;
      _showToast(message);
    } catch (e) {
      if (!mounted) return;
      _showToast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        elevation: 16,
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF0D4A91),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Account Details | Change Password',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Change current password',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'CHANGE PASSWORD',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF7A7D84),
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),
                        _buildLabel('CURRENT PASSWORD'),
                        const SizedBox(height: 8),
                        _buildPasswordField(
                          _currentController,
                          'Current Password',
                          _showCurrent,
                          () => setState(() => _showCurrent = !_showCurrent),
                        ),
                        const SizedBox(height: 18),
                        _buildLabel('NEW PASSWORD'),
                        const SizedBox(height: 8),
                        _buildPasswordField(
                          _newController,
                          'New Password',
                          _showNew,
                          () => setState(() => _showNew = !_showNew),
                          extraValidator: (value) {
                            if (value != null && value.length < 6)
                              return 'Password must be at least 6 characters';
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        _buildLabel('CONFIRM NEW PASSWORD'),
                        const SizedBox(height: 8),
                        _buildPasswordField(
                          _confirmController,
                          'Confirm New Password',
                          _showConfirm,
                          () => setState(
                              () => _showConfirm = !_showConfirm),
                          extraValidator: (value) {
                            if (value != _newController.text)
                              return 'Passwords do not match';
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        _buildPrimaryAction('UPDATE', _update),
                        const SizedBox(height: 12),
                        _buildSecondaryButton(
                            'CANCEL', () => Navigator.pop(context)),
                      ],
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

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF7A7D84),
          fontWeight: FontWeight.w700),
    );
  }

  Widget _buildPasswordField(
    TextEditingController controller,
    String hint,
    bool visible,
    VoidCallback toggle, {
    String? Function(String?)? extraValidator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: !visible,
      decoration: _inputDecoration(
        hint,
        suffixIcon: IconButton(
          icon: Icon(
              visible ? Icons.visibility : Icons.visibility_off,
              color: const Color(0xFF0D4A91)),
          onPressed: toggle,
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty)
          return 'This field is required';
        return extraValidator?.call(value);
      },
    );
  }

  InputDecoration _inputDecoration(String hint, {Widget? suffixIcon}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE3E6EB)),
    );
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF8F9FB),
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFB0B6C3)),
      suffixIcon: suffixIcon,
      border: border,
      enabledBorder: border,
    );
  }

  Widget _buildPrimaryButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0D4A91),
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onPressed,
      child: Text(label,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSecondaryButton(String label, VoidCallback onPressed) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: Color(0xFF0D4A91)),
      ),
      onPressed: onPressed,
      child: Text(label,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0D4A91))),
    );
  }
}
