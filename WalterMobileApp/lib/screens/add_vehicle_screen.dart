import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _licenseController = TextEditingController();
  List<String> _registeredPlates = [];

  void _showToast(String msg, {Color backgroundColor = const Color(0xFF0D4A91)}) {
    Fluttertoast.showToast(
      msg: msg,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: backgroundColor,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  Future<DocumentReference<Map<String, dynamic>>> _userDoc() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No user signed in.');
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  @override
  void initState() {
    super.initState();
    _loadPlates();
  }

  Future<void> _loadPlates() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data();
    if (data != null) {
      final plates = <String>[];

      if (data['plateNumber'] != null) plates.add(data['plateNumber']);

      if (data['plateNumbers'] != null) {
        plates.addAll(List<String>.from(data['plateNumbers']));
      }

      setState(() => _registeredPlates = plates.toSet().toList());
    }
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final newPlate = _licenseController.text.trim().toUpperCase();

    if (newPlate.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'plateNumbers': FieldValue.arrayUnion([newPlate])
      });
      setState(() {
        _registeredPlates.add(newPlate);
        _licenseController.clear();
      });
      _showToast('Vehicle plate added.');
    } else {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'plateNumbers': _registeredPlates});
    }
  }

  Future<void> _removePlate(String plate) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _registeredPlates.remove(plate);
    });

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({'plateNumbers': _registeredPlates});

    _showToast('Vehicle plate removed.');
  }

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        elevation: 16,
        color: const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionTitle('New Vehicle'),
                      const SizedBox(height: 8),
                      _sectionSubtitle('ADD NEW VEHICLE PLATE NUMBER'),
                      const SizedBox(height: 12),
                      _buildPlateForm(),
                      const SizedBox(height: 24),
                      _sectionTitle('Registered Vehicle Plate Number'),
                      const SizedBox(height: 12),
                      _buildPlatesList(),
                      const SizedBox(height: 24),
                      _buildPrimaryButton('SAVE', _save),
                      const SizedBox(height: 12),
                      _buildSecondaryButton(
                          'CANCEL', () => Navigator.pop(context)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlateForm() {
    return Form(
      key: _formKey,
      child: TextFormField(
        controller: _licenseController,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          UpperCaseTextFormatter(),
        ],
        decoration: _inputDecoration(
          hintText: 'Vehicle Plate Number',
          hintStyle: const TextStyle(color: Color(0xFFB0B6C3)),
        ),
        validator: (value) => value?.trim().isEmpty == true
            ? 'Please enter a plate number'
            : null,
      ),
    );
  }

  Widget _buildHeader() => Container(
        decoration: const BoxDecoration(color: Color(0xFF0D4A91)),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: const Text(
          'Account Details | Vehicle Plate Number',
          style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold),
        ),
      );

  Widget _sectionTitle(String text) => Text(
        text,
        style:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      );

  Widget _sectionSubtitle(String text) => Text(
        text,
        style:
            const TextStyle(fontSize: 12, color: Color(0xFF7A7D84)),
      );

  InputDecoration _inputDecoration(
      {required String hintText, required TextStyle hintStyle}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE3E6EB)),
    );

    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF8F9FB),
      hintText: hintText,
      hintStyle: hintStyle,
      border: border,
      enabledBorder: border,
    );
  }

  Widget _buildPlatesList() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E6EB)),
      ),
      child: Column(
        children: [
          if (_registeredPlates.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No registered vehicle plate number yet.',
                style: TextStyle(color: Color(0xFF7A7D84)),
              ),
            )
          else
            for (var i = 0; i < _registeredPlates.length; i++) ...[
              ListTile(
                title: Text(
                  _registeredPlates[i],
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: _registeredPlates.length > 1
                    ? TextButton(
                        onPressed: () =>
                            _removePlate(_registeredPlates[i]),
                        child: const Text(
                          'Remove',
                          style: TextStyle(
                            color: Color(0xFF0D4A91),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : null,
              ),
              if (i < _registeredPlates.length - 1)
                const Divider(height: 1, color: Color(0xFFDDE1E7)),
            ],
        ],
      ),
    );
  }

  Widget _buildPrimaryButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0D4A91),
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white),
      ),
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
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0D4A91)),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
