import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/firebase_service.dart';
import '../theme.dart';

class AthleteDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  const AthleteDashboard({super.key, required this.userData});

  @override
  State<AthleteDashboard> createState() => _AthleteDashboardState();
}

class _AthleteDashboardState extends State<AthleteDashboard> {
  final FirebaseService _fbService = FirebaseService();
  final _appealController = TextEditingController();
  final _picker = ImagePicker();

  bool _isUploadingDoc = false;
  bool _isAppealing = false;
  bool _isScanning = false;
  String? _scanningSessionId;

  @override
  void dispose() {
    _appealController.dispose();
    super.dispose();
  }

  // Upload proof of residency
  Future<void> _uploadResidencyDoc() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      if (image == null) return;

      setState(() => _isUploadingDoc = true);
      await _fbService.uploadResidencyProof(File(image.path));
      _showSnackBar("Proof of residency uploaded successfully!");
    } catch (e) {
      _showSnackBar("Error uploading: $e", isError: true);
    } finally {
      setState(() => _isUploadingDoc = false);
    }
  }

  // Submit strike appeal
  Future<void> _submitAppeal() async {
    final reason = _appealController.text.trim();
    if (reason.isEmpty) return;

    setState(() => _isAppealing = true);
    try {
      await _fbService.submitAppeal(reason, widget.userData['name'] ?? 'Athlete');
      _appealController.clear();
      _showSnackBar("Appeal submitted successfully. Staff will review it shortly.");
    } catch (e) {
      _showSnackBar("Error submitting appeal: $e", isError: true);
    } finally {
      setState(() => _isAppealing = false);
    }
  }

  // QR checkin code scanned
  Future<void> _onQrCodeScanned(String scannedSessionId) async {
    if (_scanningSessionId != scannedSessionId) return;

    setState(() {
      _isScanning = false;
      _scanningSessionId = null;
    });

    try {
      final result = await _fbService.checkInViaQr(scannedSessionId);
      _showSnackBar(result, isError: !result.contains("successful"));
    } catch (e) {
      _showSnackBar("Check-in error: $e", isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isBanned = widget.userData['banUntil'] != null &&
        (widget.userData['banUntil'] as Timestamp).toDate().isAfter(DateTime.now());
    final String residencyStatus = widget.userData['residencyStatus'] ?? 'none';
    final int strikes = widget.userData['strikesCount'] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("ATHLETE DASHBOARD"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _fbService.signOut(),
          )
        ],
      ),
      body: _isScanning
          ? _buildQrScannerView()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Profile Overview Header
                  _buildProfileCard(isBanned, strikes, residencyStatus),
                  const SizedBox(height: 24),

                  // Appeal section if banned
                  if (isBanned) ...[
                    _buildAppealSection(),
                    const SizedBox(height: 24),
                  ],

                  // Residency proof section
                  if (!isBanned) ...[
                    _buildResidencyUploadSection(residencyStatus),
                    const SizedBox(height: 24),
                  ],

                  // Game list title
                  Text(
                    "Upcoming Sessions",
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 12),

                  // Games feed
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _fbService.streamSessions(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text("Error: ${snapshot.error}"));
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final sessions = snapshot.data ?? [];
                      if (sessions.isEmpty) {
                        return const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text(
                              "No upcoming basketball sessions scheduled.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: sessions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          return _buildSessionCard(sessions[index], isBanned);
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileCard(bool isBanned, int strikes, String residencyStatus) {
    Color statusColor = AppTheme.success;
    String statusText = "Active Athlete";
    if (isBanned) {
      statusColor = AppTheme.error;
      statusText = "Account Banned";
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor.withOpacity(0.2),
                  child: Icon(Icons.person, color: statusColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.userData['name'] ?? 'Athlete',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        widget.userData['phoneNumber'] ?? '',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor, width: 1),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                )
              ],
            ),
            const Divider(height: 32, color: AppTheme.surfaceLight),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Residency", style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    const SizedBox(height: 4),
                    _buildResidencyBadge(residencyStatus),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text("No-Show Strikes", style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      "$strikes / 3",
                      style: TextStyle(
                        color: strikes > 0 ? AppTheme.primary : AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (isBanned) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.error.withOpacity(0.3)),
                ),
                child: Text(
                  "You are banned due to repeated no-shows. Submit an appeal below to request strike removal.",
                  style: TextStyle(color: AppTheme.error.withOpacity(0.9), fontSize: 13),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildResidencyBadge(String status) {
    IconData icon = Icons.help_outline;
    Color color = AppTheme.textSecondary;
    String label = "Unverified";

    if (status == 'approved') {
      icon = Icons.verified;
      color = AppTheme.success;
      label = "Local Resident";
    } else if (status == 'pending') {
      icon = Icons.hourglass_top;
      color = AppTheme.accent;
      label = "Verification Pending";
    } else if (status == 'rejected') {
      icon = Icons.cancel;
      color = AppTheme.error;
      label = "Rejected";
    }

    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
        )
      ],
    );
  }

  Widget _buildAppealSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Appeal Strike", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              "Briefly explain the reason for your absence. A manager will review your submission and may clear your strike.",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _appealController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: "Enter your explanation here...",
              ),
            ),
            const SizedBox(height: 16),
            _isAppealing
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _submitAppeal,
                    child: const Text("SUBMIT APPEAL"),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildResidencyUploadSection(String residencyStatus) {
    if (residencyStatus == 'approved' || residencyStatus == 'pending') {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Request Resident Status", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              "Verified residents get early 2-hour sign-up access to open runs. Upload a utility bill or lease agreement showing your name to get verified.",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _isUploadingDoc
                ? const Center(child: CircularProgressIndicator())
                : OutlinedButton.icon(
                    onPressed: _uploadResidencyDoc,
                    icon: const Icon(Icons.upload_file),
                    label: const Text("UPLOAD PROOF OF ADDRESS"),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session, bool isBanned) {
    final String id = session['id'];
    final String location = session['locationName'] ?? 'Gymnasium';
    final DateTime gameTime = (session['gameTime'] as Timestamp).toDate();
    final int totalSlots = session['totalSlots'] ?? 20;
    final int residentSlots = session['residentSlots'] ?? 10;
    final int residentStart = session['residentWindowStartMins'] ?? 120;
    final int outsiderStart = session['outsiderWindowStartMins'] ?? 60;

    final List<dynamic> activePlayers = session['activePlayers'] ?? [];
    final List<dynamic> waitlist = session['waitlist'] ?? [];

    final String myUid = currentUid ?? '';
    final int myActiveIndex = activePlayers.indexWhere((p) => p['uid'] == myUid);
    final int myWaitlistIndex = waitlist.indexWhere((p) => p['uid'] == myUid);

    final bool isMyRegistered = myActiveIndex != -1;
    final bool isMyWaitlisted = myWaitlistIndex != -1;
    final bool isMyCheckedIn = isMyRegistered && (activePlayers[myActiveIndex]['checkedIn'] == true);

    // Calculate timing window
    final DateTime now = DateTime.now();
    final Duration timeToGame = gameTime.difference(now);
    final int minutesToGame = timeToGame.inMinutes;

    final bool isResident = widget.userData['isResident'] ?? false;

    // Window logic
    final bool residentWindow = minutesToGame <= residentStart && minutesToGame > outsiderStart;
    final bool generalWindow = minutesToGame <= outsiderStart && minutesToGame > 0;
    final bool isClosed = minutesToGame <= 0;

    String windowText = "Registration Closed";
    Color windowColor = AppTheme.error;

    if (!isClosed) {
      if (minutesToGame > residentStart) {
        windowText = "Signups open in ${timeToGame.inMinutes - residentStart} mins";
        windowColor = AppTheme.textSecondary;
      } else if (residentWindow) {
        windowText = "Resident Window Open";
        windowColor = AppTheme.accent;
      } else if (generalWindow) {
        windowText = "General Signups Open";
        windowColor = AppTheme.success;
      }
    }

    // Determine slots availability
    int activeCount = activePlayers.length;
    int availableSpots = totalSlots - activeCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    location,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: windowColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    windowText,
                    style: TextStyle(color: windowColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(
                  "${gameTime.toLocal().toString().substring(0, 16)} (${timeToGame.inHours}h ${timeToGame.inMinutes % 60}m to game)",
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Players Confirmed", style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(
                      "$activeCount / $totalSlots",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text("Waitlist", style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(
                      "${waitlist.length} in line",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24, color: AppTheme.surfaceLight),
            if (isMyRegistered) ...[
              // Registered flow
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isMyCheckedIn ? AppTheme.success.withOpacity(0.1) : AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isMyCheckedIn ? AppTheme.success : AppTheme.primary),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(isMyCheckedIn ? Icons.check_circle : Icons.sports_basketball,
                              color: isMyCheckedIn ? AppTheme.success : AppTheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            isMyCheckedIn ? "CHECKED IN & READY" : "SLOT CONFIRMED",
                            style: TextStyle(
                              color: isMyCheckedIn ? AppTheme.success : AppTheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (!isMyCheckedIn && !isClosed)
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _scanningSessionId = id;
                          _isScanning = true;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        padding: const EdgeInsets.all(12),
                      ),
                      child: const Icon(Icons.qr_code_scanner),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (!isMyCheckedIn && !isClosed)
                OutlinedButton(
                  onPressed: () => _fbService.cancelRegistration(id),
                  child: const Text("CANCEL SLOT"),
                ),
            ] else if (isMyWaitlisted) ...[
              // Waitlisted flow
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.accent),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.hourglass_empty, color: AppTheme.accent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "WAITLIST POSITION: #${myWaitlistIndex + 1}",
                      style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _fbService.cancelRegistration(id),
                child: const Text("LEAVE WAITLIST"),
              ),
            ] else ...[
              // Signup buttons
              if (isBanned)
                const Center(
                  child: Text("Banned from signing up", style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold)),
                )
              else if (isClosed)
                const Center(
                  child: Text("Registration Closed", style: TextStyle(color: AppTheme.textSecondary)),
                )
              else if (minutesToGame > residentStart)
                const Center(
                  child: Text("Registration not yet open", style: TextStyle(color: AppTheme.textSecondary)),
                )
              else if (residentWindow && !isResident)
                const Center(
                  child: Text("Resident window: Locked for non-residents", style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                )
              else ...[
                // Active signup button
                ElevatedButton(
                  onPressed: () async {
                    final res = await _fbService.registerForSession(id);
                    _showSnackBar(res, isError: !res.contains("Successful") && !res.contains("registered"));
                  },
                  child: Text(availableSpots > 0 ? "SIGN UP FOR GAME" : "JOIN WAITLIST"),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQrScannerView() {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final String? rawVal = barcode.rawValue;
                if (rawVal != null) {
                  _onQrCodeScanned(rawVal);
                  break;
                }
              }
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          color: AppTheme.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Scan the front desk QR code to check in",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Verify your payment with the manager first.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _isScanning = false;
                    _scanningSessionId = null;
                  });
                },
                child: const Text("CANCEL"),
              ),
              const SizedBox(height: 12),
              // Fallback text field for testing/manual input
              TextField(
                onSubmitted: (val) => _onQrCodeScanned(val.trim()),
                decoration: const InputDecoration(
                  labelText: "Manual Check-in Key (Testing)",
                  hintText: "Enter session ID directly if camera fails",
                ),
              )
            ],
          ),
        )
      ],
    );
  }
}
