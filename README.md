# Who's Got Next - Community Basketball Sign-up App

**Who's Got Next** is a cross-platform mobile application (iOS & Android) designed for local community centers to streamline basketball open-run sign-ups. It eliminates the need to stand in physical lines, prioritizes local residents, and keeps rosters full and games active.

---

## 🏀 The Problem & Solution
*   **The Problem:** Currently, community members must show up nearly an hour early to wait in line. Only 20 players get in 15 minutes before the game, resulting in wasted time and players driving to the gym only to find it full.
*   **The Solution:** An automated two-tiered online sign-up system opening a few hours before the game. It prioritizes local community members, leverages a real-time waitlist, and enforces strict check-in cutoffs with penalty strikes for no-shows to keep player spots active.

---

## ✨ Features & Architecture

### 1. Three User Roles
*   **Athlete (Player):**
    *   Register for open runs (subject to sign-up windows).
    *   View status (Confirmed, Waitlisted, or Banned).
    *   One-time Liability Waiver signing on registration.
    *   Upload proof of residency (e.g. utility bill, lease agreement) to get verified.
    *   Scan front-desk QR code to check in and verify attendance.
    *   Submit strike appeals if banned.
*   **Manager (Gym Staff):**
    *   Create and schedule game sessions (configure slots and windows).
    *   Generate and display the check-in QR code at the front counter.
    *   Review and approve/reject uploaded address documents.
    *   Approve walk-in guest check-ins (players without phones, exempt from strikes).
    *   Manage the Strike Appeals Board (forgiving or denying appeals).
    *   Force cutoff checks manually if needed.
*   **Admin:**
    *   Includes all Manager features.
    *   Dedicated user management directory to promote/demote members to/from Manager and Admin roles.

### 2. Sign-Up Windows & Digital Waitlist
*   **Resident Window ($T-2$ hours to $T-1$ hour):** Only verified residents can register. Capped at a manager-configured slot count (e.g., 10 spots).
*   **General Window ($T-1$ hour to Game Time):** Open to both residents and non-residents to fill all remaining spots up to total session capacity.
*   **Real-time Waitlist:** If confirmed spots are full, athletes join the waitlist queue. If a confirmed player cancels or gets kicked, the waitlist promotes the next player automatically.

### 3. Check-In Cutoff & Penalty System
*   **10-Minute Cutoff:** All confirmed players must pay at the counter and scan the desk QR code at least **10 minutes before** game time.
*   **Late Kick:** Unchecked players are automatically kicked at $T-10$ minutes, and waitlisted players are promoted.
*   **No-Show Strikes:** Players who fail to check in receive a strike.
    *   *Exemption:* If a waitlist player is promoted **less than 15 minutes** before game time, they do not receive a strike if they fail to check in.
*   **Strike Ban Bands:**
    *   **1st Strike:** Banned from signing up for **7 days**.
    *   **2nd Strike:** Banned from signing up for **30 days**.
    *   **3rd Strike:** **Permanently banned** from the platform.
*   **Appeals:** Banned players can submit an appeal text explaining their absence. Managers can approve the appeal to remove the strike and lift the ban.

---

## 🛠 Tech Stack
*   **Frontend Framework:** Flutter (Dart) for native iOS and Android.
*   **State Management:** Provider
*   **Database:** Cloud Firestore (NoSQL)
*   **Authentication:** Firebase Auth (Phone OTP verification to prevent ban-dodging accounts).
*   **Storage:** Firebase Storage (holds residency proof photos).
*   **Styling:** A premium sporty dark theme built with high contrast slate/charcoal backgrounds, vibrant court-orange primary accents, and neon cyan check-in success badges.

---

## 🚀 Getting Started (Local Development)

### Prerequisites
*   [Flutter SDK](https://docs.flutter.dev/get-started/install) installed on your system.
*   [Node.js](https://nodejs.org/) (version >=20) and [Firebase CLI](https://firebase.google.com/docs/cli) installed.
*   CocoaPods (for running on iOS: `sudo gem install cocoapods`).

### 1. Database Setup & Rules Deployment
Log in to your Firebase account and select your project context:
```bash
npx firebase-tools login
npx firebase-tools use whos-got-next-49b55
```
Deploy the security rules (`firestore.rules`) to Firestore:
```bash
npx firebase-tools deploy --only firestore
```

### 2. Configure Auth and Storage
1. Go to your [Firebase Console](https://console.firebase.google.com/).
2. Navigate to **Authentication** -> **Sign-in Method** and enable **Phone**.
3. Navigate to **Storage** and initialize a storage bucket (to host residency proof files).

### 3. Install Packages & Run
Retrieve dependencies:
```bash
flutter pub get
```
Run the application on a connected device or simulator:
```bash
flutter run
```

---

## 📂 Project Directory Structure
```
├── android/            # Android native runner
├── ios/                # iOS native runner
├── firestore.rules     # Database rules
├── firebase.json       # Firebase CLI config
├── pubspec.yaml        # Flutter packages and assets
├── lib/
│   ├── main.dart       # App entry and wrapper routing
│   ├── theme.dart      # Sporty theme customization
│   ├── services/
│   │   └── firebase_service.dart  # Data mutations, signup window, waitlist, cutoff, appeals logic
│   └── screens/
│       ├── auth_screen.dart       # Phone registration and OTP verification
│       ├── waiver_screen.dart     # Scrollable liability waiver form
│       ├── athlete_dashboard.dart # Athlete feeds, sign-up flows, QR camera scanner, addresses
│       ├── manager_dashboard.dart # Schedule editor, desk QR generator, guests list, appeals queue
│       └── admin_dashboard.dart   # Role manager directory
```
