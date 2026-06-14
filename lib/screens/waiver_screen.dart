import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../theme.dart';

class WaiverScreen extends StatefulWidget {
  const WaiverScreen({super.key});

  @override
  State<WaiverScreen> createState() => _WaiverScreenState();
}

class _WaiverScreenState extends State<WaiverScreen> {
  final FirebaseService _fbService = FirebaseService();
  bool _checked = false;
  bool _isLoading = false;

  Future<void> _submitWaiver() async {
    if (!_checked) return;

    setState(() => _isLoading = true);
    try {
      await _fbService.signWaiver();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("LIABILITY WAIVER"),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Liability Waiver & Release Form",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.primary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Please read and accept the waiver below to participate in open runs.",
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.surfaceLight),
                  ),
                  child: const SingleChildScrollView(
                    child: Text(
                      "COMMUNITY CENTER BASKETBALL LIABILITY WAIVER\n\n"
                      "1. Participation Risks: I understand that participating in basketball open runs involves physical exertion and contact, which carries inherent risks of physical injury, including but not limited to sprains, fractures, concussions, or cardiac events. I knowingly and freely assume all such risks, both known and unknown.\n\n"
                      "2. Indemnification: I hereby release, waive, and forever discharge the community center, the developers, and the organizers of the Who's Got Next app from any and all liability, claims, demands, or causes of action arising out of any injury, illness, or property damage sustained by me during or as a result of my participation in open runs.\n\n"
                      "3. App Terms & Rules: I agree to abide by the registration windows, waitlist promotions, and cutoff rules. I understand that failure to check in at least 10 minutes before the scheduled game time will result in my slot being forfeited and my account receiving a no-show strike, subject to standard ban policies (1 strike = 7 days, 2 strikes = 30 days, 3 strikes = permanent ban).\n\n"
                      "4. Medical Treatment: In the event of injury, I consent to receive medical treatment deemed necessary by first responders or staff, and agree that I am solely responsible for any costs incurred.\n\n"
                      "By checking the box below and clicking 'Accept & Sign Waiver', I acknowledge that I have read this document in its entirety, fully understand its terms, and agree to be bound by them freely and voluntarily.",
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _checked,
                onChanged: (val) {
                  setState(() => _checked = val ?? false);
                },
                title: const Text(
                  "I have read, understood, and agree to the Liability Waiver and Release Terms.",
                  style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                ),
                activeColor: AppTheme.primary,
                checkColor: AppTheme.textPrimary,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              else
                ElevatedButton(
                  onPressed: _checked ? _submitWaiver : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _checked ? AppTheme.primary : AppTheme.surfaceLight,
                  ),
                  child: const Text("ACCEPT & SIGN WAIVER"),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
