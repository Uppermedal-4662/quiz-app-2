import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../providers/cloud_provider.dart';

class UserMessagesScreen extends StatefulWidget {
  const UserMessagesScreen({super.key});

  @override
  State<UserMessagesScreen> createState() => _UserMessagesScreenState();
}

class _UserMessagesScreenState extends State<UserMessagesScreen> {
  void _showSendMessageDialog() {
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudProvider>();
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Message to Admin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Send a message to the Super Admin. Limit: 5 per day.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Your message...'),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              try {
                await cloud.sendMessageToAdmin(auth.user!.uid, auth.user!.email!, controller.text.trim());
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message sent!')));
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    if (auth.isGuest) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Messages')),
        body: const Center(child: Text('Please log in to view your messages.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Messages'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showSendMessageDialog,
        label: const Text('New Message'),
        icon: const Icon(Icons.send),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('messages')
            .where('sender_uid', isEqualTo: auth.user!.uid)
            // Removed orderBy to avoid composite index requirements. 
            // We sort in memory instead.
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          // Sort in memory by timestamp descending
          final docs = snapshot.data?.docs ?? [];
          final messages = docs.toList();
          messages.sort((a, b) {
            final t1 = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
            final t2 = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
            if (t1 == null) return 1;
            if (t2 == null) return -1;
            return t2.compareTo(t1);
          });

          if (messages.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.message_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No messages sent yet.', style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('Tap the button below to send your first message.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80), // Extra bottom padding for FAB
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index].data() as Map<String, dynamic>;
              final date = (msg['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
              final reply = msg['reply'] as String?;
              final replyAt = msg['replied_at'] as Timestamp?;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.person, size: 16, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('Your Message', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                            ],
                          ),
                          Text(
                            DateFormat('MMM d, HH:mm').format(date),
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(msg['message'] ?? '', style: const TextStyle(fontSize: 15)),
                      if (reply != null) ...[
                        const Divider(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.admin_panel_settings, size: 16, color: Colors.green),
                                SizedBox(width: 8),
                                Text('Admin Reply', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                              ],
                            ),
                            if (replyAt != null)
                              Text(
                                DateFormat('MMM d, HH:mm').format(replyAt.toDate()),
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green[100]!),
                          ),
                          child: Text(
                            reply,
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ),
                      ] else ...[
                        const Divider(height: 32),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.hourglass_empty, size: 14, color: Colors.orange),
                              SizedBox(width: 8),
                              Text(
                                'Waiting for admin reply...',
                                style: TextStyle(fontSize: 12, color: Colors.orange, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
