import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../main.dart' show AuthWrapper;
import '../theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _nameController = TextEditingController();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  String _verificationId = '';
  bool _codeSent = false;
  bool _isLoading = false;
  bool _isNewUserFlow = false;
  UserCredential? _userCredential;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // Send SMS verification code
  Future<void> _sendCode() async {
    final phoneNum = _phoneController.text.trim();
    if (phoneNum.isEmpty) {
      _showSnackBar('Please enter your phone number');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNum,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-resolution (on some Android devices)
          final userCred = await _auth.signInWithCredential(credential);
          await _handleUserSetup(userCred);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          _showSnackBar('Verification failed: ${e.message}');
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _codeSent = true;
            _isLoading = false;
          });
          _showSnackBar('Verification code sent!');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Error: $e');
    }
  }

  // Verify OTP SMS Code
  Future<void> _verifyOtp() async {
    final smsCode = _otpController.text.trim();
    if (smsCode.isEmpty) {
      _showSnackBar('Please enter the verification code');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: smsCode,
      );

      final userCred = await _auth.signInWithCredential(credential);
      await _handleUserSetup(userCred);
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Invalid code. Please try again.');
    }
  }

  // Handle checking if user exists in Firestore, and onboarding them if new
  Future<void> _handleUserSetup(UserCredential userCred) async {
    final user = userCred.user;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final userDocRef = _db.collection('users').doc(user.uid);
    final docSnapshot = await userDocRef.get();

    if (!docSnapshot.exists) {
      // New user flow: Ask for display name
      setState(() {
        _userCredential = userCred;
        _isNewUserFlow = true;
        _isLoading = false;
      });
    } else {
      // Existing user: explicitly navigate to AuthWrapper which will route
      // to the correct dashboard. This is more reliable than waiting for
      // the parent StreamBuilder to react to authStateChanges() on Flutter Web.
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (route) => false,
        );
      }
    }
  }

  // Save new user info
  Future<void> _saveNewUser() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnackBar('Please enter your full name');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = _userCredential!.user!.uid;
      final phone = _userCredential!.user!.phoneNumber ?? _phoneController.text.trim();

      await _db.collection('users').doc(uid).set({
        'uid': uid,
        'phoneNumber': phone,
        'name': name,
        'role': 'athlete', // default role
        'isResident': false,
        'residencyStatus': 'none',
        'residencyProofUrl': '',
        'photoUrl': '',
        'strikesCount': 0,
        'banUntil': null,
        'hasSignedWaiver': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Error saving account: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.primary),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Center(
            child: SingleChildScrollView(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Icon & Title
                      const Center(
                        child: Icon(
                          Icons.sports_basketball,
                          size: 72,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          "WHO'S GOT NEXT?",
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: AppTheme.primary,
                                letterSpacing: 1.5,
                              ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          "Community Open Run Sign-up",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(height: 32),

                      if (_isLoading)
                        const Center(
                          child: CircularProgressIndicator(color: AppTheme.primary),
                        )
                      else if (_isNewUserFlow) ...[
                        // Step 3: Name Registration for new users
                        Text(
                          "Onboarding Profile",
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _nameController,
                          keyboardType: TextInputType.name,
                          decoration: const InputDecoration(
                            labelText: "Full Name",
                            hintText: "Enter your first and last name",
                            prefixIcon: Icon(Icons.person, color: AppTheme.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _saveNewUser,
                          child: const Text("Create Athlete Account"),
                        ),
                      ] else if (!_codeSent) ...[
                        // Step 1: Phone number entry
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: "Phone Number",
                            hintText: "+15551234567",
                            prefixIcon: Icon(Icons.phone, color: AppTheme.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _sendCode,
                          child: const Text("Send Verification Code"),
                        ),
                      ] else ...[
                        // Step 2: OTP Entry
                        TextField(
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Verification Code",
                            hintText: "6-digit OTP",
                            prefixIcon: Icon(Icons.lock, color: AppTheme.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _verifyOtp,
                          child: const Text("Verify & Login"),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => setState(() => _codeSent = false),
                          child: const Text("Change Phone Number"),
                        ),
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
}
