import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/admin_dashboard.dart';
import 'screens/athlete_dashboard.dart';
import 'screens/auth_screen.dart';
import 'screens/manager_dashboard.dart';
import 'screens/waiver_screen.dart';
import 'services/firebase_service.dart';
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
    final FirebaseService fbService = FirebaseService();

    return StreamBuilder(
      stream: fbService.streamUserData(),
      builder: (context, userSnapshot) {
        // If not authenticated (or user document stream is empty/waiting without data)
        if (fbService.currentUid == null) {
          return const AuthScreen();
        }

        if (userSnapshot.hasError) {
          return Scaffold(
            body: Center(child: Text("Database Error: ${userSnapshot.error}")),
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
          // Fallback if auth exists but Firestore document is not created yet
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
  }
}
