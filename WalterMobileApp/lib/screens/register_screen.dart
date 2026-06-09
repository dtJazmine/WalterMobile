import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/shared_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _plateController = TextEditingController();
  final _contactController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _pinController = TextEditingController();     // ← new
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
        ? const CircularProgressIndicator(color: Color(0xFF0D4A91))
        : ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D4A91),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: onPressed,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _plateController.dispose();
    _contactController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _pinController.dispose();                          // ← new
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    final phone = _contactController.text.trim();
    final fakeEmail = '$phone@waltermart.com';
    final password = _passwordController.text;

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: fakeEmail,
        password: password,
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
        'name': _nameController.text.trim(),
        'plateNumber': _plateController.text.trim().toUpperCase(),
        'phoneNumber': phone,
        'pin': _pinController.text.trim(),             // ← new
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      _showToast(
        'Registration successful! Please sign in.',
        backgroundColor: const Color(0xFF0D4A91),
      );

      Navigator.pop(context);

    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'This phone number is already registered.';
          break;
        case 'weak-password':
          message = 'Password is too weak. Use at least 6 characters.';
          break;
        default:
          message = 'Registration failed. Please try again.';
      }
      if (!mounted) return;
      _showToast(message);
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    SizedBox(
                        height:
                            MediaQuery.of(context).size.height * 0.12),
                    const Center(child: LogoBlock()),
                    SizedBox(
                        height:
                            MediaQuery.of(context).size.height * 0.05),
                    _buildTextField(
                      controller: _nameController,
                      label: 'Name',
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 18),
                    _buildTextField(
                      controller: _plateController,
                      label: 'Vehicle Plate Number',
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 18),
                    _buildTextField(
                      controller: _contactController,
                      label: 'Contact Number',
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) return 'Contact number is required';
                        if (!RegExp(r'^\d+$').hasMatch(trimmed))
                          return 'Contact number must contain only digits';
                        if (trimmed.length != 11)
                          return 'Contact number must be exactly 11 digits';
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    _buildTextField(
                      controller: _passwordController,
                      label: 'Password',
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return 'Password is required';
                        if (value.length < 6)
                          return 'Password must be at least 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    _buildTextField(
                      controller: _confirmController,
                      label: 'Confirm Password',
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return 'Please confirm your password';
                        if (value != _passwordController.text)
                          return 'Passwords do not match';
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    // ── new PIN field ──
                    _buildTextField(
                      controller: _pinController,
                      label: '4-Digit Recovery PIN',
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) return 'Recovery PIN is required';
                        if (trimmed.length != 4)
                          return 'PIN must be exactly 4 digits';
                        return null;
                      },
                    ),
                    const SizedBox(height: 6),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Text(
                          'Remember this PIN — you\'ll need it to reset your password.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF0D4A91),
                          ),
                        ),
                      ),
                    ),
                    // ────────────────────
                    const SizedBox(height: 26),
                    _buildPrimaryAction('Sign Up', _signUp),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        filled: true,
        fillColor: obscureText ? const Color(0xFFEFEFFF) : Colors.white,
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
}
