import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChangePhoneScreen extends StatefulWidget {
  const ChangePhoneScreen({super.key});

  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _pinController = TextEditingController();
  final _newPhoneController = TextEditingController();
  final _confirmPhoneController = TextEditingController();

  bool _showPassword = false;
  bool _isLoading = false;

  static const _stepTitles = [
    'STEP 1 OF 3 — CURRENT PASSWORD',
    'STEP 2 OF 3 — RECOVERY PIN',
    'STEP 3 OF 3 — NEW PHONE NUMBER',
  ];

  static const _stepSubtitles = [
    'Verify your current password',
    'Verify your recovery PIN',
    'Enter your new phone number',
  ];

  // 0 = current password, 1 = PIN, 2 = new phone number
  int _step = 0;

  User _requireUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No user signed in.');
    return user;
  }

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
            child:
                CircularProgressIndicator(color: Color(0xFF0D4A91)))
        : _buildPrimaryButton(label, onPressed);
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _pinController.dispose();
    _newPhoneController.dispose();
    _confirmPhoneController.dispose();
    super.dispose();
  }

  // ── Step 1: Verify current password ──────────────────────────
  Future<void> _verifyCurrentPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    try {
      final user = _requireUser();

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentPasswordController.text,
      );

      await user.reauthenticateWithCredential(credential);

      if (!mounted) return;
      setState(() => _step = 1);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message;
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          message = 'Current password is incorrect.';
          break;
        default:
          message = 'Something went wrong: ${e.message}';
      }
      _showToast(message);
    } catch (e) {
      if (!mounted) return;
      _showToast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Step 2: Verify PIN ────────────────────────────────────────
  Future<void> _verifyPin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    try {
      final user = _requireUser();

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) throw Exception('User data not found.');

      final storedPin = doc['pin'] as String;
      final enteredPin = _pinController.text.trim();

      if (enteredPin != storedPin) {
        if (!mounted) return;
        _showToast('Incorrect PIN. Please try again.');
        return;
      }

      if (!mounted) return;
      setState(() => _step = 2);
    } catch (e) {
      if (!mounted) return;
      _showToast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Step 3: Save new phone number ─────────────────────────────
  Future<void> _saveNewPhone() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    final newPhone = _newPhoneController.text.trim();
    final newEmail = '$newPhone@waltermart.com';

    try {
      final user = _requireUser();

      // Check if new phone number is already taken
      final existing = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: newPhone)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        if (!mounted) return;
        _showToast('This phone number is already in use.');
        return;
      }

      // Fetch all data BEFORE deleting the old account
      final oldDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final oldUid = user.uid;
      final oldData = oldDoc.data()!;
      final storedPassword = oldData['password'] as String;

      // Delete old Firebase Auth account
      await user.delete();

      // Recreate with new phone as email, same password
      final newCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: newEmail,
        password: storedPassword,
      );

      // Write Firestore doc under new UID with updated phone number
      await FirebaseFirestore.instance
          .collection('users')
          .doc(newCredential.user!.uid)
          .set({...oldData, 'phoneNumber': newPhone});

      // Delete old Firestore doc
      await FirebaseFirestore.instance
          .collection('users')
          .doc(oldUid)
          .delete();

      if (!mounted) return;

      _showToast(
        'Phone number updated successfully! Please sign in again.',
        backgroundColor: const Color(0xFF0D4A91),
      );

      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showToast('Error: ${e.message}');
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
                // ── Header ──
                Container(
                  decoration: const BoxDecoration(color: Color(0xFF0D4A91)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Account Details | Change Phone',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _stepSubtitles[_step],
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
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
                        Text(
                          _stepTitles[_step],
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF7A7D84),
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),

                        // ── Step 1: Current password ──
                        if (_step == 0) ...[
                          _buildLabel('CURRENT PASSWORD'),
                          const SizedBox(height: 8),
                          _buildPasswordField(),
                          const SizedBox(height: 24),
                          _buildPrimaryAction(
                              'CONTINUE', _verifyCurrentPassword),
                          const SizedBox(height: 12),
                          _buildSecondaryButton(
                              'CANCEL', () => Navigator.pop(context)),
                        ],

                        // ── Step 2: PIN ──
                        if (_step == 1) ...[
                          _buildLabel('RECOVERY PIN'),
                          const SizedBox(height: 8),
                          _buildPinField(),
                          const SizedBox(height: 24),
                          _buildPrimaryAction('VERIFY PIN', _verifyPin),
                          const SizedBox(height: 12),
                          _buildSecondaryButton('BACK', () {
                            setState(() {
                              _step = 0;
                              _pinController.clear();
                            });
                          }),
                        ],

                        // ── Step 3: New phone number ──
                        if (_step == 2) ...[
                          _buildLabel('NEW PHONE NUMBER'),
                          const SizedBox(height: 8),
                          _buildPhoneField(
                            _newPhoneController,
                            'New Phone Number',
                          ),
                          const SizedBox(height: 18),
                          _buildLabel('CONFIRM NEW PHONE NUMBER'),
                          const SizedBox(height: 8),
                          _buildPhoneField(
                            _confirmPhoneController,
                            'Confirm New Phone Number',
                            extraValidator: (value) {
                              if (value?.trim() !=
                                  _newPhoneController.text.trim())
                                return 'Phone numbers do not match';
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          _buildPrimaryAction('UPDATE', _saveNewPhone),
                          const SizedBox(height: 12),
                          _buildSecondaryButton('CANCEL', () {
                            Navigator.of(context).pop();
                          }),
                        ],
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

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _currentPasswordController,
      obscureText: !_showPassword,
      decoration: _inputDecoration(
        'Current Password',
        suffixIcon: IconButton(
          icon: Icon(
              _showPassword ? Icons.visibility : Icons.visibility_off,
              color: const Color(0xFF0D4A91)),
          onPressed: () =>
              setState(() => _showPassword = !_showPassword),
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty)
          return 'Password is required';
        return null;
      },
    );
  }

  Widget _buildPinField() {
    return TextFormField(
      controller: _pinController,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: _inputDecoration('4-digit Recovery PIN'),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return 'PIN is required';
        if (value.trim().length != 4) return 'PIN must be 4 digits';
        return null;
      },
    );
  }

  Widget _buildPhoneField(
    TextEditingController controller,
    String hint, {
    String? Function(String?)? extraValidator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ],
      decoration: _inputDecoration(hint),
      validator: (value) {
        final trimmed = value?.trim() ?? '';
        if (trimmed.isEmpty) return 'This field is required';
        if (trimmed.length != 11) return 'Phone number must be 11 digits';
        return extraValidator?.call(trimmed);
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
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
