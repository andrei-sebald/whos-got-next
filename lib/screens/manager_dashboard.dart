import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/firebase_service.dart';
import '../theme.dart';

class ManagerDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  const ManagerDashboard({super.key, required this.userData});

  @override
  State<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  final FirebaseService _fbService = FirebaseService();
  final _db = FirebaseFirestore.instance;

  // Controllers for creating/editing sessions
  final _locationController = TextEditingController(text: "North Gymnasium - Court A");
  final _slotsController = TextEditingController(text: "20");
  final _resSlotsController = TextEditingController(text: "10");
  final _resWindowController = TextEditingController(text: "120");
  final _outWindowController = TextEditingController(text: "60");

  // Controllers for guest check-in
  final _guestNameController = TextEditingController();
  final _guestPhoneController = TextEditingController();

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 18, minute: 0);

  bool _isCreatingSession = false;
  bool _isCheckingInGuest = false;

  @override
  void dispose() {
    _locationController.dispose();
    _slotsController.dispose();
    _resSlotsController.dispose();
    _resWindowController.dispose();
    _outWindowController.dispose();
    _guestNameController.dispose();
    _guestPhoneController.dispose();
    super.dispose();
  }

  // Create new session
  Future<void> _createSession() async {
    final location = _locationController.text.trim();
    final slots = int.tryParse(_slotsController.text) ?? 20;
    final resSlots = int.tryParse(_resSlotsController.text) ?? 10;
    final resMins = int.tryParse(_resWindowController.text) ?? 120;
    final outMins = int.tryParse(_outWindowController.text) ?? 60;

    if (location.isEmpty) {
      _showSnackBar("Please enter a location name", isError: true);
      return;
    }

    final gameDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    setState(() => _isCreatingSession = true);

    try {
      await _fbService.createSession(
        locationName: location,
        gameTime: gameDateTime,
        totalSlots: slots,
        residentSlots: resSlots,
        residentWindowStartMins: resMins,
        outsiderWindowStartMins: outMins,
      );
      Navigator.of(context).pop(); // Close sheet/modal
      _showSnackBar("Game session created successfully!");
    } catch (e) {
      _showSnackBar("Error creating session: $e", isError: true);
    } finally {
      setState(() => _isCreatingSession = false);
    }
  }

  // Check in guest
  Future<void> _checkInGuest(String sessionId) async {
    final name = _guestNameController.text.trim();
    final phone = _guestPhoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      _showSnackBar("Please enter guest name and phone number", isError: true);
      return;
    }

    setState(() => _isCheckingInGuest = true);

    try {
      await _fbService.checkInGuest(sessionId, name, phone);
      _guestNameController.clear();
      _guestPhoneController.clear();
      Navigator.of(context).pop(); // Close modal
      _showSnackBar("Walk-in guest checked in successfully!");
    } catch (e) {
      _showSnackBar("Error checking in guest: $e", isError: true);
    } finally {
      setState(() => _isCheckingInGuest = false);
    }
  }

  // Force trigger late cutoff check
  Future<void> _triggerCutoff(String sessionId) async {
    try {
      await _fbService.triggerCutoffCheck(sessionId);
      _showSnackBar("Session cutoff checked. Inactive players kicked, waitlist promoted.");
    } catch (e) {
      _showSnackBar("Error checking cutoff: $e", isError: true);
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
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("MANAGER PANEL"),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => _fbService.signOut(),
            )
          ],
          bottom: const TabBar(
            indicatorColor: AppTheme.primary,
            tabs: [
              Tab(icon: Icon(Icons.sports_basketball), text: "Games"),
              Tab(icon: Icon(Icons.verified_user), text: "Residency"),
              Tab(icon: Icon(Icons.gavel), text: "Appeals"),
              Tab(icon: Icon(Icons.add), text: "Schedule"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildGamesTab(),
            _buildResidencyTab(),
            _buildAppealsTab(),
            _buildScheduleTab(),
          ],
        ),
      ),
    );
  }

  // TAB 1: Upcoming games lists + check-ins + walk-in guest tools
  Widget _buildGamesTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _fbService.streamSessions(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        final sessions = snapshot.data ?? [];
        if (sessions.isEmpty) {
          return const Center(
            child: Text(
              "No sessions scheduled. Go to the Schedule tab to add one.",
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sessions.length,
          itemBuilder: (context, index) {
            final session = sessions[index];
            final String id = session['id'];
            final String name = session['locationName'] ?? 'Gym';
            final DateTime time = (session['gameTime'] as Timestamp).toDate();
            final List<dynamic> activePlayers = session['activePlayers'] ?? [];
            final List<dynamic> waitlist = session['waitlist'] ?? [];
            final int total = session['totalSlots'] ?? 20;

            final checkedInCount = activePlayers.where((p) => p['checkedIn'] == true).length;

            return Card(
              margin: const EdgeInsets.bottom(16),
              child: ExpansionTile(
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("${time.toLocal().toString().substring(0, 16)}  |  Checked In: $checkedInCount / ${activePlayers.length}"),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Control buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _showQrCodeModal(id, name),
                              icon: const Icon(Icons.qr_code),
                              label: const Text("SHOW QR"),
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _showGuestCheckInModal(id),
                              icon: const Icon(Icons.person_add),
                              label: const Text("ADD GUEST"),
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceLight),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _triggerCutoff(id),
                          icon: const Icon(Icons.timer_outlined),
                          label: const Text("FORCE CUTOFF CHECK (T-10m)"),
                        ),
                        const SizedBox(height: 16),
                        
                        // Active Confirmed list
                        const Text("Confirmed Roster", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                        const SizedBox(height: 8),
                        if (activePlayers.isEmpty)
                          const Text("No active registrants.", style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: activePlayers.length,
                            itemBuilder: (context, idx) {
                              final p = activePlayers[idx];
                              final bool checked = p['checkedIn'] ?? false;
                              final bool guest = p['isGuest'] ?? false;
                              return ListTile(
                                dense: true,
                                title: Text("${p['name']} ${guest ? '(Guest)' : ''}"),
                                subtitle: Text(p['phoneNumber'] ?? ''),
                                leading: Icon(
                                  checked ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: checked ? AppTheme.success : AppTheme.textSecondary,
                                ),
                                trailing: !checked
                                    ? TextButton(
                                        onPressed: () async {
                                          await _db.runTransaction((transaction) async {
                                            final ref = _db.collection('sessions').doc(id);
                                            final snap = await transaction.get(ref);
                                            if (!snap.exists) return;
                                            final list = List.from(snap.data()?['activePlayers'] ?? []);
                                            final playerIdx = list.indexWhere((pl) => pl['uid'] == p['uid']);
                                            if (playerIdx != -1) {
                                              list[playerIdx]['checkedIn'] = true;
                                              transaction.update(ref, {'activePlayers': list});
                                            }
                                          });
                                          _showSnackBar("Checked in player!");
                                        },
                                        child: const Text("CHECK IN"),
                                      )
                                    : null,
                              );
                            },
                          ),
                        
                        const Divider(height: 24),
                        // Waitlist list
                        const Text("Waitlist Queue", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accent)),
                        const SizedBox(height: 8),
                        if (waitlist.isEmpty)
                          const Text("Waitlist is empty.", style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: waitlist.length,
                            itemBuilder: (context, idx) {
                              final w = waitlist[idx];
                              return ListTile(
                                dense: true,
                                title: Text("${idx + 1}. ${w['name']}"),
                                subtitle: Text(w['phoneNumber'] ?? ''),
                                leading: const Icon(Icons.hourglass_empty, color: AppTheme.accent),
                              );
                            },
                          ),
                      ],
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  // TAB 2: Residency verification queue
  Widget _buildResidencyTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _fbService.streamPendingResidency(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        final applicants = snapshot.data ?? [];
        if (applicants.isEmpty) {
          return const Center(
            child: Text("No pending residency uploads.", style: TextStyle(color: AppTheme.textSecondary)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: applicants.length,
          itemBuilder: (context, index) {
            final app = applicants[index];
            final String uid = app['uid'];
            final String name = app['name'] ?? 'Athlete';
            final String phone = app['phoneNumber'] ?? '';
            final String docUrl = app['residencyProofUrl'] ?? '';

            return Card(
              margin: const EdgeInsets.bottom(16),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleLarge),
                    Text("Phone: $phone", style: const TextStyle(color: AppTheme.textSecondary)),
                    const SizedBox(height: 12),
                    if (docUrl.isNotEmpty)
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.surfaceLight),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            docUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(child: CircularProgressIndicator());
                            },
                            errorBuilder: (_, __, ___) => const Center(
                              child: Text("Failed to load residency document image.", style: TextStyle(color: AppTheme.error)),
                            ),
                          ),
                        ),
                      )
                    else
                      const Text("No proof image attached.", style: TextStyle(color: AppTheme.error)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _fbService.verifyResidency(uid, false),
                          style: TextButton.styleFrom(foregroundColor: AppTheme.error),
                          child: const Text("REJECT"),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () => _fbService.verifyResidency(uid, true),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                          child: const Text("APPROVE RESIDENT"),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // TAB 3: Strike Appeals Review Board
  Widget _buildAppealsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _fbService.streamPendingAppeals(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        final appeals = snapshot.data ?? [];
        if (appeals.isEmpty) {
          return const Center(
            child: Text("No pending appeals to review.", style: TextStyle(color: AppTheme.textSecondary)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: appeals.length,
          itemBuilder: (context, index) {
            final appeal = appeals[index];
            final String id = appeal['id'];
            final String uid = appeal['userId'];
            final String name = appeal['userName'] ?? 'Athlete';
            final String reason = appeal['reason'] ?? '';
            final DateTime date = (appeal['createdAt'] as Timestamp).toDate();

            return Card(
              margin: const EdgeInsets.bottom(16),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(name, style: Theme.of(context).textTheme.titleLarge),
                        Text(
                          date.toLocal().toString().substring(0, 10),
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text("Explanation:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.accent)),
                    const SizedBox(height: 4),
                    Text(
                      reason,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _fbService.resolveAppeal(id, uid, false),
                          style: TextButton.styleFrom(foregroundColor: AppTheme.error),
                          child: const Text("DENY APPEAL"),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () => _fbService.resolveAppeal(id, uid, true),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                          child: const Text("APPROVE & FORGIVE"),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // TAB 4: Create Game Session Form
  Widget _buildScheduleTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Create Game Session",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppTheme.primary, fontSize: 22),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: "Location Name",
                  prefixIcon: Icon(Icons.location_on, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _slotsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Total Slots"),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _resSlotsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Resident Slots"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _resWindowController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Res. Window (Mins)",
                        hintText: "e.g. 120",
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _outWindowController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Gen. Window (Mins)",
                        hintText: "e.g. 60",
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text("Game Date & Time", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 90)),
                        );
                        if (date != null) setState(() => _selectedDate = date);
                      },
                      child: Text("${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}"),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: _selectedTime,
                        );
                        if (time != null) setState(() => _selectedTime = time);
                      },
                      child: Text(_selectedTime.format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _isCreatingSession
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _createSession,
                      child: const Text("PUBLISH GAME SESSION"),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // Show Modal containing the check-in QR Code
  void _showQrCodeModal(String sessionId, String locationName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Check-in QR Code",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppTheme.primary, fontSize: 20),
              ),
              Text(locationName, style: const TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: sessionId, // Athlete scans this ID to check in
                  version: QrVersions.auto,
                  size: 200.0,
                  foregroundColor: Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Display this QR code at the desk for paid athletes to scan.",
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  // Walk-in Guest check-in form Modal
  void _showGuestCheckInModal(String sessionId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Register Walk-in Guest",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppTheme.primary, fontSize: 20),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _guestNameController,
                decoration: const InputDecoration(
                  labelText: "Guest Full Name",
                  prefixIcon: Icon(Icons.person, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _guestPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "Guest Phone Number",
                  prefixIcon: Icon(Icons.phone, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 24),
              _isCheckingInGuest
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: () => _checkInGuest(sessionId),
                      child: const Text("CHECK IN GUEST"),
                    ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
