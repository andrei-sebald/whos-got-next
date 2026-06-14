import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Get current user UID
  String? get currentUid => _auth.currentUser?.uid;

  // Stream current user document
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamUserData() {
    if (currentUid == null) {
      return const Stream.empty();
    }
    return _db.collection('users').doc(currentUid).snapshots();
  }

  // Stream user document by UID
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamUserDataByUid(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Sign Liability Waiver
  Future<void> signWaiver() async {
    if (currentUid == null) return;
    await _db.collection('users').doc(currentUid).update({
      'hasSignedWaiver': true,
    });
  }

  // Upload profile picture to Firebase Storage and update user doc
  Future<void> uploadProfilePicture(Uint8List imageBytes) async {
    if (currentUid == null) return;

    final ref = _storage.ref().child('profile_pictures/$currentUid.jpg');
    final uploadTask = await ref.putData(imageBytes);
    final downloadUrl = await uploadTask.ref.getDownloadURL();

    await _db.collection('users').doc(currentUid).update({
      'photoUrl': downloadUrl,
    });
  }

  // Stream all user profiles (Manager/Admin permission)
  Stream<List<Map<String, dynamic>>> streamAllUsers() {
    return _db
        .collection('users')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['uid'] = doc.id;
              return data;
            }).toList());
  }

  // Compute the next occurrence of a given weekday (1=Mon…7=Sun) at hour:minute.
  // If today is that weekday and the time hasn't passed yet, returns today's occurrence.
  // Otherwise rolls forward to the next matching weekday.
  static DateTime nextOccurrenceFromRule(int dayOfWeek, int hour, int minute) {
    final now = DateTime.now();
    // Candidate: this week's occurrence
    int daysUntil = (dayOfWeek - now.weekday) % 7;
    DateTime candidate = DateTime(
      now.year,
      now.month,
      now.day + daysUntil,
      hour,
      minute,
    );
    // If that time has already passed, jump to next week's occurrence
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  // Stream sessions, computing gameTime for recurring sessions client-side.
  // All sessions are sorted by their next upcoming occurrence.
  Stream<List<Map<String, dynamic>>> streamSessions() {
    return _db
        .collection('sessions')
        .snapshots()
        .map((snapshot) {
          final sessions = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;

            final bool isRecurring = data['isRecurring'] ?? false;
            if (isRecurring) {
              final int dow = data['recurringDayOfWeek'] ?? 4; // Thursday default
              final int h = data['recurringTimeHour'] ?? 18;
              final int m = data['recurringTimeMinute'] ?? 0;
              // Inject computed gameTime so downstream code works unchanged
              data['gameTime'] = Timestamp.fromDate(
                nextOccurrenceFromRule(dow, h, m),
              );
            }
            return data;
          }).toList();

          // Sort all sessions by ascending next occurrence
          sessions.sort((a, b) {
            final aTime = (a['gameTime'] as Timestamp?)?.toDate() ?? DateTime(9999);
            final bTime = (b['gameTime'] as Timestamp?)?.toDate() ?? DateTime(9999);
            return aTime.compareTo(bTime);
          });

          return sessions;
        });
  }

  // Manager approves/rejects resident status offline
  Future<void> verifyResidency(String athleteUid, bool approve) async {
    await _db.collection('users').doc(athleteUid).update({
      'isResident': approve,
      'residencyStatus': approve ? 'approved' : 'none',
    });
  }

  // Stream appeals for the current user
  Stream<List<Map<String, dynamic>>> streamUserAppeals() {
    if (currentUid == null) return const Stream.empty();
    return _db
        .collection('appeals')
        .where('userId', isEqualTo: currentUid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  // Stream all pending appeals (Manager permission)
  Stream<List<Map<String, dynamic>>> streamPendingAppeals() {
    return _db
        .collection('appeals')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  // Create appeal
  Future<void> submitAppeal(String reason, String userName) async {
    if (currentUid == null) return;
    await _db.collection('appeals').add({
      'userId': currentUid,
      'userName': userName,
      'reason': reason,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Manager approves/forgives appeal, clearing a strike and lifting bans
  Future<void> resolveAppeal(String appealId, String userId, bool approve) async {
    await _db.runTransaction((transaction) async {
      final appealDoc = _db.collection('appeals').doc(appealId);
      final userDoc = _db.collection('users').doc(userId);

      final userSnapshot = await transaction.get(userDoc);
      if (!userSnapshot.exists) return;

      int currentStrikes = userSnapshot.data()?['strikesCount'] ?? 0;

      if (approve) {
        // Decrement strikes (min 0)
        int newStrikes = currentStrikes > 0 ? currentStrikes - 1 : 0;
        
        // Remove ban if it was active
        transaction.update(userDoc, {
          'strikesCount': newStrikes,
          'banUntil': null, // Lift ban
        });
        transaction.update(appealDoc, {
          'status': 'approved',
        });
      } else {
        transaction.update(appealDoc, {
          'status': 'rejected',
        });
      }
    });
  }

  // Sign up for a game session (implements Resident vs. Outsider sign-up windows)
  Future<String> registerForSession(String sessionId) async {
    if (currentUid == null) return 'Not authenticated';

    final userDoc = await _db.collection('users').doc(currentUid).get();
    if (!userDoc.exists) return 'User document not found';

    final userData = userDoc.data()!;
    final bool isResident = userData['isResident'] ?? false;
    final bool hasSignedWaiver = userData['hasSignedWaiver'] ?? false;
    final Timestamp? banUntil = userData['banUntil'] as Timestamp?;

    // Check waiver
    if (!hasSignedWaiver) return 'You must sign the liability waiver first';

    // Check ban status
    if (banUntil != null && banUntil.toDate().isAfter(DateTime.now())) {
      final banString = banUntil.toDate().toLocal().toString().substring(0, 16);
      return 'You are currently banned until $banString';
    }

    final sessionRef = _db.collection('sessions').doc(sessionId);
    
    return await _db.runTransaction<String>((transaction) async {
      final sessionSnapshot = await transaction.get(sessionRef);
      if (!sessionSnapshot.exists) return 'Game session not found';

      final sessionData = sessionSnapshot.data()!;
      final DateTime gameTime = (sessionData['gameTime'] as Timestamp).toDate();
      final int totalSlots = sessionData['totalSlots'] ?? 20;
      final int residentSlots = sessionData['residentSlots'] ?? 10;
      final int residentWindowStartMins = sessionData['residentWindowStartMins'] ?? 120;
      final int outsiderWindowStartMins = sessionData['outsiderWindowStartMins'] ?? 60;

      final List<dynamic> activePlayers = sessionData['activePlayers'] ?? [];
      final List<dynamic> waitlist = sessionData['waitlist'] ?? [];

      // Check if user is already registered in active list or waitlist
      final isAlreadyActive = activePlayers.any((p) => p['uid'] == currentUid);
      final isAlreadyWaitlisted = waitlist.any((p) => p['uid'] == currentUid);
      if (isAlreadyActive || isAlreadyWaitlisted) {
        return 'Already registered for this session';
      }

      final DateTime now = DateTime.now();
      final Duration timeToGame = gameTime.difference(now);
      final int minutesToGame = timeToGame.inMinutes;

      // Determine sign-up eligibility windows
      final bool residentWindowOpen = minutesToGame <= residentWindowStartMins && minutesToGame > outsiderWindowStartMins;
      final bool generalWindowOpen = minutesToGame <= outsiderWindowStartMins && minutesToGame > 0;

      if (minutesToGame <= 0) {
        return 'Registration is closed. Game has started.';
      }

      if (!residentWindowOpen && !generalWindowOpen) {
        return 'Registration has not opened yet. Resident window opens $residentWindowStartMins minutes before.';
      }

      // Prepare player map
      final Map<String, dynamic> playerMap = {
        'uid': currentUid,
        'name': userData['name'] ?? 'Anonymous Athlete',
        'phoneNumber': userData['phoneNumber'] ?? '',
        'checkedIn': false,
        'registeredAt': Timestamp.now(),
        'isResident': isResident,
        'isGuest': false,
      };

      if (residentWindowOpen) {
        // Resident window: only verified residents can register, up to residentSlots
        if (!isResident) {
          return 'Only verified local residents can register during the Resident Window.';
        }

        if (activePlayers.length < residentSlots) {
          activePlayers.add(playerMap);
          transaction.update(sessionRef, {'activePlayers': activePlayers});
          return 'Successfully registered!';
        } else {
          // Resident slots are full, join waitlist
          waitlist.add({
            'uid': currentUid,
            'name': userData['name'] ?? 'Anonymous Athlete',
            'phoneNumber': userData['phoneNumber'] ?? '',
            'joinedAt': Timestamp.now(),
            'isResident': isResident,
          });
          transaction.update(sessionRef, {'waitlist': waitlist});
          return 'Resident slots full. You have joined the waitlist.';
        }
      } else {
        // General window open: everyone can sign up for remaining spots up to totalSlots
        if (activePlayers.length < totalSlots) {
          activePlayers.add(playerMap);
          transaction.update(sessionRef, {'activePlayers': activePlayers});
          return 'Successfully registered!';
        } else {
          // General slots are full, join waitlist
          waitlist.add({
            'uid': currentUid,
            'name': userData['name'] ?? 'Anonymous Athlete',
            'phoneNumber': userData['phoneNumber'] ?? '',
            'joinedAt': Timestamp.now(),
            'isResident': isResident,
          });
          transaction.update(sessionRef, {'waitlist': waitlist});
          return 'Game is full. You have joined the waitlist.';
        }
      }
    });
  }

  // Cancel registration and promote waitlist
  Future<void> cancelRegistration(String sessionId) async {
    if (currentUid == null) return;

    final sessionRef = _db.collection('sessions').doc(sessionId);

    await _db.runTransaction((transaction) async {
      final sessionSnapshot = await transaction.get(sessionRef);
      if (!sessionSnapshot.exists) return;

      final sessionData = sessionSnapshot.data()!;
      final List<dynamic> activePlayers = List.from(sessionData['activePlayers'] ?? []);
      final List<dynamic> waitlist = List.from(sessionData['waitlist'] ?? []);

      // Check if user is in active list
      final int activeIndex = activePlayers.indexWhere((p) => p['uid'] == currentUid);
      if (activeIndex != -1) {
        activePlayers.removeAt(activeIndex);

        // Promote first waitlisted player if available
        if (waitlist.isNotEmpty) {
          final firstWaitlist = waitlist.removeAt(0);
          activePlayers.add({
            'uid': firstWaitlist['uid'],
            'name': firstWaitlist['name'],
            'phoneNumber': firstWaitlist['phoneNumber'],
            'checkedIn': false,
            'registeredAt': Timestamp.now(), // fresh registration timestamp for waitlist promotion
            'isResident': firstWaitlist['isResident'] ?? false,
            'isGuest': false,
          });
        }
        transaction.update(sessionRef, {
          'activePlayers': activePlayers,
          'waitlist': waitlist,
        });
        return;
      }

      // Check if user is in waitlist
      final int waitlistIndex = waitlist.indexWhere((p) => p['uid'] == currentUid);
      if (waitlistIndex != -1) {
        waitlist.removeAt(waitlistIndex);
        transaction.update(sessionRef, {'waitlist': waitlist});
      }
    });
  }

  // Athlete self-checkin via scanning check-in QR code
  Future<String> checkInViaQr(String sessionId) async {
    if (currentUid == null) return 'Not authenticated';

    final sessionRef = _db.collection('sessions').doc(sessionId);

    return await _db.runTransaction<String>((transaction) async {
      final sessionSnapshot = await transaction.get(sessionRef);
      if (!sessionSnapshot.exists) return 'Session not found';

      final sessionData = sessionSnapshot.data()!;
      final DateTime gameTime = (sessionData['gameTime'] as Timestamp).toDate();
      final List<dynamic> activePlayers = List.from(sessionData['activePlayers'] ?? []);

      // Verify player has a confirmed slot
      final int playerIndex = activePlayers.indexWhere((p) => p['uid'] == currentUid);
      if (playerIndex == -1) {
        return 'You do not have a confirmed slot for this game.';
      }

      final DateTime now = DateTime.now();
      final Duration timeToGame = gameTime.difference(now);

      // Check 10 minute cutoff
      if (timeToGame.inMinutes < 10 && !activePlayers[playerIndex]['checkedIn']) {
        return 'Too late to check in. Cutoff was 10 minutes before the game.';
      }

      // Mark checkedIn
      activePlayers[playerIndex]['checkedIn'] = true;
      transaction.update(sessionRef, {'activePlayers': activePlayers});
      return 'Check-in successful! Go play!';
    });
  }

  // Manager checks in walk-in guest (who has no phone)
  Future<void> checkInGuest(String sessionId, String guestName, String guestPhone) async {
    final sessionRef = _db.collection('sessions').doc(sessionId);

    await _db.runTransaction((transaction) async {
      final sessionSnapshot = await transaction.get(sessionRef);
      if (!sessionSnapshot.exists) return;

      final sessionData = sessionSnapshot.data()!;
      final List<dynamic> activePlayers = List.from(sessionData['activePlayers'] ?? []);
      final int totalSlots = sessionData['totalSlots'] ?? 20;

      if (activePlayers.length >= totalSlots) {
        throw Exception('Session is full. Cannot check in guest.');
      }

      activePlayers.add({
        'uid': 'guest_${DateTime.now().millisecondsSinceEpoch}',
        'name': guestName,
        'phoneNumber': guestPhone,
        'checkedIn': true,
        'registeredAt': Timestamp.now(),
        'isResident': false, // guests default to non-resident unless verified later
        'isGuest': true,
      });

      transaction.update(sessionRef, {'activePlayers': activePlayers});
    });
  }

  // Trigger Late Cutoff Checks (10 minutes before game time)
  // Auto-kicks non-checked in players, dishes out strikes, promotes waitlist.
  Future<void> triggerCutoffCheck(String sessionId) async {
    final sessionRef = _db.collection('sessions').doc(sessionId);

    await _db.runTransaction((transaction) async {
      final sessionSnapshot = await transaction.get(sessionRef);
      if (!sessionSnapshot.exists) return;

      final sessionData = sessionSnapshot.data()!;
      final DateTime gameTime = (sessionData['gameTime'] as Timestamp).toDate();
      final DateTime now = DateTime.now();

      final Duration timeToGame = gameTime.difference(now);

      // Cutoff only applies if we are within 10 minutes of the game starting (or after)
      if (timeToGame.inMinutes >= 10) {
        return; // Too early for cutoff check
      }

      final List<dynamic> activePlayers = List.from(sessionData['activePlayers'] ?? []);
      final List<dynamic> waitlist = List.from(sessionData['waitlist'] ?? []);

      final List<String> usersToStrike = [];
      final List<dynamic> remainingActive = [];

      for (var player in activePlayers) {
        if (player['checkedIn'] == true || player['isGuest'] == true) {
          remainingActive.add(player);
        } else {
          // Player failed to check in on time: Kicked and gets a strike
          final String uid = player['uid'];
          final Timestamp registeredAt = player['registeredAt'];
          
          // Check if waitlist-promoted < 15 minutes before game time.
          // Waitlist promotions are given a new registration timestamp.
          final Duration timeRegisteredBeforeGame = gameTime.difference(registeredAt.toDate());
          if (timeRegisteredBeforeGame.inMinutes >= 15) {
            // Did not check in and registered >=15 minutes before the game -> Strike!
            usersToStrike.add(uid);
          }
        }
      }

      // Promote waitlisted players to fill remaining spots
      final int totalSlots = sessionData['totalSlots'] ?? 20;
      while (remainingActive.length < totalSlots && waitlist.isNotEmpty) {
        final firstWaitlist = waitlist.removeAt(0);
        remainingActive.add({
          'uid': firstWaitlist['uid'],
          'name': firstWaitlist['name'],
          'phoneNumber': firstWaitlist['phoneNumber'],
          'checkedIn': false,
          'registeredAt': Timestamp.now(), // Promotion timestamp
          'isResident': firstWaitlist['isResident'] ?? false,
          'isGuest': false,
        });
      }

      // Apply changes to session
      transaction.update(sessionRef, {
        'activePlayers': remainingActive,
        'waitlist': waitlist,
      });

      // Award strikes to users who missed cutoff
      for (final uid in usersToStrike) {
        final userDocRef = _db.collection('users').doc(uid);
        final userSnapshot = await transaction.get(userDocRef);
        if (userSnapshot.exists) {
          final int currentStrikes = (userSnapshot.data()?['strikesCount'] ?? 0) + 1;
          
          DateTime? banUntil;
          if (currentStrikes == 1) {
            banUntil = now.add(const Duration(days: 7)); // Ban 1 week
          } else if (currentStrikes == 2) {
            banUntil = now.add(const Duration(days: 30)); // Ban 1 month (30 days)
          } else if (currentStrikes >= 3) {
            banUntil = now.add(const Duration(days: 36500)); // Permanent Ban (approx 100 years)
          }

          transaction.update(userDocRef, {
            'strikesCount': currentStrikes,
            'banUntil': banUntil != null ? Timestamp.fromDate(banUntil) : null,
          });
        }
      }
    });
  }

  // Admin manages Manager role promotion/demotion
  Future<void> updateUserRole(String athleteUid, String newRole) async {
    await _db.collection('users').doc(athleteUid).update({
      'role': newRole,
    });
  }

  // Admin / Manager creates a new session.
  // For recurring weekly sessions pass isRecurring=true with recurringDayOfWeek (1=Mon…7=Sun),
  // recurringTimeHour, and recurringTimeMinute. gameTime is omitted for recurring sessions
  // because it is computed client-side each time from the recurrence rule.
  // For one-time sessions pass isRecurring=false (or omit) and provide gameTime.
  Future<void> createSession({
    required String locationName,
    required int totalSlots,
    required int residentSlots,
    required int residentWindowStartMins,
    required int outsiderWindowStartMins,
    // One-time session fields
    DateTime? gameTime,
    // Recurring session fields
    bool isRecurring = false,
    int? recurringDayOfWeek,
    int? recurringTimeHour,
    int? recurringTimeMinute,
  }) async {
    final Map<String, dynamic> doc = {
      'locationName': locationName,
      'totalSlots': totalSlots,
      'residentSlots': residentSlots,
      'residentWindowStartMins': residentWindowStartMins,
      'outsiderWindowStartMins': outsiderWindowStartMins,
      'activePlayers': [],
      'waitlist': [],
      'isRecurring': isRecurring,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (isRecurring) {
      doc['recurringDayOfWeek'] = recurringDayOfWeek;
      doc['recurringTimeHour'] = recurringTimeHour;
      doc['recurringTimeMinute'] = recurringTimeMinute;
    } else {
      doc['gameTime'] = Timestamp.fromDate(gameTime!);
    }

    await _db.collection('sessions').add(doc);
  }
}
