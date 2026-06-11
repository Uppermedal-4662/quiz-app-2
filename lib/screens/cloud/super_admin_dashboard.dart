import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  
  // Search state
  final TextEditingController _userSearchController = TextEditingController();
  final TextEditingController _inboxSearchController = TextEditingController();
  String _userSearchQuery = "";
  String _inboxSearchQuery = "";

  @override
  void initState() {
    super.initState();
    _refresh();
    _userSearchController.addListener(() {
      setState(() => _userSearchQuery = _userSearchController.text.toLowerCase());
    });
    _inboxSearchController.addListener(() {
      setState(() => _inboxSearchQuery = _inboxSearchController.text.toLowerCase());
    });
  }

  void _refresh() {
    setState(() {
      _usersFuture = context.read<CloudProvider>().getAllUsers();
    });
    context.read<CloudProvider>().getAllBanks().then((banks) {
      if (mounted) setState(() => _allBanks = banks);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
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
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people), text: 'Users'),
              Tab(icon: Icon(Icons.settings), text: 'Config'),
              Tab(icon: Icon(Icons.inbox), text: 'Inbox'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildUsersTab(),
            _buildConfigTab(),
            _buildInboxTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _usersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        
        final allUsers = snapshot.data ?? [];
        final users = allUsers.where((u) {
          final email = (u['email'] ?? '').toString().toLowerCase();
          return email.contains(_userSearchQuery);
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                controller: _userSearchController,
                decoration: InputDecoration(
                  hintText: 'Search users by email...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];
                  if (user['role'] == 'super_admin') return const SizedBox.shrink();

                  final bool isDisabled = user['is_disabled'] ?? false;

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: isDisabled ? Colors.red[50] : null,
                    child: ListTile(
                      leading: CircleAvatar(child: Text(user['role'][0].toUpperCase())),
                      title: Text(user['email'] ?? 'No Email'),
                      subtitle: Text('Role: ${user['role'].toUpperCase()} | Banks: ${(user['accessible_banks'] as List?)?.length ?? 0}'),
                      trailing: const Icon(Icons.manage_accounts),
                      onTap: () => _showManageUserDialog(user),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _showManageUserDialog(Map<String, dynamic> user) async {
    final cloud = context.read<CloudProvider>();
    List<String> userBanks = List<String>.from(user['accessible_banks'] ?? []);
    String userRole = user['role'] ?? 'user';
    
    bool isDisabled = user['is_disabled'] ?? false;
    bool canMessage = user['can_message'] ?? true;
    bool canAccessQuizzes = user['can_access_quizzes'] ?? true;
    bool canViewInbox = user['can_view_inbox'] ?? false;

    // Local dialog state for filtering banks
    String bankFilter = "";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Group banks by category
          final Map<String, List<Map<String, dynamic>>> groupedBanks = {};
          for (var b in _allBanks) {
            final name = b['name'].toString().toLowerCase();
            final cat = (b['category'] ?? 'Uncategorized').toString();
            if (name.contains(bankFilter.toLowerCase()) || cat.toLowerCase().contains(bankFilter.toLowerCase())) {
              groupedBanks.putIfAbsent(cat, () => []).add(b);
            }
          }

          return AlertDialog(
            title: Text('Manage ${user['email']}'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Account Status', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    SwitchListTile(
                      title: const Text('Disable Account'),
                      value: isDisabled,
                      onChanged: (v) => setDialogState(() => isDisabled = v),
                    ),
                    SwitchListTile(
                      title: const Text('Allow Messaging'),
                      value: canMessage,
                      onChanged: (v) => setDialogState(() => canMessage = v),
                    ),
                    SwitchListTile(
                      title: const Text('Allow Quiz Access'),
                      value: canAccessQuizzes,
                      onChanged: (v) => setDialogState(() => canAccessQuizzes = v),
                    ),
                    const Divider(),
                    const Text('Role', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    DropdownButton<String>(
                      value: userRole,
                      isExpanded: true,
                      items: ['user', 'admin'].map((r) => DropdownMenuItem(value: r, child: Text(r.toUpperCase()))).toList(),
                      onChanged: (val) => setDialogState(() => userRole = val!),
                    ),
                    if (userRole == 'admin')
                      CheckboxListTile(
                        title: const Text('Grant Inbox Access'),
                        value: canViewInbox,
                        onChanged: (v) => setDialogState(() => canViewInbox = v ?? false),
                      ),
                    const Divider(),
                    const Text('Permissions (Bank Access)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (v) => setDialogState(() => bankFilter = v),
                      decoration: const InputDecoration(hintText: 'Search banks...', prefixIcon: Icon(Icons.search), isDense: true),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(
                          value: _allBanks.isNotEmpty && userBanks.length == _allBanks.length,
                          tristate: true,
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) userBanks = _allBanks.map((b) => b['bank_id'] as String).toList();
                              else userBanks = [];
                            });
                          },
                        ),
                        const Text('Select All Banks', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    ...groupedBanks.entries.map((entry) {
                      final category = entry.key;
                      final banksInCat = entry.value;
                      final allIdsInCat = banksInCat.map((b) => b['bank_id'] as String).toList();
                      bool allSelected = allIdsInCat.every((id) => userBanks.contains(id));

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            color: Colors.grey[200],
                            width: double.infinity,
                            child: Row(
                              children: [
                                Checkbox(
                                  visualDensity: VisualDensity.compact,
                                  value: allSelected,
                                  onChanged: (val) {
                                    setDialogState(() {
                                      if (val == true) {
                                        for (var id in allIdsInCat) { if (!userBanks.contains(id)) userBanks.add(id); }
                                      } else {
                                        for (var id in allIdsInCat) { userBanks.remove(id); }
                                      }
                                    });
                                  },
                                ),
                                Text(category.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                          ),
                          ...banksInCat.map((bank) {
                            final bid = bank['bank_id'] as String;
                            return CheckboxListTile(
                              title: Text(bank['name']),
                              value: userBanks.contains(bid),
                              onChanged: (v) {
                                setDialogState(() {
                                  if (v == true) userBanks.add(bid);
                                  else userBanks.remove(bid);
                                });
                              },
                            );
                          }),
                        ],
                      );
                    }),
                    const Divider(),
                    Center(
                      child: TextButton.icon(
                        onPressed: () async {
                          try {
                            await FirebaseAuth.instance.sendPasswordResetEmail(email: user['email']);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset email sent!')));
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                          }
                        },
                        icon: const Icon(Icons.lock_reset),
                        label: const Text('Send Password Reset Link'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await cloud.updateUserRole(user['uid'], userRole);
                    await cloud.updateUserPermissions(user['uid'], userBanks);
                    await cloud.updateUserBanStatus(user['uid'],
                      isDisabled: isDisabled,
                      canMessage: canMessage,
                      canAccessQuizzes: canAccessQuizzes,
                      canViewInbox: canViewInbox,
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      _refresh();
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConfigTab() {
    final cloud = context.read<CloudProvider>();
    final auth = context.read<AuthService>();
    final greetingController = TextEditingController();
    final contactController = TextEditingController();

    return FutureBuilder<Map<String, dynamic>>(
      future: cloud.getAppConfig(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final config = snapshot.data ?? {};
        greetingController.text = config['greeting_message'] ?? '';
        contactController.text = config['contact_info'] ?? '';

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('App Greeting Message', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: greetingController,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Welcome to Quiz AI!'),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              const Text('Contact Information', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: contactController,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Support: support@example.com'),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () async {
                  await cloud.updateAppConfig({
                    'greeting_message': greetingController.text,
                    'contact_info': contactController.text,
                    'super_admin_email': auth.user?.email,
                  });
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Config updated!')));
                },
                child: const Text('SAVE CONFIG'),
              ),
              const SizedBox(height: 16),
              Text('Super Admin: ${auth.user?.email}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInboxTab() {
    final cloud = context.read<CloudProvider>();
    final auth = context.read<AuthService>();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: cloud.getAdminInbox(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final allMessages = snapshot.data ?? [];
        
        final messages = allMessages.where((m) {
          final email = (m['sender_email'] ?? '').toString().toLowerCase();
          final text = (m['message'] ?? '').toString().toLowerCase();
          return email.contains(_inboxSearchQuery) || text.contains(_inboxSearchQuery);
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                controller: _inboxSearchController,
                decoration: InputDecoration(
                  hintText: 'Search inbox...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
            ),
            Expanded(
              child: messages.isEmpty 
                ? const Center(child: Text('No messages found.'))
                : ListView.builder(
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final date = (msg['timestamp'] as dynamic)?.toDate() ?? DateTime.now();
                      final reply = msg['reply'] as String?;
                      final replyController = TextEditingController();

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(msg['sender_email'] ?? 'Anonymous', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text(DateFormat('MMM d, HH:mm').format(date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(msg['message'] ?? ''),
                              const Divider(height: 24),
                              if (reply != null) ...[
                                const Text('Admin Reply:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12)),
                                Text(reply, style: const TextStyle(fontStyle: FontStyle.italic)),
                                const SizedBox(height: 4),
                                Text('By ${msg['replied_by']} on ${DateFormat('MMM d, HH:mm').format((msg['replied_at'] as dynamic).toDate())}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              ] else ...[
                                Row(
                                  children: [
                                    Expanded(child: TextField(controller: replyController, decoration: const InputDecoration(hintText: 'Type reply...', isDense: true))),
                                    IconButton(
                                      onPressed: () async {
                                        if (replyController.text.trim().isEmpty) return;
                                        await cloud.replyToMessage(msg['id'], auth.user!.email!, replyController.text.trim());
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.send, color: Colors.blue),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ],
        );
      },
    );
  }
}
