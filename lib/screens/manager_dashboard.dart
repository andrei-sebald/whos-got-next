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

  int _selectedIndex = 0;

  final List<Map<String, dynamic>> _menuItems = [
    {'title': 'Games', 'icon': Icons.sports_basketball},
    {'title': 'Residency', 'icon': Icons.verified_user},
    {'title': 'Appeals', 'icon': Icons.gavel},
    {'title': 'Schedule', 'icon': Icons.add},
  ];

  // Controllers for creating/editing sessions
  final _locationController = TextEditingController(text: "North Gymnasium - Court A");
  final _slotsController = TextEditingController(text: "20");
  final _resSlotsController = TextEditingController(text: "10");
  final _resWindowController = TextEditingController(text: "120");
  final _outWindowController = TextEditingController(text: "60");

  // Controllers for guest check-in
  final _guestNameController = TextEditingController();
  final _guestPhoneController = TextEditingController();

  // Controllers for offline residency search
  final _residencySearchController = TextEditingController();
  String _residencySearchQuery = '';

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 18, minute: 0);

  bool _isCreatingSession = false;
  bool _isCheckingInGuest = false;

  // Recurrence state for the Schedule tab
  bool _isRecurring = true;
  int _selectedDayOfWeek = 4; // 4 = Thursday (DateTime.weekday: 1=Mon…7=Sun)

  @override
  void dispose() {
    _locationController.dispose();
    _slotsController.dispose();
    _resSlotsController.dispose();
    _resWindowController.dispose();
    _outWindowController.dispose();
    _guestNameController.dispose();
    _guestPhoneController.dispose();
    _residencySearchController.dispose();
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

    setState(() => _isCreatingSession = true);

    try {
      if (_isRecurring) {
        await _fbService.createSession(
          locationName: location,
          totalSlots: slots,
          residentSlots: resSlots,
          residentWindowStartMins: resMins,
          outsiderWindowStartMins: outMins,
          isRecurring: true,
          recurringDayOfWeek: _selectedDayOfWeek,
          recurringTimeHour: _selectedTime.hour,
          recurringTimeMinute: _selectedTime.minute,
        );
      } else {
        final gameDateTime = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          _selectedTime.hour,
          _selectedTime.minute,
        );
        await _fbService.createSession(
          locationName: location,
          totalSlots: slots,
          residentSlots: resSlots,
          residentWindowStartMins: resMins,
          outsiderWindowStartMins: outMins,
          gameTime: gameDateTime,
        );
      }

      // Bug fix: Schedule tab is inline — never pop. Instead switch to Games tab.
      setState(() => _selectedIndex = 0);
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

  Widget _buildActiveTab() {
    switch (_selectedIndex) {
      case 0:
        return _buildGamesTab();
      case 1:
        return _buildResidencyTab();
      case 2:
        return _buildAppealsTab();
      case 3:
        return _buildScheduleTab();
      default:
        return _buildGamesTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("MANAGER - ${_menuItems[_selectedIndex]['title'].toUpperCase()}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _fbService.signOut(),
          )
        ],
      ),
      drawer: Drawer(
        backgroundColor: AppTheme.background,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                border: Border(
                  bottom: BorderSide(color: AppTheme.surfaceLight, width: 1),
                ),
              ),
              currentAccountPicture: CircleAvatar(
                backgroundColor: AppTheme.primary,
                backgroundImage: widget.userData['photoUrl'] != null &&
                        widget.userData['photoUrl'].toString().isNotEmpty
                    ? NetworkImage(widget.userData['photoUrl'])
                    : null,
                child: widget.userData['photoUrl'] != null &&
                        widget.userData['photoUrl'].toString().isNotEmpty
                    ? null
                    : Text(
                        widget.userData['name'] != null &&
                                widget.userData['name'].toString().isNotEmpty
                            ? widget.userData['name'].substring(0, 1).toUpperCase()
                            : 'M',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit', // Or fallback to default sans-serif
                        ),
                      ),
              ),
              accountName: Text(
                widget.userData['name'] ?? 'Manager',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              accountEmail: Text(
                "Role: ${widget.userData['role']?.toUpperCase() ?? 'MANAGER'}",
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
            ...List.generate(_menuItems.length, (index) {
              final item = _menuItems[index];
              final bool isSelected = _selectedIndex == index;
              return ListTile(
                leading: Icon(
                  item['icon'],
                  color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                ),
                title: Text(
                  item['title'],
                  style: TextStyle(
                    color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                selectedTileColor: AppTheme.surface,
                onTap: () {
                  setState(() {
                    _selectedIndex = index;
                  });
                  Navigator.of(context).pop(); // Close drawer
                },
              );
            }),
            const Divider(color: AppTheme.surfaceLight),
            ListTile(
              leading: const Icon(Icons.logout, color: AppTheme.error),
              title: const Text(
                "Logout",
                style: TextStyle(color: AppTheme.error),
              ),
              onTap: () {
                Navigator.of(context).pop(); // Close drawer
                _fbService.signOut();
              },
            ),
          ],
        ),
      ),
      body: _buildActiveTab(),
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
              margin: const EdgeInsets.only(bottom: 16),
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

  // TAB 2: Residency verification & offline directory
  Widget _buildResidencyTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _residencySearchController,
            onChanged: (val) {
              setState(() {
                _residencySearchQuery = val.trim().toLowerCase();
              });
            },
            decoration: const InputDecoration(
              labelText: "Search Athletes by Name or Phone",
              prefixIcon: Icon(Icons.search),
              hintText: "Enter name or phone number",
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _fbService.streamAllUsers(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

              final allUsers = snapshot.data ?? [];
              
              // Filter only athletes/users matching the search query
              final filteredAthletes = allUsers.where((user) {
                final role = user['role'] ?? 'athlete';
                if (role != 'athlete') return false;

                final name = (user['name'] ?? '').toString().toLowerCase();
                final phone = (user['phoneNumber'] ?? '').toString().toLowerCase();
                return name.contains(_residencySearchQuery) || phone.contains(_residencySearchQuery);
              }).toList();

              if (filteredAthletes.isEmpty) {
                return const Center(
                  child: Text("No athletes found matching search.", style: TextStyle(color: AppTheme.textSecondary)),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filteredAthletes.length,
                itemBuilder: (context, index) {
                  final athlete = filteredAthletes[index];
                  final String uid = athlete['uid'];
                  final String name = athlete['name'] ?? 'Athlete';
                  final String phone = athlete['phoneNumber'] ?? '';
                  final bool isResident = athlete['isResident'] ?? false;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(phone),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isResident ? "RESIDENT" : "GENERAL",
                            style: TextStyle(
                              color: isResident ? AppTheme.success : AppTheme.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Switch(
                            value: isResident,
                            activeColor: AppTheme.success,
                            onChanged: (val) async {
                              await _fbService.verifyResidency(uid, val);
                              _showSnackBar("Updated resident status for $name");
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
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
              margin: const EdgeInsets.only(bottom: 16),
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
    const List<String> dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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

              // ── Session Type Toggle ──────────────────────────────────────
              const Text("Session Type", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isRecurring = true),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _isRecurring ? AppTheme.primary.withOpacity(0.15) : AppTheme.surface,
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                          border: Border.all(
                            color: _isRecurring ? AppTheme.primary : AppTheme.surfaceLight,
                            width: _isRecurring ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.repeat, color: _isRecurring ? AppTheme.primary : AppTheme.textSecondary, size: 20),
                            const SizedBox(height: 4),
                            Text(
                              "Recurring Weekly",
                              style: TextStyle(
                                color: _isRecurring ? AppTheme.primary : AppTheme.textSecondary,
                                fontWeight: _isRecurring ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isRecurring = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !_isRecurring ? AppTheme.accent.withOpacity(0.15) : AppTheme.surface,
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                          border: Border.all(
                            color: !_isRecurring ? AppTheme.accent : AppTheme.surfaceLight,
                            width: !_isRecurring ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.event, color: !_isRecurring ? AppTheme.accent : AppTheme.textSecondary, size: 20),
                            const SizedBox(height: 4),
                            Text(
                              "One-time Event",
                              style: TextStyle(
                                color: !_isRecurring ? AppTheme.accent : AppTheme.textSecondary,
                                fontWeight: !_isRecurring ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Day / Date Picker ─────────────────────────────────────────
              if (_isRecurring) ...[
                const Text("Repeats Every", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: List.generate(7, (i) {
                    final int dow = i + 1; // 1=Mon … 7=Sun
                    final bool selected = _selectedDayOfWeek == dow;
                    return ChoiceChip(
                      label: Text(dayLabels[i]),
                      selected: selected,
                      selectedColor: AppTheme.primary,
                      backgroundColor: AppTheme.surface,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : AppTheme.textSecondary,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (_) => setState(() => _selectedDayOfWeek = dow),
                    );
                  }),
                ),
              ] else ...[
                const Text("Event Date", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (date != null) setState(() => _selectedDate = date);
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.calendar_today, size: 16),
                      const SizedBox(width: 8),
                      Text("${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2,'0')}-${_selectedDate.day.toString().padLeft(2,'0')}"),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // ── Time Picker (shared) ──────────────────────────────────────
              const Text("Start Time", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: _selectedTime,
                  );
                  if (time != null) setState(() => _selectedTime = time);
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.access_time, size: 16),
                    const SizedBox(width: 8),
                    Text(_selectedTime.format(context)),
                  ],
                ),
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
