import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Add for HapticFeedback
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/app_colors.dart';
import '../core/app_drawer.dart';
import '../services/maternal_health_service.dart';
import '../services/voice_input_service.dart';

class MaternalHealthFormScreen extends StatefulWidget {
  const MaternalHealthFormScreen({super.key});

  @override
  State<MaternalHealthFormScreen> createState() => _MaternalHealthFormScreenState();
}

class _MaternalHealthFormScreenState extends State<MaternalHealthFormScreen> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedPatientId;
  String? _selectedPatientName;
  List<Map<String, dynamic>> _patients = [];
  bool _isLoadingPatients = true;
  bool _isAnalyzing = false;
  bool _isListening = false;
  final VoiceInputService _voiceService = VoiceInputService();

  // Form Controllers
  final _ageController = TextEditingController();
  final _sysBpController = TextEditingController();
  final _diaBpController = TextEditingController();
  final _hrController = TextEditingController();
  final _tempController = TextEditingController();
  final _bsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  @override
  void dispose() {
    _ageController.dispose();
    _sysBpController.dispose();
    _diaBpController.dispose();
    _hrController.dispose();
    _tempController.dispose();
    _bsController.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('patients')
          .where('midwifeId', isEqualTo: user.uid)
          .get();

      setState(() {
        _patients = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
        _isLoadingPatients = false;
      });
    } catch (e) {
      debugPrint('Error loading patients: $e');
      setState(() => _isLoadingPatients = false);
    }
  }

  void _clearForm() {
    setState(() {
      _selectedPatientId = null;
      _selectedPatientName = null;
      _ageController.clear();
      _sysBpController.clear();
      _diaBpController.clear();
      _hrController.clear();
      _tempController.clear();
      _bsController.clear();
    });
  }

  Future<void> _toggleVoiceInput() async {
    if (_isListening) {
      await _voiceService.stopListening();
      setState(() => _isListening = false);
      return;
    }

    final success = await _voiceService.init();
    if (!success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
      return;
    }

    setState(() => _isListening = true);
    await HapticFeedback.mediumImpact();

    await _voiceService.startListening(
      onResult: (text) {
        _parseVoiceInput(text);
      },
      onDone: () {
        if (mounted) {
          setState(() => _isListening = false);
        }
      },
    );
  }

  void _parseVoiceInput(String text) {
    debugPrint('Recognized: $text');
    final lowerText = text.toLowerCase();

    // Simple regex-based parsing
    final ageMatch = RegExp(r'age\s*(\d+)').firstMatch(lowerText);
    if (ageMatch != null) _ageController.text = ageMatch.group(1)!;

    final sysMatch = RegExp(r'(systolic|blood pressure high)\s*(\d+)').firstMatch(lowerText);
    if (sysMatch != null) _sysBpController.text = sysMatch.group(2)!;

    final diaMatch = RegExp(r'(diastolic|blood pressure low)\s*(\d+)').firstMatch(lowerText);
    if (diaMatch != null) _diaBpController.text = diaMatch.group(2)!;

    final hrMatch = RegExp(r'(heart rate|pulse)\s*(\d+)').firstMatch(lowerText);
    if (hrMatch != null) _hrController.text = hrMatch.group(2)!;

    final tempMatch = RegExp(r'(temperature|temp|body temp)\s*(\d+\.?\d*)').firstMatch(lowerText);
    if (tempMatch != null) _tempController.text = tempMatch.group(2)!;

    final bsMatch = RegExp(r'(sugar|blood sugar|bs)\s*(\d+\.?\d*)').firstMatch(lowerText);
    if (bsMatch != null) _bsController.text = bsMatch.group(2)!;

    HapticFeedback.lightImpact();
  }

  Future<void> _analyzeRisk() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPatientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a patient first')),
      );
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final features = [
        double.parse(_ageController.text),
        double.parse(_sysBpController.text),
        double.parse(_diaBpController.text),
        double.parse(_bsController.text),
        double.parse(_tempController.text),
        double.parse(_hrController.text),
      ];

      final result = await MaternalHealthService.predict(features);

      // Trigger Haptic Feedback if risk is not low
      if (result.predictionScore >= 3) {
        await HapticFeedback.vibrate();
      }

      if (!mounted) return;

      Navigator.pushNamed(
        context,
        '/maternal-health-result',
        arguments: {
          'patientName': _selectedPatientName,
          'patientId': _selectedPatientId,
          'result': result,
          'vitals': features,
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Analysis failed: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      drawer: const AppDrawer(currentRoute: '/maternal-health'),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: AppColors.textPrimary),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text(
          'Midwify',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'New Assessment',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.grey200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Patient Name', Icons.person_outline),
                    const SizedBox(height: 8),
                    _buildPatientDropdown(),
                    const SizedBox(height: 20),

                    _buildLabel('Age', Icons.calendar_today_outlined),
                    const SizedBox(height: 8),
                    _buildTextField(_ageController, 'Age', TextInputType.number),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('SystolicBP', Icons.monitor_heart_outlined, color: Colors.red),
                              const SizedBox(height: 8),
                              _buildTextField(_sysBpController, 'mmHg', TextInputType.number),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('DiastolicBP', Icons.show_chart, color: Colors.blue),
                              const SizedBox(height: 8),
                              _buildTextField(_diaBpController, 'mmHg', TextInputType.number),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('HeartRate', Icons.favorite_border, color: const Color(0xFFE91E7B)),
                              const SizedBox(height: 8),
                              _buildTextField(_hrController, 'bpm', TextInputType.number),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('BodyTemp', Icons.thermostat_outlined, color: Colors.orange),
                              const SizedBox(height: 8),
                              _buildTextField(_tempController, 'F', const TextInputType.numberWithOptions(decimal: true)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _buildLabel('BS', Icons.water_drop_outlined, color: Colors.purple[300]),
                    const SizedBox(height: 8),
                    _buildTextField(_bsController, 'mmol/L', const TextInputType.numberWithOptions(decimal: true)),
                    const SizedBox(height: 32),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _clearForm,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Clear'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(color: AppColors.grey200),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isAnalyzing ? null : _analyzeRisk,
                            icon: _isAnalyzing
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.monitor_heart),
                            label: Text(_isAnalyzing ? 'Analyzing...' : 'Analyze Risk'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE91E7B),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text, IconData icon, {Color? color}) {
    return Row(
      children: [
        if (icon != Icons.person_outline && icon != Icons.calendar_today_outlined) ...[
          Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, TextInputType type) {
    return TextFormField(
      controller: controller,
      keyboardType: type,
      validator: (value) => value == null || value.isEmpty ? 'Required' : null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.grey400),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.grey200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.grey200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE91E7B), width: 1.5),
        ),
      ),
    );
  }

  Widget _buildPatientDropdown() {
    if (_isLoadingPatients) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.grey200),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('Loading patients...', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    if (_patients.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.grey200),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('No active patients found', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return DropdownButtonFormField<String>(
      value: _selectedPatientId,
      decoration: InputDecoration(
        hintText: 'Select Patient',
        hintStyle: TextStyle(color: AppColors.grey400),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.grey200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.grey200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE91E7B), width: 1.5),
        ),
      ),
      items: _patients.map((p) {
        return DropdownMenuItem(
          value: p['id'] as String,
          child: Text(p['fullName'] ?? 'Unknown Patient'),
        );
      }).toList(),
      onChanged: (val) {
        final selected = _patients.firstWhere((p) => p['id'] == val);
        setState(() {
          _selectedPatientId = val;
          _selectedPatientName = selected['fullName'];
          // Auto-fill age
          if (selected['age'] != null) {
            _ageController.text = selected['age'].toString();
          }
        });
      },
    );
  }
}
