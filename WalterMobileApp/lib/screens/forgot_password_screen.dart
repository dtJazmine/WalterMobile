import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'reset_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isLoading = false;
  bool _phoneVerified = false;

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
        ? const CircularProgressIndicator(color: Color(0xFF0D4A91))
        : _buildActionButton(label, onPressed);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  // ── Step 1: Check phone number exists ────────────────────────
  Future<void> _continueWithPhone() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: _phoneController.text.trim())
          .limit(1)
          .get();

      if (!mounted) return;

      if (query.docs.isEmpty) {
        _showToast('No account found for this phone number.');
      } else {
        setState(() => _phoneVerified = true);
      }
    } catch (e) {
      if (!mounted) return;
      _showToast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Step 2: Verify PIN then go to reset password screen ───────
  Future<void> _verifyPinAndProceed() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    final phone = _phoneController.text.trim();

    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: phone)
          .limit(1)
          .get();

      if (query.docs.isEmpty) throw Exception('User not found.');

      final storedPin = query.docs.first['pin'] as String;
      final enteredPin = _pinController.text.trim();

      if (enteredPin != storedPin) {
        if (!mounted) return;
        _showToast('Incorrect PIN. Please try again.');
        return;
      }

      // PIN correct — navigate to reset password screen
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(phoneNumber: phone),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showToast('Something went wrong. Please try again.');
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
                        'Forgot Password',
                        style: TextStyle(
                          color: Color(0xFF0D4A91),
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),

                      // ── Step 1: Phone number ──
                      if (!_phoneVerified) ...[
                        _buildTextField(
                          controller: _phoneController,
                          label: 'Enter Phone Number',
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          validator: (value) {
                            final trimmed = value?.trim() ?? '';
                            if (trimmed.isEmpty) {
                              return 'Phone number is required';
                            }
                            if (trimmed.length != 11) {
                              return 'Phone number must be exactly 11 digits';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        _buildPrimaryAction('Continue', _continueWithPhone),
                        const SizedBox(height: 12),
                        _buildActionButton(
                            'Cancel', () => Navigator.pop(context)),
                      ],

                      // ── Step 2: PIN ──
                      if (_phoneVerified) ...[
                        _buildTextField(
                          controller: _pinController,
                          label: 'Recovery PIN',
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'PIN is required';
                            }
                            if (value.trim().length != 4) {
                              return 'PIN must be 4 digits';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        _buildPrimaryAction('Verify PIN', _verifyPinAndProceed),
                        const SizedBox(height: 12),
                        _buildActionButton('Back', () {
                          setState(() {
                            _phoneVerified = false;
                            _pinController.clear();
                          });
                        }),
                      ],
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
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
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