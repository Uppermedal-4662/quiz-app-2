import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/cloud_provider.dart';
import '../../services/auth_service.dart';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  late Future<List<Map<String, dynamic>>> _usersFuture;
  List<Map<String, dynamic>> _allBanks = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _usersFuture = context.read<CloudProvider>().getAllUsers();
    });
    context.read<CloudProvider>().getAllBanks().then((banks) {
      if (mounted) setState(() => _allBanks = banks);
    });
  }

  void _showPermissionsDialog(Map<String, dynamic> user) async {
    final cloud = context.read<CloudProvider>();
    List<String> userBanks = List<String>.from(user['accessible_banks'] ?? []);
    String userRole = user['role'] ?? 'user';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Manage ${user['email']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('User Role', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: userRole,
                  isExpanded: true,
                  items: ['user', 'admin'].map((r) => DropdownMenuItem(value: r, child: Text(r.toUpperCase()))).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => userRole = val);
                  },
                ),
                const SizedBox(height: 24),
                const Text('Question Bank Access', style: TextStyle(fontWeight: FontWeight.bold)),
                if (_allBanks.isEmpty) const Text('No banks available.'),
                ..._allBanks.map((bank) {
                  bool hasAccess = userBanks.contains(bank['bank_id']);
                  return CheckboxListTile(
                    title: Text(bank['name']),
                    value: hasAccess,
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) {
                          userBanks.add(bank['bank_id'] as String);
                        } else {
                          userBanks.remove(bank['bank_id'] as String);
                        }
                      });
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await cloud.updateUserRole(user['uid'], userRole);
                  await cloud.updateUserPermissions(user['uid'], userBanks);
                  if (mounted) {
                    Navigator.pop(context);
                    _refresh();
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin'),
        actions: [
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/home'),
            icon: const Icon(Icons.quiz),
            tooltip: 'Go to Local Quiz',
          ),
          IconButton(onPressed: () => context.read<AuthService>().signOut(), icon: const Icon(Icons.logout)),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _usersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          final users = snapshot.data ?? [];

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              if (user['role'] == 'super_admin') return const SizedBox.shrink(); // Hide self

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(child: Text(user['role'][0].toUpperCase())),
                  title: Text(user['email'] ?? 'No Email'),
                  subtitle: Text('Role: ${user['role'].toUpperCase()} | Banks: ${(user['accessible_banks'] as List?)?.length ?? 0}'),
                  trailing: const Icon(Icons.manage_accounts),
                  onTap: () => _showPermissionsDialog(user),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
