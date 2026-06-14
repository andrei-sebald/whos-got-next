import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/admin_dashboard.dart';
import 'screens/athlete_dashboard.dart';
import 'screens/auth_screen.dart';
import 'screens/manager_dashboard.dart';
import 'screens/waiver_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const WhosGotNextApp());
}

class WhosGotNextApp extends StatelessWidget {
  const WhosGotNextApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Who's Got Next",
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen to Firebase Auth state changes as the outer stream.
    // This ensures the widget rebuilds when the user signs in or out.
    // Previously this was broken because streamUserData() returned
    // Stream.empty() when no user was signed in, so it never re-emitted on login.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        // Still initialising the Auth SDK
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          );
        }

        final user = authSnapshot.data;

        // No signed-in user: show login screen
        if (user == null) {
          return const AuthScreen();
        }

        // User is signed in: stream their Firestore document
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Text('Database Error: ${userSnapshot.error}'),
                ),
              );
            }

            // Display loading spinner while loading user profile
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              );
            }

            final userDoc = userSnapshot.data;
            if (userDoc == null || !userDoc.exists) {
              // Auth exists but Firestore doc not created yet. Stay on AuthScreen
              // so the new-user name flow can complete and write the document.
              return const AuthScreen();
            }

            final userData = userDoc.data()!;
            final bool hasSignedWaiver = userData['hasSignedWaiver'] ?? false;

            // Force waiver sign-off if the user has not signed yet
            if (!hasSignedWaiver) {
              return const WaiverScreen();
            }

            // Routing based on User Role
            final String role = userData['role'] ?? 'athlete';
            switch (role) {
              case 'admin':
                return AdminDashboard(userData: userData);
              case 'manager':
                return ManagerDashboard(userData: userData);
              case 'athlete':
              default:
                return AthleteDashboard(userData: userData);
            }
          },
        );
      },
    );
  }
}
