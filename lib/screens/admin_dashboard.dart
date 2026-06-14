import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../theme.dart';
import 'manager_dashboard.dart';

class AdminDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  const AdminDashboard({super.key, required this.userData});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final FirebaseService _fbService = FirebaseService();
  final _db = FirebaseFirestore.instance;
  final _searchController = TextEditingController();

  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    // Admin panel wraps the ManagerDashboard but includes an overlay / route to User Management
    return Scaffold(
      body: Stack(
        children: [
          // Underlying Manager view (gives Admins all Manager tools)
          ManagerDashboard(userData: widget.userData),
          
          // User Management floating action button
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.extended(
              onPressed: _showUserManagementModal,
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.people, color: AppTheme.textPrimary),
              label: const Text("USER ROLES", style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  // Display User Roles Management Modal
  void _showUserManagementModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Manage User Roles",
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppTheme.primary, fontSize: 20),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchController,
                      onChanged: (val) {
                        setModalState(() {
                          _searchQuery = val.trim().toLowerCase();
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: "Search by phone or name",
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _db.collection('users').snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
                          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                          final docs = snapshot.data?.docs ?? [];
                          
                          // Filter users based on query
                          final filteredUsers = docs.where((doc) {
                            final data = doc.data();
                            final name = (data['name'] ?? '').toString().toLowerCase();
                            final phone = (data['phoneNumber'] ?? '').toString().toLowerCase();
                            return name.contains(_searchQuery) || phone.contains(_searchQuery);
                          }).toList();

                          if (filteredUsers.isEmpty) {
                            return const Center(child: Text("No users found.", style: TextStyle(color: AppTheme.textSecondary)));
                          }

                          return ListView.builder(
                            itemCount: filteredUsers.length,
                            itemBuilder: (context, index) {
                              final doc = filteredUsers[index];
                              final data = doc.data();
                              final String uid = doc.id;
                              final String name = data['name'] ?? 'Athlete';
                              final String phone = data['phoneNumber'] ?? '';
                              final String currentRole = data['role'] ?? 'athlete';

                              // Exclude current admin from self-demotion to avoid locking out the admin role
                              final bool isSelf = uid == _fbService.currentUid;

                              return ListTile(
                                title: Text(name),
                                subtitle: Text("$phone  |  Role: ${currentRole.toUpperCase()}"),
                                trailing: isSelf
                                    ? const Text("YOU", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.success))
                                    : DropdownButton<String>(
                                        value: currentRole,
                                        items: ['athlete', 'manager', 'admin'].map((role) {
                                          return DropdownMenuItem<String>(
                                            value: role,
                                            child: Text(role.toUpperCase()),
                                          );
                                        }).toList(),
                                        onChanged: (newRole) async {
                                          if (newRole != null && newRole != currentRole) {
                                            await _fbService.updateUserRole(uid, newRole);
                                            _showSnackBar("Updated $name's role to ${newRole.toUpperCase()}");
                                            setModalState(() {});
                                          }
                                        },
                                      ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
